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
        if loaded.tools.isEmpty {
            GrizzyClawLog.error(
                "OsaurusBundledPluginToolRegistry: loaded 0 plugin manifests — grizzyclaw_air will be empty. "
                    + "Rebuild the app (Product → Clean Build Folder) so OsaurusPlugins/*.json are embedded."
            )
        }
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

    private static var resourceBundles: [Bundle] {
        [Bundle.module, Bundle.main, Bundle(for: _OsaurusBundledPluginsBundleAnchor.self)]
    }

    /// Subdirectory names used by SwiftPM vs Xcode nested `Resources/` copies.
    private static let osaurusPluginSubdirectories = [
        "OsaurusPlugins",
        "Resources/OsaurusPlugins",
        "Resources/Resources/OsaurusPlugins",
    ]

    private static func manifestJSONURLs() -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func appendUnique(_ batch: [URL]) {
            for u in batch {
                let key = u.standardizedFileURL.path
                guard seen.insert(key).inserted else { continue }
                urls.append(u)
            }
        }

        for bundle in resourceBundles {
            for sub in osaurusPluginSubdirectories {
                if let batch = bundle.urls(forResourcesWithExtension: "json", subdirectory: sub) {
                    appendUnique(batch)
                }
                let dir = bundle.resourceURL?.appendingPathComponent(sub, isDirectory: true)
                if let dir, let items = try? FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: nil
                ) {
                    appendUnique(items.filter { $0.pathExtension == "json" })
                }
            }
        }

        if urls.isEmpty {
            for bundle in resourceBundles {
                for base in manifestResourceBasenames {
                    for sub in osaurusPluginSubdirectories {
                        if let u = bundle.url(
                            forResource: base, withExtension: "json", subdirectory: sub)
                        {
                            appendUnique([u])
                        }
                    }
                }
            }
        }

        if urls.isEmpty {
            appendUnique(sourceTreeManifestJSONURLs())
        }

        return urls
    }

    /// When the Xcode app bundle omits `OsaurusPlugins`, load manifests from the package source tree (same paths as the repo).
    private static func sourceTreeManifestJSONURLs() -> [URL] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/OsaurusPlugins", isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return items.filter { $0.pathExtension == "json" }
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
