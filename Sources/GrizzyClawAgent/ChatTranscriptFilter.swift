import Foundation
import GrizzyClawCore

/// Pure transcript filtering for chat (MCP display modes, blank assistant shells).
public enum ChatTranscriptFilter: Sendable {
    private static func isToolOutputUserMessage(_ m: ChatMessage) -> Bool {
        m.role == .user && m.content.hasPrefix("[Tool output]")
    }

    private static func replyBlockHasNonBlankAssistant(afterUserIndex userIndex: Int, in all: [ChatMessage]) -> Bool {
        guard userIndex >= 0, userIndex < all.count, all[userIndex].role == .user else { return false }
        var j = userIndex + 1
        while j < all.count, all[j].role != .user {
            if all[j].role == .assistant {
                let stripped = ToolCallCommandParsing
                    .stripToolCallBlocks(all[j].content)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !stripped.isEmpty, stripped != "…" {
                    return true
                }
            }
            j += 1
        }
        return false
    }

    public static func visibleMessages(
        _ all: [ChatMessage],
        mode: GuiChatPreferences.McpTranscriptMode,
        isStreaming: Bool
    ) -> [ChatMessage] {
        let lastAssistantId = all.last(where: { $0.role == .assistant })?.id
        var out: [ChatMessage] = []
        for (i, m) in all.enumerated() where m.role != .system {
            // `[Tool output]` user messages are an internal transport detail (e.g. MLX chat templates).
            // They should never be shown in the GUI transcript; the `.tool` message is the user-visible one.
            if isToolOutputUserMessage(m) { continue }
            switch mode {
            case .assistant:
                // Assistant-only mode normally hides tool output; however, some local models never emit a
                // follow-up assistant summary after the tool runs. In that case, hiding tool output makes
                // results "flash then disappear". Keep tool output when there is no non-blank assistant
                // message in the same reply block.
                if m.role == .tool {
                    let lastUser = (0..<i).last { all[$0].role == .user } ?? -1
                    if lastUser >= 0, replyBlockHasNonBlankAssistant(afterUserIndex: lastUser, in: all) {
                        continue
                    }
                    out.append(m)
                    continue
                }
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
