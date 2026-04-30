import Foundation

public struct MCPToolDescriptor: Sendable, Equatable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue?

    public init(name: String, description: String, inputSchema: JSONValue? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct MCPToolsDiscoveryResult: Sendable {
    /// Server name → discovered MCP tools (name, description, optional input schema).
    public var servers: [String: [MCPToolDescriptor]]
    public var errorMessage: String?

    public init(servers: [String: [MCPToolDescriptor]], errorMessage: String?) {
        self.servers = servers
        self.errorMessage = errorMessage
    }
}

public enum MCPToolsDiscoveryError: Error, LocalizedError {
    case nativeDiscoveryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .nativeDiscoveryFailed(let s):
            return "MCP discovery failed: \(s)"
        }
    }
}

/// Native-Swift MCP tool discovery via `GrizzyMCPNativeRuntime`.
/// The legacy Python fallback (`mcp_discover.py`) has been removed — the app no longer
/// depends on a Python interpreter.
public enum MCPToolsDiscovery {
    private struct CacheKey: Hashable {
        let path: String
        let modificationTime: TimeInterval?
        let onlyServerNames: [String]?
    }

    private actor DiscoveryCache {
        static let shared = DiscoveryCache()
        private var store: [CacheKey: MCPToolsDiscoveryResult] = [:]

        func get(_ key: CacheKey) -> MCPToolsDiscoveryResult? {
            store[key]
        }

        func put(_ value: MCPToolsDiscoveryResult, for key: CacheKey) {
            store[key] = value
        }

        func removeAll(path: String) {
            store = store.filter { $0.key.path != path }
        }
    }

