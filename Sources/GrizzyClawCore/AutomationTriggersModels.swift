import Foundation

/// One row in `~/.grizzyclaw/triggers.json` (`grizzyclaw.automation.triggers.TriggerRule`).
public struct AutomationTriggerRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var event: String
    public var description: String
    public var condition: TriggerConditionDTO?
    public var action: TriggerActionDTO

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, event, description, condition, action
    }

    public init(
        id: String,
        name: String,
        enabled: Bool = true,
        event: String = "message",
        description: String = "",
        condition: TriggerConditionDTO? = nil,
        action: TriggerActionDTO
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.event = event
        self.description = description
        self.condition = condition
        self.action = action
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Unnamed"
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        event = try c.decodeIfPresent(String.self, forKey: .event) ?? "message"
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        condition = try c.decodeIfPresent(TriggerConditionDTO.self, forKey: .condition)
        action = try c.decode(TriggerActionDTO.self, forKey: .action)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(event, forKey: .event)
        try c.encode(description, forKey: .description)
        try c.encodeIfPresent(condition, forKey: .condition)
        try c.encode(action, forKey: .action)
    }
}

public struct TriggerConditionDTO: Codable, Equatable, Sendable {
    public var type: String
    /// Stored as JSON (string, number, etc.); Python commonly uses a string pattern.
    public var value: JSONValue

    public init(type: String, value: JSONValue) {
        self.type = type
        self.value = value
    }
}

public struct TriggerActionDTO: Codable, Equatable, Sendable {
    public var type: String
    public var config: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case type, config
    }

    public init(type: String, config: [String: JSONValue] = [:]) {
        self.type = type
        self.config = config
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "agent_message"
        config = try c.decodeIfPresent([String: JSONValue].self, forKey: .config) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(config, forKey: .config)
    }
}

public struct TriggersFilePayload: Codable, Sendable {
    public var triggers: [AutomationTriggerRecord]

    public init(triggers: [AutomationTriggerRecord]) {
        self.triggers = triggers
    }
}
