import Foundation

/// Built-in skill ids and display metadata — mirrors `grizzyclaw/skills/registry.py` `SKILL_REGISTRY`.
public struct BuiltinClawHubSkill: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let icon: String

    public init(id: String, name: String, description: String, icon: String) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
    }

    public var pickerLabel: String { "\(icon) \(name) — \(description)" }
}

public enum BuiltinClawHubSkills {
    public static let all: [BuiltinClawHubSkill] = [
        .init(id: "web_search", name: "Web Search", description: "Search the web for real-time information via DuckDuckGo", icon: "🔍"),
        .init(id: "filesystem", name: "File System", description: "Read, write, and manage files on your system", icon: "📁"),
        .init(id: "documentation", name: "Documentation", description: "Query library documentation via Context7", icon: "📚"),
        .init(id: "browser", name: "Browser Automation", description: "Navigate, screenshot, and interact with web pages", icon: "🌐"),
        .init(id: "memory", name: "Memory", description: "Remember and recall information across conversations", icon: "🧠"),
        .init(id: "scheduler", name: "Scheduler", description: "Schedule tasks and reminders", icon: "⏰"),
        .init(id: "calendar", name: "Google Calendar", description: "List, create, update calendar events", icon: "📅"),
        .init(id: "gmail", name: "Gmail", description: "Send emails, reply to threads", icon: "📧"),
        .init(id: "github", name: "GitHub", description: "Manage PRs, issues, repos", icon: "💻"),
        .init(id: "mcp_marketplace", name: "MCP Marketplace", description: "Discover and install ClawHub MCP servers", icon: "🛒"),
    ]

    public static func availableToAdd(enabledLowercased: Set<String>) -> [BuiltinClawHubSkill] {
        all.filter { !enabledLowercased.contains($0.id.lowercased()) }
    }

    public static func skill(forID id: String) -> BuiltinClawHubSkill? {
        all.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }
}
