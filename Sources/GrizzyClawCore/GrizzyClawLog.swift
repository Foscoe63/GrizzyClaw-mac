import Foundation
import os

/// Unified `os.Logger` surface; errors always log; verbose lines only when `setDebugEnabled(true)` (typically from `config.yaml` `debug:`).
public enum GrizzyClawLog {
    private static let logger = Logger(subsystem: "com.grizzyclaw.mac", category: "GrizzyClaw")
    private static let homeLogURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("grizzyclaw_swift_debug.log")
    private nonisolated(unsafe) static var debugEnabled = false
    private nonisolated(unsafe) static var emittedDebugModeHint = false

    public static func setDebugEnabled(_ enabled: Bool) {
        debugEnabled = enabled
        guard enabled, !emittedDebugModeHint else { return }
        emittedDebugModeHint = true
        logger.info(
            "GrizzyClaw debug mode on — GrizzyClawLog.debug lines use Logger.debug. In Terminal: log stream --predicate 'subsystem == \"com.grizzyclaw.mac\"' --level debug"
        )
        emitToStderr("info", "GrizzyClaw debug mode on")
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
        appendHomeLogLine(line)
    }

    private static func appendHomeLogLine(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let row = "\(stamp) \(line)\n"
        guard let data = row.data(using: .utf8) else { return }
        let path = homeLogURL.path
        if FileManager.default.fileExists(atPath: path) {
            guard let handle = try? FileHandle(forWritingTo: homeLogURL) else { return }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            FileManager.default.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o644])
        }
    }
}
