import Foundation

/// Parity with Python `swarm_setup_tab.py` (`_LINT_PROMPT`, `_TEST_PROMPT`).
public enum SwarmSetupModels {
    public static let lintPrompt =
        """
        You are LintingPro. Focus on build errors, test failures, linter output, and style issues.

        Fix order: compile/build → failing tests → warnings → style. Prefer minimal safe changes.
        Respond with: Findings, Fix plan (ordered), Patch scope, Verification steps.
        """

    public static let testPrompt =
        """
        You are TestingPro. Write, review, and repair automated tests.

        Prefer deterministic tests and clear Arrange/Act/Assert. Avoid flaky async timing.
        Deliver: what to test, tests to add/update, how to run and interpret failures.
        """

    public static let softwareOrder = ["planning", "coding", "lint", "test", "research"]
    public static let personalOrder = ["personal", "research"]
    public static let hybridOrder = ["planning", "coding", "lint", "test", "personal", "research"]

    public static func checkboxLabel(kind: String) -> String {
        switch kind {
        case "planning": return "Planning Assistant (@planning_assistant)"
        case "coding": return "Code Assistant (@code_assistant)"
        case "lint": return "Linting Pro (@linting_pro)"
        case "test": return "Testing Pro (@testing_pro)"
        case "research": return "Research Assistant (@research_assistant)"
        case "personal": return "Personal Assistant (@personal_assistant)"
        default: return kind
        }
    }

    /// One agent row in the swarm wizard (Leader + roster specialists).
    public enum SwarmKind: String, CaseIterable {
        case leader
        case planning, coding, lint, test, research, personal
    }

    /// Python `_spec_meta`: display name, template JSON key, optional prompt override, description line.
    public static func specMeta(_ kind: SwarmKind) -> (
        displayName: String,
        templateKey: String,
        overridePrompt: String?,
        description: String
    ) {
        switch kind {
        case .leader:
            return ("Default", "default", nil, "General-purpose assistant")
        case .planning:
            return ("Planning Assistant", "planning", nil, "Project planning, roadmaps, and strategy")
        case .coding:
            return ("Code Assistant", "coding", nil, "Specialized for programming tasks")
        case .lint:
            return ("Linting Pro", "coding", lintPrompt, "Build, lint, and test hygiene.")
        case .test:
            return ("Testing Pro", "coding", testPrompt, "Writes and fixes automated tests.")
        case .research:
            return ("Research Assistant", "research", nil, "Information gathering and analysis")
        case .personal:
            return ("Personal Assistant", "personal", nil, "Daily tasks and reminders")
        }
    }

    public static func presetRosterKeys(presetIndex: Int) -> [String] {
        switch presetIndex {
        case 0: return softwareOrder
        case 1: return personalOrder
        default: return hybridOrder
        }
    }

    public static func managedKinds(
        presetIndex: Int,
        softwareRoster: Set<String>,
        personalRoster: Set<String>,
        hybridRoster: Set<String>
    ) -> [SwarmKind] {
        let keys = presetRosterKeys(presetIndex: presetIndex)
        let roster: Set<String> =
            presetIndex == 0 ? softwareRoster : (presetIndex == 1 ? personalRoster : hybridRoster)
        let specialists = keys.filter { roster.contains($0) }.compactMap { SwarmKind(rawValue: $0) }
        return [.leader] + specialists
    }

    public static func channelNormalized(_ channel: String) -> String {
        let t = channel.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "default" : t
    }

    public static func mentionSlug(displayName: String) -> String {
        displayName.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
    }

    /// Python `WORKSPACE_TEMPLATES[template].icon` / `.color`.
    public static func templateIconColor(templateKey: String) -> (icon: String, color: String) {
        switch templateKey {
        case "default": return ("🤖", "#007AFF")
        case "planning": return ("🗺️", "#00C7BE")
        case "coding": return ("💻", "#34C759")
        case "research": return ("🔬", "#5856D6")
        case "personal": return ("📋", "#FF2D55")
        default: return ("🤖", "#007AFF")
        }
    }

    /// Python `_effective_prompt` / template `system_prompt`.
    public static func effectiveSystemPrompt(for kind: SwarmKind) throws -> String {
        let meta = specMeta(kind)
        if let o = meta.overridePrompt { return o }
        let o = try SwarmWorkspaceTemplateCatalog.configObject(forTemplateKey: meta.templateKey)
        guard let sp = o["system_prompt"], case .string(let s) = sp else {
            return ""
        }
        return s
    }
}
