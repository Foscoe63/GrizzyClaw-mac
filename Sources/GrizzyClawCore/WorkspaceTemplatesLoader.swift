import Foundation

/// One user-defined template from `~/.grizzyclaw/workspace_templates.json` (Python `WorkspaceManager.get_all_templates` user half).
public struct WorkspaceUserTemplate: Identifiable, Sendable {
    public var id: String { templateKey }
    /// Dictionary key in JSON (e.g. `designer`, `my_template`).
    public let templateKey: String
    /// Human-readable template title (`name` in JSON).
    public let displayName: String
    public let description: String
    public let icon: String
    public let color: String
    public let config: JSONValue?

    public init(
        templateKey: String,
        displayName: String,
        description: String,
        icon: String,
        color: String,
        config: JSONValue?
    ) {
        self.templateKey = templateKey
        self.displayName = displayName
        self.description = description
        self.icon = icon
        self.color = color
        self.config = config
    }
}

public enum WorkspaceTemplatesLoader {
    /// Loads user templates; returns empty if the file is missing. Skips invalid entries.
    public static func load(from url: URL) throws -> [WorkspaceUserTemplate] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var out: [WorkspaceUserTemplate] = []
        out.reserveCapacity(root.count)
        for (key, value) in root {
            guard let dict = value as? [String: Any] else { continue }
            guard let name = dict["name"] as? String, !name.isEmpty else { continue }
            let desc = dict["description"] as? String ?? ""
            let icon = dict["icon"] as? String ?? "🤖"
            let color = dict["color"] as? String ?? "#007AFF"
            let config: JSONValue?
            if let c = dict["config"] {
                let configData = try JSONSerialization.data(withJSONObject: c)
                config = try JSONDecoder().decode(JSONValue.self, from: configData)
            } else {
                config = nil
            }
            out.append(
                WorkspaceUserTemplate(
                    templateKey: key,
                    displayName: name,
                    description: desc,
                    icon: icon,
                    color: color,
                    config: config
                )
            )
        }
        return out.sorted { $0.templateKey.localizedCaseInsensitiveCompare($1.templateKey) == .orderedAscending }
    }

    /// Merges one entry into `workspace_templates.json` (Python `WorkspaceManager.add_user_template`).
    public static func saveUserTemplate(
        key rawKey: String,
        workspace: WorkspaceRecord,
        to url: URL
    ) throws {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "_")
        guard !key.isEmpty else {
            throw WorkspaceMutationError.invalidTemplateKey("Template key cannot be empty.")
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard key.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw WorkspaceMutationError.invalidTemplateKey(
                "Template key must use only letters, numbers, and underscores."
            )
        }

        try GrizzyClawPaths.ensureUserDataDirectoryExists()

        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            root = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }

        let cfgObj: Any
        if let cfg = workspace.config {
            cfgObj = try cfg.jsonSerializationValue()
        } else {
            cfgObj = [String: Any]()
        }

        root[key] = [
            "name": workspace.name,
            "description": workspace.description ?? "",
            "icon": workspace.icon ?? "🤖",
            "color": workspace.color ?? "#007AFF",
            "config": cfgObj,
        ]

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    /// Adds or replaces one template entry with an explicit `config` blob (Python `add_user_template` parity).
    public static func saveUserTemplateEntry(
        key rawKey: String,
        displayName: String,
        description: String,
        icon: String,
        color: String,
        config: JSONValue,
        to url: URL
    ) throws {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "_")
        guard !key.isEmpty else {
            throw WorkspaceMutationError.invalidTemplateKey("Template key cannot be empty.")
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard key.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw WorkspaceMutationError.invalidTemplateKey(
                "Template key must use only letters, numbers, and underscores."
            )
        }

        try GrizzyClawPaths.ensureUserDataDirectoryExists()

        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            root = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }

        let cfgObj = try config.jsonSerializationValue()

        root[key] = [
            "name": displayName,
            "description": description,
            "icon": icon,
            "color": color,
            "config": cfgObj,
        ]

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
