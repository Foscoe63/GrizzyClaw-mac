import Foundation

public enum WorkspaceTransferIO {
    public static func exportJSON(_ record: WorkspaceRecord) throws -> Data {
        let payload = try WorkspaceShareLink.exportJSONObject(record)
        let root: [String: Any] = [
            "version": 1,
            "workspace": payload,
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    public static func decodeWorkspacePayload(from data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WorkspaceMutationError.saveFailed("Invalid workspace import file.")
        }

        if let workspace = root["workspace"] as? [String: Any] {
            try validate(payload: workspace)
            return workspace
        }

        if let persona = root["persona"] as? [String: Any] {
            return try mapOsaurusPersona(persona)
        }

        try validate(payload: root)
        return root
    }

    private static func validate(payload: [String: Any]) throws {
        guard payload["name"] is String else {
            throw WorkspaceMutationError.saveFailed("The selected JSON file is not a workspace export.")
        }
    }

    private static func mapOsaurusPersona(_ persona: [String: Any]) throws -> [String: Any] {
        guard let name = persona["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw WorkspaceMutationError.saveFailed("The selected Osaurus agent JSON is missing a usable name.")
        }

        var config: [String: Any] = [:]
        if let systemPrompt = persona["systemPrompt"] as? String {
            config["system_prompt"] = systemPrompt
        }
        if let defaultModel = persona["defaultModel"] as? String, !defaultModel.isEmpty {
            config["llm_model"] = defaultModel
        }
        if let temperature = persona["temperature"] as? Double {
            config["temperature"] = temperature
        } else if let temperature = persona["temperature"] as? NSNumber {
            config["temperature"] = temperature.doubleValue
        }
        if let maxTokens = persona["maxTokens"] as? Int {
            config["max_tokens"] = maxTokens
        } else if let maxTokens = persona["maxTokens"] as? NSNumber {
            config["max_tokens"] = maxTokens.intValue
        }
        if let riskMode = persona["riskMode"] as? String, !riskMode.isEmpty {
            config["autonomy_level"] = riskMode
        }

        return [
            "name": name,
            "description": (persona["description"] as? String) ?? "",
            "icon": "🤖",
            "color": "#007AFF",
            "config": config,
        ]
    }
}
