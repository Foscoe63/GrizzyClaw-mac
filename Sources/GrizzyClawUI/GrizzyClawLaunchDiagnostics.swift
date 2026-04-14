import Darwin
import Foundation
import os.log

/// Lines that must appear in the Xcode debug console (and stderr) if the process gets past dyld + Swift startup.
/// If Xcode’s debug area stays empty, check `~/grizzyclaw_swift_debug.log` or
/// `log stream --predicate 'subsystem == "com.grizzyclaw.macos"' --level debug` while launching.
public enum GrizzyClawLaunchDiagnostics {
    private nonisolated(unsafe) static var didUnbufferStderr = false
    private static let unifiedLog = Logger(subsystem: "com.grizzyclaw.macos", category: "launch")
    private static let homeLogURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("grizzyclaw_swift_debug.log")

    public static func log(_ phase: String) {
        if !didUnbufferStderr {
            didUnbufferStderr = true
            setbuf(stderr, nil)
        }
        let msg = "GrizzyClaw [launch] \(phase) pid=\(getpid())"
        fputs("\(msg)\n", stderr)
        fflush(stderr)
        NSLog("%@", msg)
        unifiedLog.info("\(msg, privacy: .public)")
        appendHomeLogLine(msg)
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
