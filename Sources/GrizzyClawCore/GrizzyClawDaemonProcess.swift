import Foundation

/// Runs `grizzyclaw …` via `/usr/bin/env` with stdio detached so long-running `daemon run` cannot block on pipe backpressure.
public enum GrizzyClawDaemonProcess {
    /// Starts `grizzyclaw daemon run` (or other subcommands) without waiting for exit.
    public static func launchGrizzyClawDaemon(arguments: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["grizzyclaw"] + arguments
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }
}
