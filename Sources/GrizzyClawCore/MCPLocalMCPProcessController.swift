import Foundation

public enum MCPLocalMCPError: LocalizedError {
    case noCommand
    case commandNotFound(String)
    case startFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noCommand: return "No command defined for this server."
        case .commandNotFound(let c): return "Command not found: \(c). Install it or ensure PATH includes Homebrew and npm (e.g. /opt/homebrew/bin)."
        case .startFailed(let s): return s
        }
    }
}

/// Starts/stops local MCP stdio processes — Python `MCPTab.toggle_mcp_connection` (subprocess + `pgrep` fallback).
/// Process I/O and waits run off the main thread so the UI never beach-balls (npx / `ps` / terminate loops).
/// `entries` are guarded by `stateLock`; `@unchecked Sendable` satisfies the `shared` singleton and GCD closures.
public final class MCPLocalMCPProcessController: ObservableObject, @unchecked Sendable {
    public static let shared = MCPLocalMCPProcessController()

    private final class ServerDataBox: @unchecked Sendable {
        let value: [String: Any]

        init(_ value: [String: Any]) {
            self.value = value
        }
    }

    private struct Entry {
        var process: Process
        /// Keep stdin write handle open so the child does not get EOF (Python `stdin=subprocess.PIPE`).
        var stdinWriter: FileHandle
        var stderrPipe: Pipe
        /// `npx`/`uvx` wrappers often exit while the real MCP stays alive as a `node …` child. We then match via `ps` instead of `process.isRunning`.
        var psGhost: Bool
        /// Specific PID of the child process if discovered (more robust than broad pattern matching).
        var ghostPid: Int32?
    }

    private var entries: [String: Entry] = [:]
    private let stateLock = NSLock()

    private init() {}

    /// True if we launched this session’s process and it is still running (or `ps` says the MCP child is still up).
    public func isTrackedRunning(name: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let e = entries[name] else { return false }
        if e.process.isRunning { return true }
        if let gpid = e.ghostPid {
            return Self.isPidAlive(gpid)
        }
        return e.psGhost
    }

    private static func isPidAlive(_ pid: Int32) -> Bool {
        let k = Process()
        k.executableURL = URL(fileURLWithPath: "/bin/kill")
        k.arguments = ["-0", String(pid)]
        try? k.run()
        k.waitUntilExit()
        return k.terminationStatus == 0
    }

