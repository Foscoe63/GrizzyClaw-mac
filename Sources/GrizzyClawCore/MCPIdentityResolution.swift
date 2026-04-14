import Foundation

/// Maps model-emitted MCP identifiers (often copied from Cursor docs, e.g. `user-ddg-search`) to
/// configured server names in `grizzyclaw.json` (e.g. `ddg-search`).
public enum MCPIdentityResolution: Sendable {
    private static func stripBracketSuffix(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = trimmed.firstIndex(of: "[") else { return trimmed }
        return String(trimmed[..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resolves `raw` to a server name present in `knownServers` when possible; otherwise returns trimmed `raw`.
    public static func canonicalServerName(modelOutput raw: String, knownServers: [String]) -> String {
        let trimmed = stripBracketSuffix(raw)
        guard !trimmed.isEmpty else { return trimmed }
        let knownSet = Set(knownServers)

        var cur = trimmed
        for _ in 0 ..< 8 {
            if knownSet.contains(cur) { return cur }
            let ci = knownServers.filter { $0.caseInsensitiveCompare(cur) == .orderedSame }
            if ci.count == 1 { return ci[0] }

            let lower = cur.lowercased()
            if lower.hasPrefix("user-") {
                cur = String(cur.dropFirst(5))
                continue
            }
            if lower == "web-search" || lower == "google-search" || lower == "search" {
                cur = "ddg-search"
                continue
            }
            let hyphen = cur.replacingOccurrences(of: "_", with: "-")
            if hyphen != cur {
                cur = hyphen
                continue
            }
            break
        }
        return trimmed
    }

    /// Resolves tool name against the tool list for one server (exact, then case-insensitive unique, then `_` → `-`).
    public static func canonicalToolName(modelOutput raw: String, knownTools: [String]) -> String {
        let trimmed = stripBracketSuffix(raw)
        guard !trimmed.isEmpty else { return trimmed }
        let knownSet = Set(knownTools)

        var cur = trimmed
        for _ in 0 ..< 8 {
            if knownSet.contains(cur) { return cur }
            let ci = knownTools.filter { $0.caseInsensitiveCompare(cur) == .orderedSame }
            if ci.count == 1 { return ci[0] }

            let hyphen = cur.replacingOccurrences(of: "_", with: "-")
            if hyphen != cur {
                cur = hyphen
                continue
            }
            break
        }
        // One tool on this server: models almost always say `search` while the MCP exposes a package-specific id.
        if knownTools.count == 1 { return knownTools[0] }
        return trimmed
    }
}
