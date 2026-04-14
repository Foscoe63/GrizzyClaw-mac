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

    public init(llm: LLM? = nil, mcpEnabledPairs: [[String]]? = nil, mcpTranscriptMode: McpTranscriptMode? = nil) {
        self.llm = llm
        self.mcpEnabledPairs = mcpEnabledPairs
        self.mcpTranscriptMode = mcpTranscriptMode
    }

    private enum CodingKeys: String, CodingKey {
        case llm
        case mcpEnabledPairs
        case mcpTranscriptMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        llm = try c.decodeIfPresent(LLM.self, forKey: .llm)
        mcpEnabledPairs = try c.decodeIfPresent([[String]].self, forKey: .mcpEnabledPairs)
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
