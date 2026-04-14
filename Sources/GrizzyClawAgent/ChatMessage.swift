import Foundation

public struct ChatMessage: Identifiable, Sendable, Equatable {
    public enum Role: String, Sendable {
        case system
        case user
        case assistant
        /// MCP / internal tool output injected after a TOOL_CALL (shown as “Tool”, not “You”).
        case tool
    }

    public let id: UUID
    public var role: Role
    public var content: String

    public init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}
