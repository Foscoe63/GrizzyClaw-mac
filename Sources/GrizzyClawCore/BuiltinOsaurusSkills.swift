import Foundation

/// Osaurus built-in behavioral skills (ported from OsaurusCore `Skill.builtInSkills`), installed from bundle resources.
public struct BuiltinOsaurusSkillDefinition: Identifiable, Hashable, Sendable {
    public var id: String { skillID }

    /// Value stored in `enabled_skills` / workspace override (single path segment, no slashes).
    public let skillID: String

    /// Subdirectory under `BundledSkills/Osaurus/` in GrizzyClawCore resources.
    public let bundleFolderSlug: String

    public let name: String
    public let description: String
    public let icon: String

    /// Matches Osaurus defaults (`Sandbox Plugin Creator` is on by default there).
    public let defaultEnabled: Bool

    public init(
        skillID: String,
        bundleFolderSlug: String,
        name: String,
        description: String,
        icon: String,
        defaultEnabled: Bool
    ) {
        self.skillID = skillID
        self.bundleFolderSlug = bundleFolderSlug
        self.name = name
        self.description = description
        self.icon = icon
        self.defaultEnabled = defaultEnabled
    }

    public var pickerLabel: String { "\(icon) \(name) — \(description)" }
}

public enum BuiltinOsaurusSkills {
    /// Bump when bundled `SKILL.md` content changes so ``OsaurusBundledSkillsInstaller`` can refresh user copies.
    public static let bundleRevision = 2

    public static let all: [BuiltinOsaurusSkillDefinition] = [
        .init(
            skillID: "osaurus-research-analyst",
            bundleFolderSlug: "research-analyst",
            name: "Research Analyst",
            description: "In-depth research with fact-checking and balanced analysis",
            icon: "🔬",
            defaultEnabled: false
        ),
        .init(
            skillID: "osaurus-creative-brainstormer",
            bundleFolderSlug: "creative-brainstormer",
            name: "Creative Brainstormer",
            description: "Generate ideas, overcome creative blocks, and explore possibilities",
            icon: "💡",
            defaultEnabled: false
        ),
        .init(
            skillID: "osaurus-study-tutor",
            bundleFolderSlug: "study-tutor",
            name: "Study Tutor",
            description: "Patient explanations, practice problems, and learning strategies",
            icon: "📖",
            defaultEnabled: false
        ),
        .init(
            skillID: "osaurus-productivity-coach",
            bundleFolderSlug: "productivity-coach",
            name: "Productivity Coach",
            description: "Task management, prioritization, and goal achievement",
            icon: "✅",
            defaultEnabled: false
        ),
        .init(
            skillID: "osaurus-content-summarizer",
            bundleFolderSlug: "content-summarizer",
            name: "Content Summarizer",
            description: "Extract key points and create structured summaries",
            icon: "📝",
            defaultEnabled: false
        ),
        .init(
            skillID: "osaurus-debug-assistant",
            bundleFolderSlug: "debug-assistant",
            name: "Debug Assistant",
            description: "Systematic debugging and problem-solving approach",
            icon: "🐛",
            defaultEnabled: false
        ),
        .init(
            skillID: "osaurus-data-visualizer",
            bundleFolderSlug: "data-visualizer",
            name: "Data Visualizer",
            description: "Render charts and graphs from data inline or from file attachments",
            icon: "📊",
            defaultEnabled: false
        ),
        .init(
            skillID: "osaurus-sandbox-plugin-creator",
            bundleFolderSlug: "sandbox-plugin-creator",
            name: "Sandbox Plugin Creator",
            description:
                "Create new sandbox plugins when you need an integration or capability that does not exist yet (Osaurus-oriented; sandbox execution is not bundled in GrizzyClaw-Air).",
            icon: "🔌",
            defaultEnabled: true
        ),
    ]

    public static func skill(forID id: String) -> BuiltinOsaurusSkillDefinition? {
        let key = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.first { $0.skillID.lowercased() == key }
    }

    public static let defaultEnabledSkillIDs: Set<String> = Set(
        all.filter(\.defaultEnabled).map(\.skillID)
    )

    public static func availableToAdd(enabledLowercased: Set<String>) -> [BuiltinOsaurusSkillDefinition] {
        all.filter { !enabledLowercased.contains($0.skillID.lowercased()) }
    }
}
