import Foundation

// MARK: - JSON file (~/.grizzyclaw/grizzyclaw.json) — Python `MCPTab._load_mcp_data` / `_save_mcp_data`

/// One row in the MCP Servers table (`name` is the key in `mcpServers` in JSON).
public struct MCPServerRow: Identifiable {
    public var id: String { name }
    public var name: String
    public var enabled: Bool
    /// Full server config as in Python (includes `url` or `command`/`args`, optional `headers`, `env`, …).
    public var dictionary: [String: Any]

    public init(name: String, enabled: Bool, dictionary: [String: Any]) {
        self.name = name
        self.enabled = enabled
        self.dictionary = dictionary
    }

    /// Merged record for UI/tooltips (always includes `name`).
    public func mergedRecord() -> [String: Any] {
        var m = dictionary
        m["name"] = name
        m["enabled"] = enabled
        return m
    }
}

extension MCPServerRow: @unchecked Sendable {}

public enum MCPServersFileIOError: Error, LocalizedError {
    case invalidJSON
    case cannotCreateParentDirectory

    public var errorDescription: String? {
        switch self {
        case .invalidJSON: return "The MCP servers file is not valid JSON."
        case .cannotCreateParentDirectory: return "Could not create the directory for the MCP servers file."
        }
    }
}

public enum MCPServersFileIO {
    public static func resolveJSONURL(mcpServersFile configValue: String) -> URL {
        let raw = configValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = (raw.isEmpty ? "~/.grizzyclaw/grizzyclaw.json" : raw) as NSString
        return URL(fileURLWithPath: path.expandingTildeInPath)
    }

    public static func load(url: URL) throws -> [MCPServerRow] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let rawServers = obj["mcpServers"] as? [String: Any] else {
            if obj["mcpServers"] != nil { throw MCPServersFileIOError.invalidJSON }
            return []
        }
        var rows: [MCPServerRow] = []
        for (name, val) in rawServers {
            guard var cfg = val as? [String: Any] else { throw MCPServersFileIOError.invalidJSON }
            let enabled = (cfg["enabled"] as? Bool) ?? true
            cfg.removeValue(forKey: "enabled")
            rows.append(MCPServerRow(name: name, enabled: enabled, dictionary: cfg))
        }
        rows.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return rows
    }

    /// Persists `{"mcpServers": { name: { … } } }` matching Python `MCPTab._save_mcp_data`.
    public static func save(url: URL, servers: [MCPServerRow]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var mcpDict: [String: [String: Any]] = [:]
        for s in servers {
            var cfg = buildSavedConfig(from: s)
            cfg["enabled"] = s.enabled
            mcpDict[s.name] = cfg
        }
        let payload: [String: Any] = ["mcpServers": mcpDict]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private static func buildSavedConfig(from row: MCPServerRow) -> [String: Any] {
        var cfg: [String: Any] = [:]
        let d = row.dictionary
        if let u = d["url"] as? String, !u.isEmpty {
            cfg["url"] = u
            if let h = d["headers"] as? [String: Any], !h.isEmpty { cfg["headers"] = h }
        }
        if let cmd = d["command"] as? String, !cmd.isEmpty {
            cfg["command"] = cmd
            cfg["args"] = d["args"] ?? []
            if let env = d["env"] as? [String: Any], !env.isEmpty { cfg["env"] = env }
            if let t = d["timeout_s"] as? Int, t > 0 { cfg["timeout_s"] = t }
            if let m = d["max_concurrency"] as? Int, m > 0 { cfg["max_concurrency"] = m }
        }
        return cfg
    }

    // MARK: - Quick add (Python `MCPTab._parse_quick_add`)

    /// Returns a partial record (`name`, `url` or `command`/`args`) or nil.
    public static func parseQuickAdd(_ raw: String) -> [String: Any]? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if t.hasPrefix("https://") || t.hasPrefix("http://") {
            return ["name": "remote", "url": t]
        }
        if t.hasPrefix("@") || t.contains("/") {
            let slug = t
            let name = slug.split(separator: "/").last.map(String.init) ?? "mcp_server"
            let base = name.split(separator: "@").last.map(String.init) ?? name
            let cleaned = base.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespaces)
            return ["name": cleaned.isEmpty ? "mcp_server" : cleaned, "command": "npx", "args": ["-y", slug]]
        }
        if t.lowercased().hasPrefix("pypi:") {
            let pkg = String(t.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).last ?? "").trimmingCharacters(in: .whitespaces)
            let namePart = pkg.split(separator: "[", maxSplits: 1).first.map(String.init) ?? "mcp_server"
            return ["name": namePart.isEmpty ? "mcp_server" : namePart, "command": "uvx", "args": [pkg]]
        }
        let parts = t.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !parts.isEmpty else { return nil }
        let cmd = parts[0]
        let args = Array(parts.dropFirst())
        var derivedName = "mcp_server"
        for a in args.reversed() {
            if a.contains("@") || a.contains("/") {
                derivedName = a.split(separator: "/").last.map(String.init) ?? a
                derivedName = derivedName.split(separator: "@").last.map(String.init) ?? derivedName
                derivedName = derivedName.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return ["name": derivedName, "command": cmd, "args": args]
    }
}
