import Foundation
import GrizzyClawCore

/// Pure transcript filtering for chat (MCP display modes, blank assistant shells).
public enum ChatTranscriptFilter: Sendable {
    public static func visibleMessages(
        _ all: [ChatMessage],
        mode: GuiChatPreferences.McpTranscriptMode,
        isStreaming: Bool
    ) -> [ChatMessage] {
        let lastAssistantId = all.last(where: { $0.role == .assistant })?.id
        var out: [ChatMessage] = []
        for (i, m) in all.enumerated() where m.role != .system {
            switch mode {
            case .assistant:
                guard m.role != .tool else { continue }
                if shouldHideBlankAssistant(m, in: all, isStreaming: isStreaming, lastAssistantId: lastAssistantId) {
                    continue
                }
                out.append(m)
            case .tool:
                if m.role == .user || m.role == .tool {
                    out.append(m)
                    continue
                }
                guard m.role == .assistant else { continue }
                if shouldHideBlankAssistant(m, in: all, isStreaming: isStreaming, lastAssistantId: lastAssistantId) {
                    continue
                }
                if replyBlockHasTool(forAssistantIndex: i, in: all) {
                    continue
                }
                out.append(m)
            case .both:
                if shouldHideBlankAssistant(m, in: all, isStreaming: isStreaming, lastAssistantId: lastAssistantId) {
                    continue
                }
                out.append(m)
            }
        }
        return out
    }

    /// Exposed for tests — `true` if the reply block after the last user (until the next user) contains a `.tool` message.
    public static func replyBlockHasTool(forAssistantIndex assistantIndex: Int, in all: [ChatMessage]) -> Bool {
        guard assistantIndex < all.count, all[assistantIndex].role == .assistant else { return false }
        let lastUser = (0..<assistantIndex).last { all[$0].role == .user } ?? -1
        var j = lastUser + 1
        while j < all.count, all[j].role != .user {
            if all[j].role == .tool { return true }
            j += 1
        }
        return false
    }

    private static func shouldHideBlankAssistant(
        _ m: ChatMessage,
        in all: [ChatMessage],
        isStreaming: Bool,
        lastAssistantId: UUID?
    ) -> Bool {
        guard m.role == .assistant else { return false }
        if isStreaming, m.id == lastAssistantId {
            return false
        }
        let t = m.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "…"
    }
}
