import Foundation
import Yams

/// Minimal read–merge–write edits for `config.yaml` (Python `Settings.to_file` parity for selected keys).
public enum UserConfigYAMLPatch {
    public enum PatchError: Error, LocalizedError {
        case configMissing(URL)
        case loadFailed(String)

        public var errorDescription: String? {
            switch self {
            case .configMissing(let u):
                return "config.yaml not found at \(u.path). Create it with the Python app or add the file manually."
            case .loadFailed(let s):
                return s
            }
        }
    }

    /// Writes `scheduled_task_run_timeout_seconds` (Python `Settings.scheduled_task_run_timeout_seconds`).
    public static func setScheduledTaskRunTimeout(seconds: Int, configURL: URL = GrizzyClawPaths.configYAML) throws {
        try GrizzyClawPaths.ensureUserDataDirectoryExists()
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw PatchError.configMissing(configURL)
        }
        let text = try String(contentsOf: configURL, encoding: .utf8)
        let parsed: Any?
        do {
            parsed = try Yams.load(yaml: text)
        } catch {
            throw PatchError.loadFailed(error.localizedDescription)
        }
        var root = (parsed as? [String: Any]) ?? [:]
        root["scheduled_task_run_timeout_seconds"] = seconds
        let out = try Yams.dump(object: root)
        try out.write(to: configURL, atomically: true, encoding: .utf8)
    }
}