    /// - Parameter onlyServerNames: If non-empty, native discovery only connects to these rows (e.g. **Test** for one server). Avoids hanging on unrelated broken servers.
    public static func discover(
        mcpServersFile: String,
        onlyServerNames: Set<String>? = nil,
        forceRefresh: Bool = false
    ) async throws -> MCPToolsDiscoveryResult {
        let expanded = (mcpServersFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "~/.grizzyclaw/grizzyclaw.json" : mcpServersFile) as NSString
        let path = expanded.expandingTildeInPath
        let cacheKey = CacheKey(
            path: path,
            modificationTime: ((try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? nil)?.timeIntervalSince1970,
            onlyServerNames: onlyServerNames?.sorted()
        )

        if forceRefresh {
            await DiscoveryCache.shared.removeAll(path: path)
        } else if let cached = await DiscoveryCache.shared.get(cacheKey) {
            return cached
        }

        do {
            let url = URL(fileURLWithPath: path)
            let rows = try MCPServersFileIO.load(url: url)
            let rowsToProbe = probeRows(rows: rows, onlyServerNames: onlyServerNames)
            if rowsToProbe.isEmpty {
                if let filter = onlyServerNames, !filter.isEmpty {
                    return MCPToolsDiscoveryResult(servers: [:], errorMessage: "No MCP server in the JSON file matches the requested name(s).")
                }
                let empty = MCPToolsDiscoveryResult(servers: [:], errorMessage: nil)
                await DiscoveryCache.shared.put(empty, for: cacheKey)
                return empty
            }
            let native = try await GrizzyMCPNativeRuntime.shared.discoverTools(servers: rowsToProbe)
            let merged = native.mergingPythonInternalTools()
            await DiscoveryCache.shared.put(merged, for: cacheKey)
            return merged
        } catch {
            GrizzyClawLog.error("MCP native discovery failed: \(error.localizedDescription)")
            throw MCPToolsDiscoveryError.nativeDiscoveryFailed(error.localizedDescription)
        }
    }

    static func probeRows(rows: [MCPServerRow], onlyServerNames: Set<String>? = nil) -> [MCPServerRow] {
        let enabledRows = rows.filter(\.enabled)
        guard let filter = onlyServerNames, !filter.isEmpty else {
            return enabledRows
        }
        return enabledRows
            .filter { filter.contains($0.name) }
            .map { MCPServerRow(name: $0.name, enabled: true, dictionary: $0.dictionary) }
    }

    /// Validates a local stdio server by writing a temporary `grizzyclaw.json` and running native discovery on it.
    public static func validateStdioConfiguration(command: String, args: [String], env: [String: String]) async -> (ok: Bool, message: String) {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else {
            return (false, "No command set")
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("grizzyclaw_mcp_validate_\(UUID().uuidString).json", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: temp) }
        let cfg: [String: Any] = [
            "command": cmd,
            "args": args,
            "env": env,
        ]
        let payload: [String: Any] = [
            "mcpServers": [
                "_validate": cfg,
            ],
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try data.write(to: temp, options: .atomic)
        } catch {
            return (false, error.localizedDescription)
        }
        do {
            let r = try await discover(mcpServersFile: temp.path)
            if let err = r.errorMessage, !err.isEmpty {
                return (false, err)
            }
            let n = r.servers["_validate"]?.count ?? 0
            if n == 0 {
                return (false, "No tools returned")
            }
            return (true, "OK — \(n) tools")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// MARK: - Built-in Grizzy tools (native parity)

extension MCPToolsDiscoveryResult {
    public struct InternalTool: Sendable {
        public let server: String
        public let name: String
        public let description: String

        public init(server: String, name: String, description: String) {
            self.server = server
            self.name = name
            self.description = description
        }
    }

    /// Built-in native Grizzy tools — prepended before discovered MCP tools, deduped.
    public static let pythonInternalTools: [InternalTool] = [
        .init(
            server: "grizzyclaw",
            name: "get_status",
            description: "Show native chat status, workspace id, and MCP servers file."
        ),
        .init(
            server: "grizzyclaw",
            name: "create_scheduled_task",
            description: "Create a scheduled task in the scheduler using a cron expression and task message."
        ),
        .init(
            server: "grizzyclaw",
            name: "list_scheduled_tasks",
            description: "List scheduled tasks currently saved in the scheduler."
        ),
        .init(
            server: "grizzyclaw",
            name: "run_scheduled_task",
            description: "Run a scheduled task immediately by task id."
        ),
        .init(
            server: "grizzyclaw",
            name: "search_transcripts",
            description: "Search saved transcripts and session history."
        ),
    ]

    /// Flat merge: internal pairs first, then discovered (stable), deduped by (server, tool).
    public func mergingPythonInternalTools() -> MCPToolsDiscoveryResult {
        var seen = Set<String>()
        var flat: [(String, MCPToolDescriptor)] = []
        func pairKey(_ s: String, _ n: String) -> String { s + "\u{1E}" + n }
        for t in Self.pythonInternalTools {
            let k = pairKey(t.server, t.name)
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            flat.append((t.server, MCPToolDescriptor(name: t.name, description: t.description)))
        }
        for srv in servers.keys.sorted() {
            guard let tools = servers[srv] else { continue }
            for t in tools {
                let k = pairKey(srv, t.name)
                guard !seen.contains(k) else { continue }
                seen.insert(k)
                flat.append((srv, t))
            }
        }
        var by: [String: [MCPToolDescriptor]] = [:]
        for (srv, tool) in flat {
            by[srv, default: []].append(tool)
        }
        return MCPToolsDiscoveryResult(servers: by, errorMessage: errorMessage)
    }

    /// Hide tools outside the workspace `mcp_tool_allowlist` when that list is non-empty (`ws_allow`).
    /// Resolves each allow entry against discovered server/tool names (same rules as chat tool identity) so
    /// saved rows like `user-ddg-search` / case drift still match `ddg-search` from discovery.
    public func filteredByWorkspaceAllowlist(_ allow: [(String, String)]) -> MCPToolsDiscoveryResult {
        guard !allow.isEmpty else { return self }
        let knownServers = Array(servers.keys)
        var ok = Set<String>()
        for (a, b) in allow {
            ok.insert(a + "\u{1E}" + b)
        }
        for (asrv, atool) in allow {
            let canonSrv = MCPIdentityResolution.canonicalServerName(modelOutput: asrv, knownServers: knownServers)
            guard let toolList = servers[canonSrv] else { continue }
            let names = toolList.map(\.name)
            let canonTool = MCPIdentityResolution.canonicalToolName(modelOutput: atool, knownTools: names)
            ok.insert(canonSrv + "\u{1E}" + canonTool)
        }
        var by: [String: [MCPToolDescriptor]] = [:]
        for (srv, tools) in servers {
            let ft = tools.filter { ok.contains(srv + "\u{1E}" + $0.name) }
            if !ft.isEmpty { by[srv] = ft }
        }
        if by.isEmpty, !servers.isEmpty {
            GrizzyClawLog.info(
                "Workspace mcp_tool_allowlist matched no discovered tools (stale names or tool renames). Using full discovery for the chat tool list."
            )
            return self
        }
        return MCPToolsDiscoveryResult(servers: by, errorMessage: errorMessage)
    }
}
