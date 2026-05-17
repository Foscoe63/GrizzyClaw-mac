import Foundation

public struct GitHubSkillPreview: Identifiable, Hashable, Sendable {
    public let id: String
    public let suggestedSkillID: String
    public let title: String
    public let description: String
    public let markdown: String
    public let sourceLabel: String
}

public enum GitHubSkillImportService {
    private static func invalidGitHubURL(_ message: String) -> NSError {
        NSError(
            domain: "GitHubSkillImport",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    public static func fetchSkills(from input: String) async throws -> [GitHubSkillPreview] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "GitHubSkillImport",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Paste a GitHub repository or raw `SKILL.md` URL first."]
            )
        }
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            throw NSError(
                domain: "GitHubSkillImport",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "That is not a valid URL."]
            )
        }

        if host == "raw.githubusercontent.com" {
            return [try await fetchDirectSkill(rawURL: url, sourceLabel: url.absoluteString)]
        }

        guard host == "github.com" else {
            throw NSError(
                domain: "GitHubSkillImport",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Only GitHub repository and raw GitHub file URLs are supported."]
            )
        }

        let comps = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard comps.count >= 2 else {
            throw NSError(
                domain: "GitHubSkillImport",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Paste a full GitHub repository URL like `https://github.com/owner/repo`."]
            )
        }

        let owner = comps[0]
        let repo = comps[1].replacingOccurrences(of: ".git", with: "")
        let explicitPath = explicitSkillPath(pathComponents: comps)
        let branchCandidates = try await branchCandidates(owner: owner, repo: repo, preferredBranch: explicitPath?.branch)

        if let explicitPath {
            for branch in branchCandidates {
                let rawBase = try rawBaseURL(owner: owner, repo: repo, branch: branch)
                let candidate = rawBase.appendingPathComponent(explicitPath.path)
                if let preview = try await maybeFetchDirectSkill(rawURL: candidate, sourceLabel: candidate.absoluteString) {
                    return [preview]
                }
            }
        }

        for branch in branchCandidates {
            let rawBase = try rawBaseURL(owner: owner, repo: repo, branch: branch)
            let marketplaceURL = rawBase.appendingPathComponent(".claude-plugin/marketplace.json")
            if let previews = try await fetchMarketplaceSkills(marketplaceURL: marketplaceURL, rawBase: rawBase), !previews.isEmpty {
                return previews
            }
        }

        let commonPaths = [
            "SKILL.md",
            ".claude/SKILL.md",
            ".claude-plugin/SKILL.md",
            "skills/\(repo)/SKILL.md",
            ".claude/skills/\(repo)/SKILL.md",
        ]

        for branch in branchCandidates {
            let rawBase = try rawBaseURL(owner: owner, repo: repo, branch: branch)
            for path in commonPaths {
                let candidate = rawBase.appendingPathComponent(path)
                if let preview = try await maybeFetchDirectSkill(rawURL: candidate, sourceLabel: candidate.absoluteString) {
                    return [preview]
                }
            }
        }

        throw NSError(
            domain: "GitHubSkillImport",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "No importable `SKILL.md` or `.claude-plugin/marketplace.json` was found in that GitHub repository."]
        )
    }

    private static func explicitSkillPath(pathComponents: [String]) -> (branch: String, path: String)? {
        guard pathComponents.count >= 5 else { return nil }
        let marker = pathComponents[2].lowercased()
        guard marker == "blob" || marker == "tree" else { return nil }
        let branch = pathComponents[3]
        let remaining = pathComponents.dropFirst(4).joined(separator: "/")
        guard !remaining.isEmpty else { return nil }
        return (branch, remaining)
    }

    private static func branchCandidates(owner: String, repo: String, preferredBranch: String?) async throws -> [String] {
        var ordered: [String] = []
        if let preferredBranch, !preferredBranch.isEmpty { ordered.append(preferredBranch) }
        if let detected = try await detectDefaultBranch(owner: owner, repo: repo), !ordered.contains(detected) {
            ordered.append(detected)
        }
        for fallback in ["main", "master"] where !ordered.contains(fallback) {
            ordered.append(fallback)
        }
        return ordered
    }

    private static func detectDefaultBranch(owner: String, repo: String) async throws -> String? {
        guard let apiURL = githubRepoAPIURL(owner: owner, repo: repo) else {
            throw invalidGitHubURL("Could not build a GitHub API URL for that repository.")
        }
        guard let data = try await fetchData(apiURL) else { return nil }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["default_branch"] as? String
    }

    private static func fetchMarketplaceSkills(marketplaceURL: URL, rawBase: URL) async throws -> [GitHubSkillPreview]? {
        guard let data = try await fetchData(marketplaceURL) else { return nil }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = root["plugins"] as? [[String: Any]]
        else {
            return nil
        }

        var previews: [GitHubSkillPreview] = []
        var seenPaths = Set<String>()
        for plugin in plugins {
            guard let skills = plugin["skills"] as? [[String: Any]] else { continue }
            for skill in skills {
                guard let rawPath = skill["path"] as? String else { continue }
                let normalizedPath = rawPath.hasSuffix(".md") ? rawPath : "\(rawPath)/SKILL.md"
                guard seenPaths.insert(normalizedPath).inserted else { continue }
                let skillURL = rawBase.appendingPathComponent(normalizedPath)
                guard let markdown = try await fetchText(skillURL) else { continue }
                let suggestedID = InstalledSkillStore.suggestedSkillID(
                    markdown: markdown,
                    fallback: (skill["name"] as? String) ?? rawPath.components(separatedBy: "/").last
                )
                let rawTitle = (skill["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let title = rawTitle.isEmpty ? suggestedID : rawTitle
                let description = (skill["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                previews.append(
                    GitHubSkillPreview(
                        id: normalizedPath,
                        suggestedSkillID: suggestedID,
                        title: title,
                        description: description,
                        markdown: markdown,
                        sourceLabel: skillURL.absoluteString
                    )
                )
            }
        }
        return previews.isEmpty ? nil : previews
    }

    private static func fetchDirectSkill(rawURL: URL, sourceLabel: String) async throws -> GitHubSkillPreview {
        guard let markdown = try await fetchText(rawURL) else {
            throw NSError(
                domain: "GitHubSkillImport",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Could not download `SKILL.md` from GitHub."]
            )
        }
        let fallback = rawURL.deletingPathExtension().lastPathComponent.caseInsensitiveCompare("SKILL") == .orderedSame
            ? rawURL.deletingLastPathComponent().lastPathComponent
            : rawURL.deletingPathExtension().lastPathComponent
        let suggestedID = InstalledSkillStore.suggestedSkillID(markdown: markdown, fallback: fallback)
        return GitHubSkillPreview(
            id: rawURL.absoluteString,
            suggestedSkillID: suggestedID,
            title: suggestedID,
            description: "",
            markdown: markdown,
            sourceLabel: sourceLabel
        )
    }

    private static func maybeFetchDirectSkill(rawURL: URL, sourceLabel: String) async throws -> GitHubSkillPreview? {
        guard let markdown = try await fetchText(rawURL) else { return nil }
        let fallback = rawURL.deletingPathExtension().lastPathComponent.caseInsensitiveCompare("SKILL") == .orderedSame
            ? rawURL.deletingLastPathComponent().lastPathComponent
            : rawURL.deletingPathExtension().lastPathComponent
        let suggestedID = InstalledSkillStore.suggestedSkillID(markdown: markdown, fallback: fallback)
        return GitHubSkillPreview(
            id: rawURL.absoluteString,
            suggestedSkillID: suggestedID,
            title: suggestedID,
            description: "",
            markdown: markdown,
            sourceLabel: sourceLabel
        )
    }

    private static func githubRepoAPIURL(owner: String, repo: String) -> URL? {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "api.github.com"
        comps.percentEncodedPath = "/repos/\(owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? owner)/\(repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo)"
        return comps.url
    }

    private static func rawBaseURL(owner: String, repo: String, branch: String) throws -> URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "raw.githubusercontent.com"
        comps.percentEncodedPath = "/\(owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? owner)/\(repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo)/\(branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch)/"
        guard let url = comps.url else {
            throw invalidGitHubURL("Could not build a raw GitHub URL for that repository.")
        }
        return url
    }

    private static func fetchText(_ url: URL) async throws -> String? {
        guard let data = try await fetchData(url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func fetchData(_ url: URL) async throws -> Data? {
        var request = URLRequest(url: url)
        request.setValue("GrizzyClawMac/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 { return nil }
            throw NSError(
                domain: "GitHubSkillImport",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "GitHub returned HTTP \(http.statusCode) for \(url.absoluteString)."]
            )
        }
        return data
    }
}
