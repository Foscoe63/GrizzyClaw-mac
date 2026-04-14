import Foundation

/// Anchor for `Bundle(for:)` when `Bundle.module` is empty (some Xcode + local SPM builds omit the package resource bundle).
private final class _BuiltinMCPMarketplaceBundleAnchor: NSObject {}

// MARK: - Parity with Python `grizzyclaw.skills.executors.DEFAULT_MCP_MARKETPLACE` + `MarketplaceDialog._load_servers`

/// One installable MCP server row from the built-in JSON or a remote marketplace URL.
public struct MCPMarketplaceServerEntry: Identifiable, Sendable, Equatable, Hashable {
    public let name: String
    public let command: String?
    public let args: [String]?
    public let url: String?
    public let description: String
    public let featured: Bool

    public var id: String { name }

    public init(
        name: String,
        command: String? = nil,
        args: [String]? = nil,
        url: String? = nil,
        description: String = "",
        featured: Bool = false
    ) {
        self.name = name
        self.command = command
        self.args = args
        self.url = url
        self.description = description
        self.featured = featured
    }

    /// Same shape as Python `MarketplaceDialog._install_selected` → `mcpServers[name]`.
    public func makeServerRow(enabled: Bool = true) -> MCPServerRow? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return nil }
        if let u = url?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            return MCPServerRow(name: n, enabled: enabled, dictionary: ["url": u])
        }
        guard let cmd = command?.trimmingCharacters(in: .whitespacesAndNewlines), !cmd.isEmpty else { return nil }
        let dict: [String: Any] = ["command": cmd, "args": args ?? []]
        return MCPServerRow(name: n, enabled: enabled, dictionary: dict)
    }
}

// MARK: - Categories / tools (Python `MarketplaceDialog`)

public enum MCPMarketplacePresentation {
    public static let categories: [(title: String, keywords: [String])] = [
        ("🌐 Web & Search", ["search", "ddg", "web", "browser", "playwright", "puppeteer", "scrape", "fetch"]),
        ("📁 Files & Storage", ["filesystem", "file", "storage", "s3", "drive", "dropbox"]),
        ("🔧 Development", ["github", "gitlab", "git", "docker", "kubernetes", "npm", "code", "shell"]),
        ("📊 Data & Analytics", ["database", "sql", "postgres", "mongo", "redis", "analytics", "sqlite"]),
        ("🤖 AI & ML", ["openai", "anthropic", "huggingface", "llm", "ai", "model", "memory", "thinking"]),
        ("📝 Productivity", ["notion", "slack", "discord", "email", "calendar", "todo", "time", "maps"]),
    ]

    public static let featuredNames: Set<String> = [
        "playwright-mcp", "filesystem", "github", "ddg-search", "memory", "sequential-thinking", "fetch",
    ]

    public static let estimatedTools: [String: Int] = [
        "playwright-mcp": 8, "puppeteer": 6, "ddg-search": 3, "brave-search": 2, "fetch": 2,
        "filesystem": 11, "google-drive": 5, "github": 12, "gitlab": 10,
        "sequential-thinking": 1, "sqlite": 6, "postgres": 5, "slack": 8,
        "google-maps": 4, "memory": 3, "everart": 2, "time": 2, "shell": 1,
    ]

    public static func category(for entry: MCPMarketplaceServerEntry) -> String {
        let text = "\(entry.name) \(entry.description)".lowercased()
        for (title, keywords) in categories {
            for kw in keywords where text.contains(kw) { return title }
        }
        return "🔌 Other"
    }

    public static func isFeatured(_ entry: MCPMarketplaceServerEntry) -> Bool {
        if entry.featured { return true }
        return featuredNames.contains(entry.name)
    }

    public static func estimatedToolsLabel(for entry: MCPMarketplaceServerEntry) -> String {
        if let t = estimatedTools[entry.name] { return "~\(t)" }
        return "?"
    }
}

// MARK: - Loaders

public enum MCPMarketplaceCatalogError: Error, LocalizedError {
    case missingBuiltinResource
    case invalidBuiltinData

    public var errorDescription: String? {
        switch self {
        case .missingBuiltinResource: return "Built-in MCP marketplace list is missing from the app bundle."
        case .invalidBuiltinData: return "Built-in MCP marketplace list could not be read."
        }
    }
}

public enum MCPMarketplaceCatalog {
    /// Loads `builtin_mcp_marketplace.json` (Python `DEFAULT_MCP_MARKETPLACE`).
    public static func loadBuiltIn() throws -> [MCPMarketplaceServerEntry] {
        guard let url = builtinMarketplaceJSONURL() else {
            throw MCPMarketplaceCatalogError.missingBuiltinResource
        }
        let data = try Data(contentsOf: url)
        return try decodeServerArray(from: data)
    }

    /// SwiftPM puts JSON in `Bundle.module`; the Xcode app target may copy the same file into `Bundle.main`.
    private static func builtinMarketplaceJSONURL() -> URL? {
        let name = "builtin_mcp_marketplace"
        let ext = "json"
        if let u = Bundle.module.url(forResource: name, withExtension: ext) { return u }
        if let u = Bundle.main.url(forResource: name, withExtension: ext) { return u }
        return Bundle(for: _BuiltinMCPMarketplaceBundleAnchor.self).url(forResource: name, withExtension: ext)
    }

    /// Fetches JSON from `marketplaceURL` (optional `servers` wrapper); on failure caller may fall back to `loadBuiltIn()`.
    public static func fetchRemoteJSON(from marketplaceURL: URL) async throws -> [MCPMarketplaceServerEntry] {
        var request = URLRequest(url: marketplaceURL)
        request.timeoutInterval = 20
        request.setValue("GrizzyClaw-Mac/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }
        return try decodeServerArray(from: data)
    }

    private static func decodeServerArray(from data: Data) throws -> [MCPMarketplaceServerEntry] {
        let obj = try JSONSerialization.jsonObject(with: data)
        let rawList: [[String: Any]]
        if let arr = obj as? [[String: Any]] {
            rawList = arr
        } else if let dict = obj as? [String: Any], let inner = dict["servers"] as? [[String: Any]] {
            rawList = inner
        } else {
            throw MCPMarketplaceCatalogError.invalidBuiltinData
        }
        var out: [MCPMarketplaceServerEntry] = []
        out.reserveCapacity(rawList.count)
        for d in rawList {
            guard let name = d["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let cmd = d["command"] as? String
            let args = d["args"] as? [String]
            let url = d["url"] as? String
            let desc = (d["description"] as? String) ?? ""
            let feat = (d["featured"] as? Bool) ?? false
            out.append(MCPMarketplaceServerEntry(
                name: name,
                command: cmd,
                args: args,
                url: url,
                description: desc,
                featured: feat
            ))
        }
        return out
    }
}
