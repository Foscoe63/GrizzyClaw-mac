import Foundation

/// First-party GrizzyClaw-Air tool surface for iPad (and any host that opts in).
///
/// - **Catalog**: `grizzyclaw` (Swift-defined internal + parity tools) plus a single namespace
///   ``airServerName`` whose tool ids are `pluginSlug.toolName` (e.g. `search.search`), delegating
///   to native Swift handlers registered under `osaurus.*` — **without** advertising `osaurus.*`
///   servers in the model-facing discovery map.
/// - **Execution**: map ``airServerName`` + dotted tool id back to `(osaurus.<slug>, toolName)` for
///   ``OsaurusBundledPluginToolHandlers``.
public enum GrizzyClawAirFirstPartyToolCatalog {
    public static let airServerName = "grizzyclaw_air"

    /// `osaurus.search` + `search` → `search.search` (plugin slug + `.` + MCP tool name).
    public static func airToolId(osaurusServer: String, osaurusTool: String) -> String {
        let s = osaurusServer.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug: String
        if s.hasPrefix("osaurus.") {
            slug = String(s.dropFirst("osaurus.".count))
        } else {
            slug = s
        }
        return "\(slug).\(osaurusTool)"
    }

    /// Inverse of ``airToolId(osaurusServer:osaurusTool:)`` when `tool` contains at least one `.`.
    public static func osaurusDelegation(server: String, tool: String) -> (String, String)? {
        guard server.trimmingCharacters(in: .whitespacesAndNewlines) == airServerName else {
            return nil
        }
        let t = tool.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dot = t.firstIndex(of: ".") else { return nil }
        let slug = String(t[..<dot])
        let rest = String(t[t.index(after: dot)...])
        guard !slug.isEmpty, !rest.isEmpty else { return nil }
        return ("osaurus.\(slug)", rest)
    }

    /// Chat / picker discovery: `grizzyclaw` + ``airServerName`` only (no `osaurus.*` keys).
    public static func iPadChatDiscovery() -> MCPToolsDiscoveryResult {
        var by: [String: [MCPToolDescriptor]] = [:]
        func appendInternal(_ tools: [MCPToolsDiscoveryResult.InternalTool]) {
            for t in tools {
                by[t.server, default: []].append(
                    MCPToolDescriptor(name: t.name, description: t.description, inputSchema: t.inputSchema))
            }
        }
        appendInternal(MCPToolsDiscoveryResult.pythonInternalTools)
        appendInternal(OsaurusParityToolDescriptors.tools)

        for t in OsaurusBundledPluginToolRegistry.internalTools {
            let airName = airToolId(osaurusServer: t.server, osaurusTool: t.name)
            by[airServerName, default: []].append(
                MCPToolDescriptor(name: airName, description: t.description, inputSchema: t.inputSchema))
        }
        return MCPToolsDiscoveryResult(servers: by, errorMessage: nil)
    }

    /// Workspace allowlists often store legacy `osaurus.*` pairs; expand so ``filteredByWorkspaceAllowlist``
    /// still matches ``iPadChatDiscovery()`` rows.
    public static func allowlistPairsIncludingAirAliases(_ pairs: [(String, String)]) -> [(String, String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        func add(_ s: String, _ t: String) {
            let k = s + "\u{1E}" + t
            guard !seen.contains(k) else { return }
            seen.insert(k)
            out.append((s, t))
        }
        for (s, t) in pairs {
            add(s, t)
            let srv = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if srv.hasPrefix("osaurus.") {
                add(airServerName, airToolId(osaurusServer: srv, osaurusTool: t))
            }
        }
        return out
    }

    /// Whether a stored allowlist composite (server+tool) should enable this first-party air tool in the editor UI.
    /// Uses the same `\u{1E}` composite format as workspace allowlist keys.
    public static func storedAllowlistContainsAirTool(storedComposites: Set<String>, airTool: String) -> Bool {
        if storedComposites.isEmpty { return true }
        let direct = allowlistComposite(server: airServerName, tool: airTool)
        if storedComposites.contains(direct) { return true }
        guard let (osSrv, osTool) = osaurusDelegation(server: airServerName, tool: airTool) else {
            return false
        }
        let legacy = allowlistComposite(server: osSrv, tool: osTool)
        return storedComposites.contains(legacy)
    }

    public static func allowlistComposite(server: String, tool: String) -> String {
        "\(server)\u{1E}\(tool)"
    }

    /// Ungrouped `grizzyclaw_air` tool ids (no `.`); shown under "Other" in workspace tool UI.
    public static let airToolUncategorizedSlug = "__uncategorized__"

    /// Display heading for a plugin group (first segment of `slug.tool`, e.g. `notes` → bundled "Apple Notes").
    public static func displayTitle(forAirPluginSlug slug: String) -> String {
        if slug == airToolUncategorizedSlug { return "Other" }
        let titles = OsaurusBundledPluginToolRegistry.bundledAirSlugDisplayTitles
        if let t = titles[slug], !t.isEmpty { return t }
        let spaced = slug.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return spaced.localizedCapitalized
    }

    /// After generic ``MCPIdentityResolution.canonicalToolName``, refine tool ids on ``airServerName``.
    public static func canonicalAirToolName(
        modelTool raw: String,
        knownTools: [String],
        genericCanonical: String
    ) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let knownSet = Set(knownTools)
        if knownSet.contains(genericCanonical) { return genericCanonical }
        if knownSet.contains(trimmed) { return trimmed }

        // Sloppy models: tool "search" on air server → prefer `search.search` when present.
        if trimmed == "search", knownTools.contains("search.search") { return "search.search" }
        if trimmed == "fetch", knownTools.contains("fetch.fetch") { return "fetch.fetch" }

        let dotted = knownTools.filter { $0.hasSuffix(".\(trimmed)") }
        if dotted.count == 1 { return dotted[0] }
        return genericCanonical
    }
}
