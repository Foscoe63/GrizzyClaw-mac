import Foundation

/// Vendored CLI-Anything `SKILL.md` packs under `BundledSkills/CLIAnything/` plus `catalog.json`.
public enum CLIAnythingBundledCatalog {
    public struct Entry: Codable, Sendable, Identifiable, Hashable {
        public var id: String { catalogID }
        public let catalogID: String
        public let folder: String
        public let title: String

        enum CodingKeys: String, CodingKey {
            case catalogID = "id"
            case folder
            case title
        }
    }

    private struct Root: Codable {
        let version: Int
        let entries: [Entry]
    }

    public static func loadEntries() -> [Entry] {
        guard
            let url = Bundle.module.url(
                forResource: "catalog",
                withExtension: "json",
                subdirectory: "BundledSkills/CLIAnything"
            ),
            let data = try? Data(contentsOf: url),
            let root = try? JSONDecoder().decode(Root.self, from: data)
        else {
            return []
        }
        return root.entries
    }

    public static func bundledSkillMarkdownURL(folder: String) -> URL? {
        Bundle.module.url(
            forResource: "SKILL",
            withExtension: "md",
            subdirectory: "BundledSkills/CLIAnything/\(folder)"
        )
    }
}
