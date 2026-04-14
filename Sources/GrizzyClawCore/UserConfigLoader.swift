import Foundation
import Yams

public enum UserConfigLoader {
    public enum LoadError: Swift.Error, LocalizedError {
        case notUTF8(URL)
        case invalidYAML(String)

        public var errorDescription: String? {
            switch self {
            case .notUTF8(let url):
                return "Could not read config as UTF-8: \(url.path)"
            case .invalidYAML(let message):
                return message
            }
        }
    }

    /// Loads `~/.grizzyclaw/config.yaml` when present; otherwise returns defaults with `fileMissing == true`.
    public static func loadUserConfigIfPresent(at url: URL = GrizzyClawPaths.configYAML) throws -> UserConfigSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return UserConfigSnapshot.missingFile(at: url)
        }
        guard let yamlText = String(data: try Data(contentsOf: url), encoding: .utf8) else {
            throw LoadError.notUTF8(url)
        }
        let parsed: Any?
        do {
            parsed = try Yams.load(yaml: yamlText)
        } catch {
            throw LoadError.invalidYAML(error.localizedDescription)
        }
        let dict = (parsed as? [String: Any]) ?? [:]
        return UserConfigSnapshot(parsing: dict, configPath: url)
    }
}