    /// Clears **psGhost** rows when `ps` no longer shows the MCP (child truly exited).
    public func reconcilePsGhosts(rows: [MCPServerRow]) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var changed = false
            self.stateLock.lock()
            for row in rows {
                let record = row.mergedRecord()
                guard let name = record["name"] as? String else { continue }
                guard let entry = self.entries[name], entry.psGhost else { continue }
                guard record["command"] != nil else { continue }
                let eval = MCPServerRuntimeStatus.evaluateLocalRunning(serverData: record)
                if !eval.running {
                    GrizzyClawLog.debug("MCP reconcilePsGhosts: remove name=\(name) — \(eval.detail)")
                    self.entries.removeValue(forKey: name)
                    changed = true
                }
            }
            self.stateLock.unlock()
            if changed {
                DispatchQueue.main.async { self.objectWillChange.send() }
            }
        }
    }

    /// Spawns the MCP process on a background queue; safe to call from the main thread.
    /// Important: **`cont.resume()` must not be scheduled only with `DispatchQueue.main.async`** when the caller
    /// awaits on the MainActor — the main queue cannot drain that block until the await finishes (deadlock).
    public func start(serverData: [String: Any]) async throws {
        let serverDataBox = ServerDataBox(serverData)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.performStart(serverData: serverDataBox.value)
                    cont.resume()
                    DispatchQueue.main.async {
                        self.objectWillChange.send()
                    }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func performStart(serverData: [String: Any]) throws {
        guard let cmd = serverData["command"] as? String, !cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPLocalMCPError.noCommand
        }
        let name = (serverData["name"] as? String) ?? "unknown"

        stateLock.lock()
        if let e = entries[name], e.process.isRunning {
            GrizzyClawLog.debug("MCP performStart: skip name=\(name) — already running pid=\(e.process.processIdentifier)")
            stateLock.unlock()
            return
        }
        if entries[name] != nil {
            GrizzyClawLog.debug("MCP performStart: replacing stale entry name=\(name)")
            entries.removeValue(forKey: name)
        }
        stateLock.unlock()

        let args = MCPServerRuntimeStatus.normalizeMCPArgs(serverData["args"])
        guard let exe = Self.resolveExecutable(cmd) else {
            throw MCPLocalMCPError.commandNotFound(cmd)
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args

        let env = Self.expandedEnvironment(merging: serverData["env"] as? [String: Any])
        p.environment = env

        let stdinPipe = Pipe()
        p.standardInput = stdinPipe
        p.standardOutput = Self.nullWriteHandle()
        let stderrPipe = Pipe()
        p.standardError = stderrPipe

        do {
            try p.run()
        } catch {
            throw MCPLocalMCPError.startFailed(error.localizedDescription)
        }

        GrizzyClawLog.debug("MCP performStart: name=\(name) pid=\(p.processIdentifier) exe=\(exe) args=\(args.prefix(6).map { String(describing: $0) }.joined(separator: " "))\(args.count > 6 ? " …" : "")")

        let entry = Entry(process: p, stdinWriter: stdinPipe.fileHandleForWriting, stderrPipe: stderrPipe, psGhost: false)
        stateLock.lock()
        entries[name] = entry
        let trackedNames = Array(entries.keys).sorted()
        stateLock.unlock()
        GrizzyClawLog.debug("MCP entries after start: count=\(trackedNames.count) names=[\(trackedNames.joined(separator: ", "))]")

        let serverDataBox = ServerDataBox(serverData)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.checkStartedProcessStillRunning(name: name, serverData: serverDataBox.value)
        }
    }

    /// Stops on a background queue (terminate wait and `pgrep` never block the UI).
    public func stop(serverData: [String: Any]) {
        let serverDataBox = ServerDataBox(serverData)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.performStop(serverData: serverDataBox.value)
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }

    /// Same as ``stop`` but waits until terminate / `kill` work finishes. Use when updating UI (`runningMap`)
    /// so `ps`-based status does not stay stale while tracking has already cleared.
    public func stopAwaitingCompletion(serverData: [String: Any]) async {
        let serverDataBox = ServerDataBox(serverData)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    cont.resume()
                    return
                }
                self.performStop(serverData: serverDataBox.value)
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    cont.resume()
                }
            }
        }
    }

    private func performStop(serverData: [String: Any]) {
        let name = (serverData["name"] as? String) ?? ""

        stateLock.lock()
        let entry = entries.removeValue(forKey: name)
        stateLock.unlock()
        GrizzyClawLog.debug("MCP performStop: name=\(name) hadEntry=\(entry != nil)")

        if let e = entry {
            if e.process.isRunning {
                e.process.terminate()
                let deadline = Date().addingTimeInterval(3)
                while e.process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if e.process.isRunning {
                    e.process.interrupt()
                    e.process.waitUntilExit()
                }
            }
            if let gpid = e.ghostPid {
                Self.killPid(String(gpid))
            }
            try? e.stdinWriter.close()
        }

        Self.killViaPgrep(serverData: serverData)
    }

    private func checkStartedProcessStillRunning(name: String, serverData: [String: Any]) {
        stateLock.lock()
        guard var e = entries[name] else {
            stateLock.unlock()
            return
        }
        if e.process.isRunning {
            GrizzyClawLog.debug("MCP checkStartedProcessStillRunning: name=\(name) direct child pid still running")
            stateLock.unlock()
            return
        }

        // Wrapper exited; child may still be running under another PID (see `psGhost`).
        // We try to find the specific PID to be more robust.
        let patterns = MCPServerRuntimeStatus.matchPatterns(serverData: serverData)
        let myPid = String(ProcessInfo.processInfo.processIdentifier)
        var foundPid: Int32? = nil
        for pat in patterns where pat.count >= 15 {
            let pids = Self.pgrepFull(pattern: pat).filter { $0 != myPid }
            if pids.count == 1, let first = Int32(pids[0]) {
                foundPid = first
                break
            }
        }

        let eval = MCPServerRuntimeStatus.evaluateLocalRunning(serverData: serverData)
        if eval.running {
            e.psGhost = true
            e.ghostPid = foundPid
            entries[name] = e
            GrizzyClawLog.debug("MCP checkStartedProcessStillRunning: name=\(name) psGhost=true gpid=\(foundPid ?? -1) — \(eval.detail)")
            stateLock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.objectWillChange.send()
            }
            return
        }

        GrizzyClawLog.debug("MCP checkStartedProcessStillRunning: name=\(name) removing entry — \(eval.detail)")
        entries.removeValue(forKey: name)
        let stderrPipe = e.stderrPipe
        let terminationStatus = e.process.terminationStatus
        stateLock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }

        var err = ""
        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            err = s
        }
        if err.isEmpty {
            err = "Process exited with code \(terminationStatus)."
        }
        var hint = ""
        if name.lowercased().contains("playwright") || err.lowercased().contains("playwright") || err.lowercased().contains("executable") {
            hint = "\n\nTo fix: run in a terminal:\n  playwright install chromium"
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .mcpLocalProcessExitedEarly,
                object: nil,
                userInfo: [
                    "name": name,
                    "detail": String(err.prefix(800)) + hint,
                ]
            )
        }
    }

    private static func nullWriteHandle() -> FileHandle {
        if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null")) {
            return h
        }
        return Pipe().fileHandleForWriting
    }

    /// Same PATH expansion as `start`, exposed for native MCP stdio clients.
    public static func expandedEnvironmentForMCP(merging extra: [String: Any]?) -> [String: String] {
        expandedEnvironment(merging: extra)
    }

    private static func expandedEnvironment(merging extra: [String: Any]?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extras = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin",
            "/usr/local/bin", "/usr/local/sbin",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/versions/node/current/bin").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".volta/bin").path,
            "/usr/local/opt/node/bin", "/opt/homebrew/opt/node/bin",
            "/usr/bin", "/bin",
        ]
        var pathParts = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for p in extras where FileManager.default.fileExists(atPath: p) && !pathParts.contains(p) {
            pathParts.insert(p, at: 0)
        }
        env["PATH"] = pathParts.joined(separator: ":")
        if let extra {
            for (k, v) in extra {
                env[String(describing: k)] = String(describing: v)
            }
        }
        return env
    }

    /// Resolves a command name or path for spawning MCP stdio servers (same search PATH as `start`).
    public static func resolveExecutable(_ command: String) -> String? {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if cmd.isEmpty { return nil }
        if cmd.contains("/") {
            let p = (cmd as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        let path = expandedEnvironment(merging: nil)["PATH"] ?? ""
        for dir in path.split(separator: ":") {
            let full = URL(fileURLWithPath: String(dir)).appendingPathComponent(cmd).path
            if FileManager.default.isExecutableFile(atPath: full) { return full }
        }
        return nil
    }

    private static func killViaPgrep(serverData: [String: Any]) {
        let myPid = String(ProcessInfo.processInfo.processIdentifier)
        let patterns = MCPServerRuntimeStatus.matchPatterns(serverData: serverData)
        var seen = Set<String>()
        // ONLY use very specific patterns for kill to avoid collateral damage.
        // We prefer the full command match or the package name if it's long enough.
        for pat in patterns where pat.count >= 15 {
            for pid in pgrepFull(pattern: pat) where pid != myPid && !seen.contains(pid) {
                seen.insert(pid)
                killPid(pid)
            }
        }
    }

    private static func pgrepFull(pattern: String) -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", pattern]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }

    private static func killPid(_ pid: String) {
        let k = Process()
        k.executableURL = URL(fileURLWithPath: "/bin/kill")
        k.arguments = ["-TERM", pid]
        try? k.run()
        k.waitUntilExit()
    }
}

extension Notification.Name {
    public static let mcpLocalProcessExitedEarly = Notification.Name("GrizzyClaw.mcpLocalProcessExitedEarly")
}
