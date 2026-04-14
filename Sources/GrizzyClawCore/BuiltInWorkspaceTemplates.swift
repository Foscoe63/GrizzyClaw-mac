import Foundation

/// Static display metadata for Python `WORKSPACE_TEMPLATES` keys (order matches `grizzyclaw/workspaces/workspace.py`).
public enum BuiltInWorkspaceTemplates {
    public struct Metadata: Sendable {
        public let key: String
        public let name: String
        public let description: String
        public let icon: String
        public let color: String

        public init(key: String, name: String, description: String, icon: String, color: String) {
            self.key = key
            self.name = name
            self.description = description
            self.icon = icon
            self.color = color
        }
    }

    /// Same key order as Python `WORKSPACE_TEMPLATES` iteration (default → … → designer).
    public static let orderedMetadata: [Metadata] = [
        Metadata(
            key: "default",
            name: "Default",
            description: "General-purpose assistant",
            icon: "🤖",
            color: "#007AFF"
        ),
        Metadata(
            key: "coding",
            name: "Code Assistant",
            description: "Specialized for programming tasks",
            icon: "💻",
            color: "#34C759"
        ),
        Metadata(
            key: "writing",
            name: "Writing Assistant",
            description: "Creative writing and content creation",
            icon: "✍️",
            color: "#FF9500"
        ),
        Metadata(
            key: "research",
            name: "Research Assistant",
            description: "Information gathering and analysis",
            icon: "🔬",
            color: "#5856D6"
        ),
        Metadata(
            key: "personal",
            name: "Personal Assistant",
            description: "Daily tasks and reminders",
            icon: "📋",
            color: "#FF2D55"
        ),
        Metadata(
            key: "planning",
            name: "Planning Assistant",
            description: "Project planning, roadmaps, and strategy",
            icon: "🗺️",
            color: "#00C7BE"
        ),
        Metadata(
            key: "designer",
            name: "Designer",
            description: "Design, UI/UX, and visual creativity",
            icon: "🎨",
            color: "#AF52DE"
        ),
    ]

    public static var orderedKeys: [String] {
        orderedMetadata.map(\.key)
    }
}
