import Foundation

/// One curated marketplace row (Python `DEFAULT_SKILL_MARKETPLACE` / `skill_marketplace.json`).
public struct SkillMarketplaceEntry: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let enabledSkillsAdd: [String]

    public init(id: String, name: String, description: String, enabledSkillsAdd: [String]) {
        self.id = id
        self.name = name
        self.description = description
        self.enabledSkillsAdd = enabledSkillsAdd
    }
}

private struct RawMarketplaceFile: Decodable {
    let id: String?
    let name: String?
    let description: String?
    let enabled_skills_add: [String]?
}

/// Loads the same sources as Python `load_skill_marketplace` / `WorkspaceManager.get_skill_marketplace`.
public enum SkillMarketplaceLoader {
    private static let builtIn: [SkillMarketplaceEntry] = [
        .init(id: "code-review", name: "Code review", description: "Review and improve code quality.", enabledSkillsAdd: ["code_review"]),
        .init(id: "create-rule", name: "Create Cursor rule", description: "Create or update .cursor rules and AGENTS.md.", enabledSkillsAdd: ["create-rule"]),
        .init(id: "create-skill", name: "Create Agent Skill", description: "Author Cursor Agent Skills (SKILL.md).", enabledSkillsAdd: ["create-skill"]),
        .init(id: "update-cursor-settings", name: "Update Cursor settings", description: "Modify editor/settings.json.", enabledSkillsAdd: ["update-cursor-settings"]),
    ]

    public static func load(skillMarketplacePathFromConfig: String) throws -> [SkillMarketplaceEntry] {
        let trimmed = skillMarketplacePathFromConfig.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let p = (trimmed as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: p) {
                return try decodeAndDedupe(URL(fileURLWithPath: p))
            }
        }
        let u = GrizzyClawPaths.skillMarketplaceJSON
        if FileManager.default.fileExists(atPath: u.path) {
            return try decodeAndDedupe(u)
        }
        return dedupe(builtIn)
    }

    private static func decodeAndDedupe(_ url: URL) throws -> [SkillMarketplaceEntry] {
        let data = try Data(contentsOf: url)
        let raw = try JSONDecoder().decode([RawMarketplaceFile].self, from: data)
        var entries: [SkillMarketplaceEntry] = []
        for r in raw {
            let id = (r.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (r.name ?? r.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let add = r.enabled_skills_add ?? []
            if id.isEmpty { continue }
            entries.append(
                SkillMarketplaceEntry(
                    id: id,
                    name: name.isEmpty ? id : name,
                    description: (r.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    enabledSkillsAdd: add
                )
            )
        }
        return dedupe(entries)
    }

    private static func dedupe(_ items: [SkillMarketplaceEntry]) -> [SkillMarketplaceEntry] {
        var seenIds = Set<String>()
        var seenNames = Set<String>()
        var out: [SkillMarketplaceEntry] = []
        for e in items {
            let eid = e.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let nk = SkillNameNormalizer.normalize(e.name)
            if !eid.isEmpty, seenIds.contains(eid) { continue }
            if !nk.isEmpty, seenNames.contains(nk) { continue }
            if !eid.isEmpty { seenIds.insert(eid) }
            if !nk.isEmpty { seenNames.insert(nk) }
            out.append(e)
        }
        return out
    }
}
