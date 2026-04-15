import Foundation

/// Matches Python `~/.grizzyclaw/gui_chat_prefs.json` (`ChatWidget._save_gui_prefs`).
public struct GuiChatPreferences: Codable, Equatable, Sendable {
    /// What to show in the chat transcript after MCP tool calls: model prose, raw tool output, or both.
    public enum McpTranscriptMode: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
        case assistant
        case tool
        case both
    }

    public struct LLM: Codable, Equatable, Sendable {
        public var provider: String?
        public var model: String?

        public init(provider: String? = nil, model: String? = nil) {
            self.provider = provider
            self.model = model
        }
    }

    public var llm: LLM?
    /// Each element is `[serverName, toolName]` as in Python.
    public var mcpEnabledPairs: [[String]]?
    /// When `nil`, defaults to `.assistant` (assistant bubbles only; tool turns hidden).
    public var mcpTranscriptMode: McpTranscriptMode?
    /// When `nil`, defaults to `true` so returned MCP follow-up actions keep working.
    public var mcpAutoFollowActions: Bool?
    /// Cache of MCP tool counts shown in Preferences, keyed by resolved MCP JSON path.
    public var mcpToolCountsByJSONPath: [String: [String: Int]]?

    public init(
        llm: LLM? = nil,
        mcpEnabledPairs: [[String]]? = nil,
        mcpTranscriptMode: McpTranscriptMode? = nil,
        mcpAutoFollowActions: Bool? = nil,
        mcpToolCountsByJSONPath: [String: [String: Int]]? = nil
    ) {
        self.llm = llm
        self.mcpEnabledPairs = mcpEnabledPairs
        self.mcpTranscriptMode = mcpTranscriptMode
        self.mcpAutoFollowActions = mcpAutoFollowActions
        self.mcpToolCountsByJSONPath = mcpToolCountsByJSONPath
    }

    private enum CodingKeys: String, CodingKey {
        case llm
        case mcpEnabledPairs
        case mcpTranscriptMode
        case mcpAutoFollowActions
        case mcpToolCountsByJSONPath
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        llm = try c.decodeIfPresent(LLM.self, forKey: .llm)
        mcpEnabledPairs = try c.decodeIfPresent([[String]].self, forKey: .mcpEnabledPairs)
        mcpAutoFollowActions = try c.decodeIfPresent(Bool.self, forKey: .mcpAutoFollowActions)
        mcpToolCountsByJSONPath = try c.decodeIfPresent([String: [String: Int]].self, forKey: .mcpToolCountsByJSONPath)
        if let raw = try c.decodeIfPresent(String.self, forKey: .mcpTranscriptMode) {
            mcpTranscriptMode = McpTranscriptMode(rawValue: raw)
        } else {
            mcpTranscriptMode = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(llm, forKey: .llm)
        try c.encodeIfPresent(mcpEnabledPairs, forKey: .mcpEnabledPairs)
        try c.encodeIfPresent(mcpTranscriptMode, forKey: .mcpTranscriptMode)
        try c.encodeIfPresent(mcpAutoFollowActions, forKey: .mcpAutoFollowActions)
        try c.encodeIfPresent(mcpToolCountsByJSONPath, forKey: .mcpToolCountsByJSONPath)
    }

    public static let fileName = "gui_chat_prefs.json"

    public static func load() -> GuiChatPreferences {
        let url = GrizzyClawPaths.userDataDirectory.appendingPathComponent(fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: url) else {
            return GuiChatPreferences()
        }
        do {
            let dec = JSONDecoder()
            return try dec.decode(GuiChatPreferences.self, from: data)
        } catch {
            GrizzyClawLog.error("gui_chat_prefs.json decode failed, using defaults: \(error.localizedDescription)")
            return GuiChatPreferences()
        }
    }

    public func save() throws {
        try GrizzyClawPaths.ensureUserDataDirectoryExists()
        let url = GrizzyClawPaths.userDataDirectory.appendingPathComponent(Self.fileName, isDirectory: false)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}
