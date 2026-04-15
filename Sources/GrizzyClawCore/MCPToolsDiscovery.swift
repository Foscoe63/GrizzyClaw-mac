import Foundation

public struct MCPToolDescriptor: Sendable, Equatable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue?

    public init(name: String, description: String, inputSchema: JSONValue? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct MCPToolsDiscoveryResult: Sendable {
    /// Server name → discovered MCP tools (name, description, optional input schema).
    public var servers: [String: [MCPToolDescriptor]]
    public var errorMessage: String?

    public init(servers: [String: [MCPToolDescriptor]], errorMessage: String?) {
        self.servers = servers
        self.errorMessage = errorMessage
    }
}

public enum MCPToolsDiscoveryError: Error, LocalizedError {
    case pythonNotFound
    case scriptResourceMissing
    case emptyOutput
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Could not find python3 on this Mac (install Python 3 and pip install mcp httpx)."
        case .scriptResourceMissing:
            return "mcp_discover.py could not be found. Reinstall the app, or set GRIZZYCLAW_MCP_DISCOVER to the script path, or ensure ~/.grizzyclaw/support/mcp_discover.py exists (copied after a successful run)."
        case .emptyOutput:
            return "MCP discovery produced no output."
        case .invalidJSON(let s):
            return "MCP discovery returned invalid JSON: \(s)"
        }
    }
}

/// Runs the bundled `mcp_discover.py` helper (same protocol stack as the Python GrizzyClaw app).
public enum MCPToolsDiscovery {
    /// Optional override: absolute path to `mcp_discover.py` (for debugging or custom installs).
    public static let environmentScriptKey = "GRIZZYCLAW_MCP_DISCOVER"

    /// Stable copy updated whenever a bundled script is found (`~/.grizzyclaw/support/mcp_discover.py`).
    public static var cachedScriptURL: URL {
        GrizzyClawPaths.userDataDirectory.appendingPathComponent("support/mcp_discover.py", isDirectory: false)
    }

    /// Set `GRIZZYCLAW_MCP_USE_PYTHON=1` to force the legacy Python `mcp_discover.py` path (e.g. debugging).
    public static let forcePythonDiscoveryKey = "GRIZZYCLAW_MCP_USE_PYTHON"

    private struct CacheKey: Hashable {
        let path: String
        let modificationTime: TimeInterval?
        let onlyServerNames: [String]?
    }

    private actor DiscoveryCache {
        static let shared = DiscoveryCache()
        private var store: [CacheKey: MCPToolsDiscoveryResult] = [:]

        func get(_ key: CacheKey) -> MCPToolsDiscoveryResult? {
            store[key]
        }

        func put(_ value: MCPToolsDiscoveryResult, for key: CacheKey) {
            store[key] = value
        }

        func removeAll(path: String) {
            store = store.filter { $0.key.path != path }
        }
    }

