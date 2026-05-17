import Foundation

/// Anchor for `Bundle(for:)` when `Bundle.module` is empty (Xcode + local SPM edge cases).
private final class _OsaurusBundledPluginsBundleAnchor: NSObject {}

/// Loads [osaurus-tools `plugins/*.json`](https://github.com/osaurus-ai/osaurus-tools/tree/master/plugins)
/// from ``Bundle.module`` and exposes each tool as a synthetic MCP server (`plugin_id` → tool `name`).
public enum OsaurusBundledPluginToolRegistry {
    public static let registrySourceURL = URL(
        string: "https://github.com/osaurus-ai/osaurus-tools/tree/master/plugins")!

    private static let cache: (
        tools: [MCPToolsDiscoveryResult.InternalTool],
        servers: Set<String>,
        airSlugDisplayTitles: [String: String]
    ) = {
        let loaded = loadAllManifestToolsAndSlugTitles()
        return (loaded.tools, Set(loaded.tools.map(\.server)), loaded.airSlugDisplayTitles)
    }()

    /// Built-in tool rows merged into MCP discovery (after grizzyclaw parity tools).
    public static var internalTools: [MCPToolsDiscoveryResult.InternalTool] { cache.tools }

    /// Human titles from bundled `plugins/*.json` `name` field, keyed by the first segment of `grizzyclaw_air` tool ids
    /// (the segment after `osaurus.` in `plugin_id`, e.g. `notes` → "Apple Notes").
    public static var bundledAirSlugDisplayTitles: [String: String] { cache.airSlugDisplayTitles }

    public static func isBundledPluginServer(_ server: String) -> Bool {
        let s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        return cache.servers.contains(s)
    }

    private static func manifestJSONURLs() -> [URL] {
        var urls: [URL] = []
        if let batch = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "OsaurusPlugins") {
            urls.append(contentsOf: batch)
        }
        if urls.isEmpty {
            for base in Self.manifestResourceBasenames {
                if let u = Bundle.module.url(
                    forResource: base, withExtension: "json", subdirectory: "OsaurusPlugins")
                {
                    urls.append(u)
                } else if let u = Bundle.main.url(
                    forResource: base, withExtension: "json", subdirectory: "OsaurusPlugins")
                {
                    urls.append(u)
                } else if let u = Bundle(for: _OsaurusBundledPluginsBundleAnchor.self).url(
                    forResource: base, withExtension: "json", subdirectory: "OsaurusPlugins")
                {
                    urls.append(u)
                }
            }
        }
        return urls
    }

    private static func loadAllManifestToolsAndSlugTitles() -> (
        tools: [MCPToolsDiscoveryResult.InternalTool],
        airSlugDisplayTitles: [String: String]
    ) {
        let urls = manifestJSONURLs()
        var out: [MCPToolsDiscoveryResult.InternalTool] = []
        out.reserveCapacity(180)
        var slugTitles: [String: String] = [:]
        let looseObjectSchema: JSONValue = .object([
            "type": .string("object"),
            "description": .string(
                "Arguments for this tool (see Osaurus plugin manifest / SKILL in osaurus-tools)."),
            "additionalProperties": .bool(true),
        ])

        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let (tools, slug, title) = parseManifestJSONWithSlugTitle(data: data, defaultSchema: looseObjectSchema)
            out.append(contentsOf: tools)
            if let slug, let title, !slug.isEmpty, !title.isEmpty {
                slugTitles[slug] = title
            }
        }

        let sortedTools = out.sorted { a, b in
            if a.server != b.server { return a.server.localizedCaseInsensitiveCompare(b.server) == .orderedAscending }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return (sortedTools, slugTitles)
    }

    /// Basenames under `OsaurusPlugins/` (without `.json`) — fallback enumeration when directory listing is empty.
    private static let manifestResourceBasenames: [String] = [
        "osaurus.browser", "osaurus.calendar", "osaurus.contacts", "osaurus.emacs", "osaurus.fetch",
        "osaurus.images", "osaurus.macos-use", "osaurus.mail", "osaurus.maps", "osaurus.messages",
        "osaurus.music", "osaurus.notes", "osaurus.pptx", "osaurus.reminders", "osaurus.resend",
        "osaurus.search", "osaurus.telegram", "osaurus.time", "osaurus.vision", "osaurus.xlsx",
    ]

    private static func airSlug(fromPluginId pluginId: String) -> String {
        let s = pluginId.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("osaurus.") {
            return String(s.dropFirst("osaurus.".count))
        }
        return s
    }

    private static func parseManifestJSONWithSlugTitle(
        data: Data,
        defaultSchema: JSONValue
    ) -> (tools: [MCPToolsDiscoveryResult.InternalTool], airSlug: String?, displayTitle: String?) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let pluginId = (root["plugin_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !pluginId.isEmpty
        else { return ([], nil, nil) }

        let airSlug = airSlug(fromPluginId: pluginId)
        let cardTitle = (root["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        let pluginSummary = (root["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let caps = root["capabilities"] as? [String: Any] ?? [:]
        let tools = caps["tools"] as? [[String: Any]] ?? []

        var out: [MCPToolsDiscoveryResult.InternalTool] = []
        for t in tools {
            guard let name = (t["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty
            else { continue }
            let toolDesc = (t["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let combined: String = {
                if toolDesc.isEmpty { return pluginSummary }
                if pluginSummary.isEmpty { return toolDesc }
                return "\(pluginSummary)\n\n\(toolDesc)"
            }()
            out.append(
                MCPToolsDiscoveryResult.InternalTool(
                    server: pluginId,
                    name: name,
                    description: combined,
                    inputSchema: defaultSchema
                ))
        }
        return (out, airSlug, cardTitle)
    }
}
