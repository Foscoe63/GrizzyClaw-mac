import Foundation
import Yams

/// Editable in-memory view of `~/.grizzyclaw/config.yaml` for the native Preferences window (Python `SettingsDialog` parity).
public final class ConfigYamlDocument: ObservableObject {
    @Published public private(set) var root: [String: Any]
    public let configURL: URL
    @Published public var lastLoadError: String?

    public init(fileURL: URL = GrizzyClawPaths.configYAML) {
        self.configURL = fileURL
        self.root = [:]
        reload()
    }

    public func reload() {
        lastLoadError = nil
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            root = [:]
            syncDebugFlagFromRoot()
            return
        }
        do {
            let data = try Data(contentsOf: configURL)
            guard let text = String(data: data, encoding: .utf8) else {
                lastLoadError = "Could not decode config as UTF-8."
                root = [:]
                syncDebugFlagFromRoot()
                return
            }
            let parsed = try Yams.load(yaml: text)
            root = (parsed as? [String: Any]) ?? [:]
        } catch {
            lastLoadError = error.localizedDescription
            root = [:]
        }
        syncDebugFlagFromRoot()
    }

    /// Keeps `GrizzyClawLog` in sync with `root` after load/merge (Preferences `reload()` does not go through `set(_:value:)`).
    private func syncDebugFlagFromRoot() {
        GrizzyClawLog.setDebugEnabled(bool("debug", default: false))
    }

    public func save() throws {
        try GrizzyClawPaths.ensureUserDataDirectoryExists()
        let yaml = try Yams.dump(object: root)
        try yaml.write(to: configURL, atomically: true, encoding: .utf8)
        lastLoadError = nil
    }

    // MARK: - Typed access (keys match Python `Settings` / `config.yaml` snake_case)

    public func string(_ key: String, default d: String) -> String {
        UserConfigSnapshot.coerceString(root[key], default: d)
    }

    /// String for optional YAML fields (`null` or missing → empty).
    public func optionalString(_ key: String) -> String {
        guard let v = root[key], !(v is NSNull) else { return "" }
        return UserConfigSnapshot.coerceString(v, default: "")
    }

    public func int(_ key: String, default d: Int) -> Int {
        UserConfigSnapshot.coerceInt(root[key], default: d)
    }

    public func bool(_ key: String, default d: Bool) -> Bool {
        UserConfigSnapshot.coerceBool(root[key], default: d)
    }

    public func double(_ key: String, default d: Double) -> Double {
        UserConfigSnapshot.coerceDouble(root[key], default: d)
    }

    public func stringArray(_ key: String) -> [String] {
        guard let v = root[key] else { return [] }
        if let a = v as? [String] { return a }
        if let a = v as? [Any] {
            return a.compactMap { UserConfigSnapshot.coerceString($0, default: "").trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return []
    }

    public func set(_ key: String, value: Any?) {
        if let value {
            root[key] = value
        } else {
            root.removeValue(forKey: key)
        }
        objectWillChange.send()
        if key == "debug" {
            GrizzyClawLog.setDebugEnabled(bool("debug", default: false))
        }
    }

    /// Optional secret / string: empty trims → YAML `null` (matches Python `None`).
    public func setOptionalString(_ key: String, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            root[key] = NSNull()
        } else {
            root[key] = t
        }
        objectWillChange.send()
    }

    public func merge(_ patch: [String: Any]) {
        for (k, v) in patch {
            if v is NSNull {
                root.removeValue(forKey: k)
            } else {
                root[k] = v
            }
        }
        objectWillChange.send()
        syncDebugFlagFromRoot()
    }

    public func setStringArray(_ key: String, _ value: [String]) {
        root[key] = value
        objectWillChange.send()
    }

    /// Re-read a single key from `config.yaml` on disk (Python ClawHub “Refresh” without discarding other unsaved keys).
    public func reloadValue(forKey key: String, fromDisk fileURL: URL? = nil) {
        let u = fileURL ?? configURL
        guard FileManager.default.fileExists(atPath: u.path) else { return }
        do {
            let data = try Data(contentsOf: u)
            guard let text = String(data: data, encoding: .utf8) else { return }
            let parsed = try Yams.load(yaml: text) as? [String: Any]
            guard let parsed, let v = parsed[key] else { return }
            root[key] = v
            objectWillChange.send()
            if key == "debug" {
                syncDebugFlagFromRoot()
            }
        } catch {}
    }
}