    /// - Parameter onlyServerNames: If non-empty, native discovery only connects to these rows (e.g. **Test** for one server). Avoids hanging on unrelated broken servers.
    public static func discover(
        mcpServersFile: String,
        onlyServerNames: Set<String>? = nil,
        forceRefresh: Bool = false
    ) async throws -> MCPToolsDiscoveryResult {
        let expanded = (mcpServersFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "~/.grizzyclaw/grizzyclaw.json" : mcpServersFile) as NSString
        let path = expanded.expandingTildeInPath
        let cacheKey = CacheKey(
            path: path,
            modificationTime: ((try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? nil)?.timeIntervalSince1970,
            onlyServerNames: onlyServerNames?.sorted()
        )

        if forceRefresh {
            await DiscoveryCache.shared.removeAll(path: path)
        } else if let cached = await DiscoveryCache.shared.get(cacheKey) {
            return cached
        }

        let forcePython = ProcessInfo.processInfo.environment[Self.forcePythonDiscoveryKey] == "1"
        if !forcePython {
            do {
                let url = URL(fileURLWithPath: path)
                let rows = try MCPServersFileIO.load(url: url)
                let rowsToProbe = probeRows(rows: rows, onlyServerNames: onlyServerNames)
                if rowsToProbe.isEmpty {
                    if let filter = onlyServerNames, !filter.isEmpty {
                        return MCPToolsDiscoveryResult(servers: [:], errorMessage: "No MCP server in the JSON file matches the requested name(s).")
                    }
                    await DiscoveryCache.shared.put(MCPToolsDiscoveryResult(servers: [:], errorMessage: nil), for: cacheKey)
                    return MCPToolsDiscoveryResult(servers: [:], errorMessage: nil)
                }
                let native = try await GrizzyMCPNativeRuntime.shared.discoverTools(servers: rowsToProbe)
                let merged = native.mergingPythonInternalTools()
                await DiscoveryCache.shared.put(merged, for: cacheKey)
                return merged
            } catch {
                GrizzyClawLog.error("MCP native discovery failed, falling back to Python: \(error.localizedDescription)")
            }
        }

        guard let scriptURL = resolveMcpDiscoverScriptURL() else {
            throw MCPToolsDiscoveryError.scriptResourceMissing
        }

        let python = Self.resolvePython3Executable()
        guard FileManager.default.isExecutableFile(atPath: python) else {
            throw MCPToolsDiscoveryError.pythonNotFound
        }

        let result = try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: python)
            proc.arguments = [scriptURL.path, path]

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            try proc.run()
            // `waitUntilExit()` does not honor Swift task cancellation; terminate if the script hangs.
            let killTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(43 * 1_000_000_000))
                if proc.isRunning {
                    proc.terminate()
                }
            }
            proc.waitUntilExit()
            killTask.cancel()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !outData.isEmpty else {
                if !errText.isEmpty {
                    throw MCPToolsDiscoveryError.invalidJSON(errText)
                }
                throw MCPToolsDiscoveryError.emptyOutput
            }

            let obj = try JSONSerialization.jsonObject(with: outData) as? [String: Any]
            guard let obj else {
                throw MCPToolsDiscoveryError.invalidJSON("not an object")
            }

            let err: String?
            if let e = obj["error"] as? String, !e.isEmpty {
                err = e
            } else if obj["error"] is NSNull {
                err = nil
            } else {
                err = obj["error"] as? String
            }

            var servers: [String: [MCPToolDescriptor]] = [:]
            if let srv = obj["servers"] as? [String: Any] {
                for (name, val) in srv {
                    guard let rows = val as? [[Any]] else { continue }
                    var pairs: [MCPToolDescriptor] = []
                    for row in rows {
                        guard row.count >= 1 else { continue }
                        let tool = String(describing: row[0])
                        let desc = row.count >= 2 ? String(describing: row[1]) : ""
                        if !tool.isEmpty {
                            pairs.append(MCPToolDescriptor(name: tool, description: desc))
                        }
                    }
                    if !pairs.isEmpty {
                        servers[name] = pairs
                    }
                }
            }

            return MCPToolsDiscoveryResult(servers: servers, errorMessage: err)
        }.value
        await DiscoveryCache.shared.put(result, for: cacheKey)
        return result
    }

    static func probeRows(rows: [MCPServerRow], onlyServerNames: Set<String>? = nil) -> [MCPServerRow] {
        let enabledRows = rows.filter(\.enabled)
        guard let filter = onlyServerNames, !filter.isEmpty else {
            return enabledRows
        }
        return enabledRows
            .filter { filter.contains($0.name) }
            .map { MCPServerRow(name: $0.name, enabled: true, dictionary: $0.dictionary) }
    }

    /// Validates a local stdio server by writing a temporary `grizzyclaw.json` and running `mcp_discover.py` (same path as **Test** in the list; approximates Python `validate_server_config` + `ValidateConfigWorker`).
    public static func validateStdioConfiguration(command: String, args: [String], env: [String: String]) async -> (ok: Bool, message: String) {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else {
            return (false, "No command set")
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("grizzyclaw_mcp_validate_\(UUID().uuidString).json", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: temp) }
        let cfg: [String: Any] = [
            "command": cmd,
            "args": args,
            "env": env,
        ]
        let payload: [String: Any] = [
            "mcpServers": [
                "_validate": cfg,
            ],
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try data.write(to: temp, options: .atomic)
        } catch {
            return (false, error.localizedDescription)
        }
        do {
            let r = try await discover(mcpServersFile: temp.path)
            if let err = r.errorMessage, !err.isEmpty {
                return (false, err)
            }
            let n = r.servers["_validate"]?.count ?? 0
            if n == 0 {
                return (false, "No tools returned")
            }
            return (true, "OK — \(n) tools")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Resolves `mcp_discover.py` for **any** MCP server entry in JSON — discovery is one shared script, not per-server.
    private static func resolveMcpDiscoverScriptURL() -> URL? {
        let fm = FileManager.default

        if let raw = ProcessInfo.processInfo.environment[Self.environmentScriptKey], !raw.isEmpty {
            let u = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
            if fm.isReadableFile(atPath: u.path) { return u }
        }

        if let bundled = locateBundledMcpDiscoverScript() {
            try? fm.createDirectory(at: cachedScriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: cachedScriptURL)
            try? fm.copyItem(at: bundled, to: cachedScriptURL)
            return bundled
        }

        if fm.isReadableFile(atPath: cachedScriptURL.path) {
            return cachedScriptURL
        }

        return nil
    }

    /// `Bundle.module` alone fails for some `.app` / Xcode + SPM layouts; search main bundle, framework bundles, and SPM `.build` bundles.
    private static func locateBundledMcpDiscoverScript() -> URL? {
        let fm = FileManager.default
        let filename = "mcp_discover.py"

        let bundles: [Bundle] = [
            Bundle.module,
            Bundle.main,
            Bundle(for: MCPToolsDiscoveryBundleAnchor.self),
        ]

        for b in bundles {
            if let u = b.url(forResource: "mcp_discover", withExtension: "py"), fm.isReadableFile(atPath: u.path) {
                return u
            }
            if let r = b.resourceURL {
                let direct = r.appendingPathComponent(filename)
                if fm.isReadableFile(atPath: direct.path) { return direct }
                let alt = r.appendingPathComponent("Resources/\(filename)")
                if fm.isReadableFile(atPath: alt.path) { return alt }
            }
        }

        if let res = Bundle.main.resourceURL,
           let found = findNamedFile(filename, under: res, maxEntries: 1200) {
            return found
        }

        let fw = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        if fm.fileExists(atPath: fw.path),
           let found = findNamedFile(filename, under: fw, maxEntries: 2500) {
            return found
        }

        if let exe = Bundle.main.executableURL {
            var dir = exe.deletingLastPathComponent()
            for _ in 0..<10 {
                for leaf in ["GrizzyClawCore_GrizzyClawCore.bundle", "GrizzyClawCore.bundle"] {
                    let bURL = dir.appendingPathComponent(leaf)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: bURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
                    let cand = bURL.appendingPathComponent("Contents/Resources/\(filename)")
                    if fm.isReadableFile(atPath: cand.path) { return cand }
                    if let bu = Bundle(url: bURL), let u = bu.url(forResource: "mcp_discover", withExtension: "py"), fm.isReadableFile(atPath: u.path) {
                        return u
                    }
                }
                if dir.path == "/" { break }
                dir = dir.deletingLastPathComponent()
            }
        }

        return nil
    }

    private static func findNamedFile(_ name: String, under root: URL, maxEntries: Int) -> URL? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        var n = 0
        for case let u as URL in en {
            n += 1
            if n > maxEntries { return nil }
            if u.lastPathComponent == name, fm.isReadableFile(atPath: u.path) { return u }
        }
        return nil
    }

    private static func resolvePython3Executable() -> String {
        let pipxCandidates = [
            "~/.local/pipx/venvs/mcp/bin/python",
            "~/.local/pipx/venvs/mcp/bin/python3",
        ].map { ($0 as NSString).expandingTildeInPath }
        for p in pipxCandidates where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        let candidates = [
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return "/usr/bin/python3"
    }
}

/// Objective-C class anchor so `Bundle(for:)` resolves the GrizzyClawCore module bundle when embedded as a framework.
private final class MCPToolsDiscoveryBundleAnchor: NSObject {}

// MARK: - Python `ChatWidget._populate_tools_picker` parity (`_INTERNAL_GRIZZY_TOOLS`, workspace allowlist)

extension MCPToolsDiscoveryResult {
    public struct InternalTool: Sendable {
        public let server: String
        public let name: String
        public let description: String

        public init(server: String, name: String, description: String) {
            self.server = server
            self.name = name
            self.description = description
        }
    }

    /// Python `main_window._INTERNAL_GRIZZY_TOOLS` — prepended before discovered MCP tools, deduped.
    public static let pythonInternalTools: [InternalTool] = [
        .init(
            server: "grizzyclaw",
            name: "get_status",
            description: "Show native chat status, workspace id, and MCP servers file."
        ),
        .init(
            server: "grizzyclaw",
            name: "create_scheduled_task",
            description: "Create a scheduled task in the scheduler using a cron expression and task message."
        ),
        .init(
            server: "grizzyclaw",
            name: "list_scheduled_tasks",
            description: "List scheduled tasks currently saved in the scheduler."
        ),
        .init(
            server: "grizzyclaw",
            name: "run_scheduled_task",
            description: "Run a scheduled task immediately by task id."
        ),
        .init(
            server: "grizzyclaw",
            name: "search_transcripts",
            description: "Search saved transcripts and session history."
        ),
    ]

    /// Flat merge: internal pairs first, then discovered (stable), deduped by (server, tool).
    public func mergingPythonInternalTools() -> MCPToolsDiscoveryResult {
        var seen = Set<String>()
        var flat: [(String, MCPToolDescriptor)] = []
        func pairKey(_ s: String, _ n: String) -> String { s + "\u{1E}" + n }
        for t in Self.pythonInternalTools {
            let k = pairKey(t.server, t.name)
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            flat.append((t.server, MCPToolDescriptor(name: t.name, description: t.description)))
        }
        for srv in servers.keys.sorted() {
            guard let tools = servers[srv] else { continue }
            for t in tools {
                let k = pairKey(srv, t.name)
                guard !seen.contains(k) else { continue }
                seen.insert(k)
                flat.append((srv, t))
            }
        }
        var by: [String: [MCPToolDescriptor]] = [:]
        for (srv, tool) in flat {
            by[srv, default: []].append(tool)
        }
        return MCPToolsDiscoveryResult(servers: by, errorMessage: errorMessage)
    }

    /// Hide tools outside the workspace `mcp_tool_allowlist` when that list is non-empty (Python `ws_allow`).
    /// Resolves each allow entry against discovered server/tool names (same rules as chat tool identity) so
    /// saved rows like `user-ddg-search` / case drift still match `ddg-search` from discovery.
    public func filteredByWorkspaceAllowlist(_ allow: [(String, String)]) -> MCPToolsDiscoveryResult {
        guard !allow.isEmpty else { return self }
        let knownServers = Array(servers.keys)
        var ok = Set<String>()
        for (a, b) in allow {
            ok.insert(a + "\u{1E}" + b)
        }
        for (asrv, atool) in allow {
            let canonSrv = MCPIdentityResolution.canonicalServerName(modelOutput: asrv, knownServers: knownServers)
            guard let toolList = servers[canonSrv] else { continue }
            let names = toolList.map(\.name)
            let canonTool = MCPIdentityResolution.canonicalToolName(modelOutput: atool, knownTools: names)
            ok.insert(canonSrv + "\u{1E}" + canonTool)
        }
        var by: [String: [MCPToolDescriptor]] = [:]
        for (srv, tools) in servers {
            let ft = tools.filter { ok.contains(srv + "\u{1E}" + $0.name) }
            if !ft.isEmpty { by[srv] = ft }
        }
        if by.isEmpty, !servers.isEmpty {
            GrizzyClawLog.info(
                "Workspace mcp_tool_allowlist matched no discovered tools (stale names or tool renames). Using full discovery for the chat tool list."
            )
            return self
        }
        return MCPToolsDiscoveryResult(servers: by, errorMessage: errorMessage)
    }
}
