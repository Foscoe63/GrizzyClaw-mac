import Foundation

public enum ClawHubSkillResolver {
    /// Global defaults from `~/.grizzyclaw/config.yaml`.
    public static func defaultSkillIDs(user: UserConfigSnapshot) -> [String] {
        deduplicatedSkillIDs(user.enabledSkills)
    }

    /// Explicit per-workspace/per-agent override from `workspaces.json`.
    public static func workspaceOverrideSkillIDs(workspace: WorkspaceRecord?) -> [String]? {
        guard let raw = workspace?.config?.stringArrayIfPresent(forKey: "enabled_skills") else { return nil }
        return deduplicatedSkillIDs(raw)
    }

    public static func usesWorkspaceOverride(workspace: WorkspaceRecord?) -> Bool {
        workspaceOverrideSkillIDs(workspace: workspace) != nil
    }

    /// Final resolved set for the selected agent/workspace, matching Osaurus-style defaults + per-agent override.
    public static func resolvedSkillIDs(user: UserConfigSnapshot, workspace: WorkspaceRecord?) -> [String] {
        if let override = workspaceOverrideSkillIDs(workspace: workspace) {
            return override
        }
        return defaultSkillIDs(user: user)
    }

    private static func deduplicatedSkillIDs(_ rawIDs: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in rawIDs {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }
}
