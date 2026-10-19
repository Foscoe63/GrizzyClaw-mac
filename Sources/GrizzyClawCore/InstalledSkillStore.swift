import Foundation

public struct InstalledSkillSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let description: String
    public let skillMarkdownURL: URL
}

public enum InstalledSkillStore {
    public static func importSkill(from sourceURL: URL, preferredID: String? = nil) throws -> String {
        let resolved = try resolveImportSource(from: sourceURL)
        let markdown = try String(contentsOf: resolved.skillMarkdownURL, encoding: .utf8)
        let skillID = suggestedSkillID(markdown: markdown, fallback: preferredID ?? resolved.fallbackName)
        let destination = try installDirectory(for: skillID)

        if let copyRoot = resolved.copyRootDirectory {
            try replaceDirectory(at: destination, withContentsOf: copyRoot)
        } else {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try markdown.write(
                to: destination.appendingPathComponent("SKILL.md", isDirectory: false),
                atomically: true,
                encoding: .utf8
            )
        }
        return skillID
    }

    public static func installMarkdown(_ markdown: String, preferredID: String? = nil) throws -> String {
        let skillID = suggestedSkillID(markdown: markdown, fallback: preferredID)
        let destination = try installDirectory(for: skillID)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try markdown.write(
            to: destination.appendingPathComponent("SKILL.md", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        return skillID
    }

    public static func suggestedSkillID(markdown: String, fallback: String?) -> String {
        let candidates = [
            frontMatterValue(key: "name", markdown: markdown),
            headingTitle(markdown: markdown),
            fallback,
        ]
        for candidate in candidates {
            let normalized = normalizeSkillID(candidate)
            if !normalized.isEmpty { return normalized }
        }
        return "custom_skill"
    }

    public static func listInstalledSkills() throws -> [InstalledSkillSummary] {
        let root = try GrizzyClawPaths.ensureSkillsDirectoryExists()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var out: [InstalledSkillSummary] = []
        for entry in entries.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: entry.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            guard let markdownURL = try? firstSkillMarkdown(in: entry),
                  let markdown = try? String(contentsOf: markdownURL, encoding: .utf8)
            else {
                continue
            }
            let title = frontMatterValue(key: "name", markdown: markdown)
                ?? headingTitle(markdown: markdown)
                ?? entry.lastPathComponent
            let description = frontMatterValue(key: "description", markdown: markdown) ?? "Imported custom skill"
            out.append(
                InstalledSkillSummary(
                    id: entry.lastPathComponent,
                    title: title,
                    description: description,
                    skillMarkdownURL: markdownURL
                )
            )
        }
        return out
    }

    private static func installDirectory(for skillID: String) throws -> URL {
        let base = try GrizzyClawPaths.ensureSkillsDirectoryExists()
        return base.appendingPathComponent(skillID, isDirectory: true)
    }

    private static func resolveImportSource(from url: URL) throws -> ResolvedImportSource {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw NSError(
                domain: "InstalledSkillStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Skill source does not exist: \(url.path)"]
            )
        }

        if isDirectory.boolValue {
            let markdownURL = try firstSkillMarkdown(in: url)
            return ResolvedImportSource(
                skillMarkdownURL: markdownURL,
                copyRootDirectory: markdownURL.deletingLastPathComponent(),
                fallbackName: markdownURL.deletingLastPathComponent().lastPathComponent
            )
        }

        let ext = url.pathExtension.lowercased()
        guard ext == "md" || ext == "markdown" || url.lastPathComponent.uppercased() == "SKILL.MD" else {
            throw NSError(
                domain: "InstalledSkillStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Choose a `SKILL.md` file or a folder that contains one."]
            )
        }

        let copyRoot: URL? = url.lastPathComponent.caseInsensitiveCompare("SKILL.md") == .orderedSame
            ? url.deletingLastPathComponent()
            : nil
        let fallbackName = copyRoot?.lastPathComponent ?? url.deletingPathExtension().lastPathComponent
        return ResolvedImportSource(skillMarkdownURL: url, copyRootDirectory: copyRoot, fallbackName: fallbackName)
    }

    private static func replaceDirectory(at destination: URL, withContentsOf source: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }

    private static func firstSkillMarkdown(in directory: URL) throws -> URL {
        let direct = directory.appendingPathComponent("SKILL.md", isDirectory: false)
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw NSError(
                domain: "InstalledSkillStore",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not inspect folder: \(directory.path)"]
            )
        }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent.caseInsensitiveCompare("SKILL.md") == .orderedSame {
                return fileURL
            }
        }

        throw NSError(
            domain: "InstalledSkillStore",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "No `SKILL.md` file was found in that folder."]
        )
    }

    private static func normalizeSkillID(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }
        let slash = "/".unicodeScalars.first!
        let dot = ".".unicodeScalars.first!

        var out = ""
        var lastWasSeparator = false
        for scalar in trimmed.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if scalar == "_" || scalar == "-" {
                if !out.isEmpty, !lastWasSeparator {
                    out.unicodeScalars.append("_")
                    lastWasSeparator = true
                }
            } else if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == slash || scalar == dot {
                if !out.isEmpty, !lastWasSeparator {
                    out.unicodeScalars.append("_")
                    lastWasSeparator = true
                }
            }
        }
        while out.last == "_" { out.removeLast() }
        return out
    }

    private static func frontMatterValue(key: String, markdown: String) -> String? {
        let lines = markdown.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return nil }
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "---" { break }
            guard trimmed.lowercased().hasPrefix(key.lowercased() + ":") else { continue }
            let value = String(trimmed.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    private static func headingTitle(markdown: String) -> String? {
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("#") else { continue }
            return String(trimmed.drop { $0 == "#" || $0.isWhitespace }).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

private struct ResolvedImportSource {
    let skillMarkdownURL: URL
    let copyRootDirectory: URL?
    let fallbackName: String
}
