import Foundation
import os

/// Unified `os.Logger` surface; errors always log; verbose lines only when `setDebugEnabled(true)` (typically from `config.yaml` `debug:`).
public enum GrizzyClawLog {
    private static let logger = Logger(subsystem: "com.grizzyclaw.mac", category: "GrizzyClaw")

    /// Preferred log path: `~/.grizzyclaw/grizzyclaw_swift_debug.log`. Falls back to `~/grizzyclaw_swift_debug.log`
    /// if the `.grizzyclaw` directory cannot be created (e.g., permissions, readonly home).
    private static var debugLogURL: URL {
        let preferred = GrizzyClawPaths.userDataDirectory.appendingPathComponent("grizzyclaw_swift_debug.log")
        // Best-effort: ensure `~/.grizzyclaw` exists. If this fails we fall through to the legacy `$HOME` path below.
        do {
            try FileManager.default.createDirectory(
                at: GrizzyClawPaths.userDataDirectory,
                withIntermediateDirectories: true
            )
            return preferred
        } catch {
            return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("grizzyclaw_swift_debug.log")
        }
    }

    private nonisolated(unsafe) static var debugEnabled = false
    private nonisolated(unsafe) static var emittedDebugModeHint = false
    private nonisolated(unsafe) static var reportedWriteFailurePath: String?

    public static func setDebugEnabled(_ enabled: Bool) {
        debugEnabled = enabled
        guard enabled, !emittedDebugModeHint else { return }
        emittedDebugModeHint = true
        let path = debugLogURL.path
        logger.info(
            "GrizzyClaw debug mode on — file log: \(path, privacy: .public) — In Terminal: log stream --predicate 'subsystem == \"com.grizzyclaw.mac\"' --level debug"
        )
        emitToStderr("info", "GrizzyClaw debug mode on — writing to \(path)")
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        emitToStderr("error", message)
    }

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        guard debugEnabled else { return }
        emitToStderr("info", message)
    }

    public static func debug(_ message: String) {
        guard debugEnabled else { return }
        logger.debug("\(message, privacy: .public)")
        emitToStderr("debug", message)
    }

    private static func emitToStderr(_ level: String, _ message: String) {
        let cleaned = message
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let line = "GrizzyClaw [\(level)] \(cleaned)"
        fputs("\(line)\n", stderr)
        fflush(stderr)
        appendDebugLogLine(line)
    }

    private static func appendDebugLogLine(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let row = "\(stamp) \(line)\n"
        guard let data = row.data(using: .utf8) else { return }
        let url = debugLogURL
        let path = url.path
        do {
            if FileManager.default.fileExists(atPath: path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                let created = FileManager.default.createFile(
                    atPath: path, contents: data, attributes: [.posixPermissions: 0o644]
                )
                if !created {
                    reportWriteFailure(path: path, error: nil)
                }
            }
        } catch {
            reportWriteFailure(path: path, error: error)
        }
    }

    private static func reportWriteFailure(path: String, error: Error?) {
        // Report a given failing path exactly once per process so we don't spam on every log line.
        guard reportedWriteFailurePath != path else { return }
        reportedWriteFailurePath = path
        let desc = error.map { String(describing: $0) } ?? "createFile returned false"
        logger.error("GrizzyClawLog: failed to write debug log to \(path, privacy: .public) — \(desc, privacy: .public)")
        fputs("GrizzyClaw [error] failed to write debug log to \(path) — \(desc)\n", stderr)
        fflush(stderr)
    }
}
