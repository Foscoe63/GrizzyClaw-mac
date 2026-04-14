import Foundation

public enum AutomationTriggersPersistenceError: LocalizedError {
    case decodeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .decodeFailed(let s): return s
        }
    }
}

/// Load/save `triggers.json` (Python `load_triggers` / `save_triggers`).
public enum AutomationTriggersPersistence {
    public static func load() throws -> [AutomationTriggerRecord] {
        let url = GrizzyClawPaths.triggersJSON
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [] }
        do {
            let decoded = try JSONDecoder().decode(TriggersFilePayload.self, from: data)
            return decoded.triggers
        } catch {
            throw AutomationTriggersPersistenceError.decodeFailed(error.localizedDescription)
        }
    }

    public static func save(_ rules: [AutomationTriggerRecord]) throws {
        try GrizzyClawPaths.ensureUserDataDirectoryExists()
        let payload = TriggersFilePayload(triggers: rules)
        let data = try JSONEncoder.prettyPrinted.encode(payload)
        try data.write(to: GrizzyClawPaths.triggersJSON, options: [.atomic])
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
