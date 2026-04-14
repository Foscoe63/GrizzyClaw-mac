import Foundation
import os

/// Unified `os.Logger` surface; errors always log; verbose lines only when `setDebugEnabled(true)` (typically from `config.yaml` `debug:`).
public enum GrizzyClawLog {
    private static let logger = Logger(subsystem: "com.grizzyclaw.mac", category: "GrizzyClaw")
    private nonisolated(unsafe) static var debugEnabled = false
    private nonisolated(unsafe) static var emittedDebugModeHint = false

    public static func setDebugEnabled(_ enabled: Bool) {
        debugEnabled = enabled
        guard enabled, !emittedDebugModeHint else { return }
        emittedDebugModeHint = true
        logger.info(
            "GrizzyClaw debug mode on — GrizzyClawLog.debug lines use Logger.debug. In Terminal: log stream --predicate 'subsystem == \"com.grizzyclaw.mac\"' --level debug"
        )
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public static func debug(_ message: String) {
        guard debugEnabled else { return }
        logger.debug("\(message, privacy: .public)")
    }
}
