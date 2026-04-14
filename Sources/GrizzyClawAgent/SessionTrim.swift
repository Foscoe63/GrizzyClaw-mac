import Foundation

/// Mirrors `grizzyclaw/agent/context_utils.py` (`trim_session` + priority markers).
public enum SessionTrim {
    static let priorityMarkers: [String] = [
        "[Tool result",
        "TOOL_CALL",
        "BROWSER_ACTION",
        "SCHEDULE_TASK",
        "MEMORY_SAVE",
        "EXEC_COMMAND",
        "\u{2692}", // 🔧
    ]

    public static func messageHasPriorityContent(_ message: ChatMessage) -> Bool {
        priorityMarkers.contains { message.content.contains($0) }
    }

    /// Drop oldest turns first while preserving recent tail and older high-value tool-heavy turns.
    public static func trim(_ session: [ChatMessage], maxMessages: Int) -> [ChatMessage] {
        guard session.count > maxMessages else { return session }

        let recentCount = max(maxMessages - 4, maxMessages / 2)
        let recent = Array(session.suffix(recentCount))
        let older = Array(session.dropLast(recentCount))

        let prioritySlots = maxMessages - recent.count
        if prioritySlots <= 0 {
            return recent
        }

        let priorityInOlder = older.filter { messageHasPriorityContent($0) }
        let keptPriority = Array(priorityInOlder.suffix(prioritySlots))

        return keptPriority + recent
    }
}
