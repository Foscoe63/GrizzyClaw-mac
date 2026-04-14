import Foundation

public enum SwarmTemplateError: Error, Sendable {
    case missingTemplateKey(String)
}

/// Loads Python `WORKSPACE_TEMPLATES` config blobs from `swarm_workspace_templates.json` (generated from GrizzyClaw).
public enum SwarmWorkspaceTemplateCatalog {
    private static let root: JSONValue = {
        guard let url = Bundle.module.url(forResource: "swarm_workspace_templates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            fatalError("GrizzyClawCore: swarm_workspace_templates.json missing or invalid")
        }
        return decoded
    }()

    /// Full `config` object for a template key (built-in keys from `swarm_workspace_templates.json`).
    public static func configObject(forTemplateKey key: String) throws -> [String: JSONValue] {
        guard case .object(let templates) = root,
              let tmpl = templates[key],
              case .object(let dict) = tmpl
        else {
            throw SwarmTemplateError.missingTemplateKey(key)
        }
        return dict
    }

    /// Workspace `config` JSON for `WorkspaceRecord.makeNew` / `create_workspace`.
    public static func configJSON(forTemplateKey key: String) throws -> JSONValue {
        try JSONValue.object(configObject(forTemplateKey: key))
    }
}
