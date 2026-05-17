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

    /// Raw discovery with **no** rows from `grizzyclaw.json` / MCP server file.
    /// After ``mergingPythonInternalTools()``, this yields built-in `grizzyclaw.*` plus bundled `osaurus.*`
    /// manifests so iPad chat and tool UI can run **without** configured MCP servers or native discovery.
    public static var withoutConfiguredMCPServers: MCPToolsDiscoveryResult {
        MCPToolsDiscoveryResult(servers: [:], errorMessage: nil)
    }
}

public enum MCPToolsDiscoveryError: Error, LocalizedError {
    case nativeDiscoveryFailed(String)
    case pythonNotFound
    case scriptResourceMissing
    case emptyOutput
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .nativeDiscoveryFailed(let s):
            return "MCP discovery failed: \(s)"
        case .pythonNotFound:
            return "Could not find python3 on this Mac (install Python 3 and pip install mcp httpx)."
        case .scriptResourceMissing:
            return "mcp_discover.py could not be found. Reinstall the app, or set GRIZZYCLAW_MCP_DISCOVER to the script path, or ensure ~/.grizzyclaw/support/mcp_discover.py exists."
        case .emptyOutput:
            return "MCP discovery produced no output."
        case .invalidJSON(let s):
            return "MCP discovery returned invalid JSON: \(s)"
        }
    }
}

/// Native-Swift MCP tool discovery via `GrizzyMCPNativeRuntime`, with optional Python fallback.
public enum MCPToolsDiscovery {
    public static let environmentScriptKey = "GRIZZYCLAW_MCP_DISCOVER"
    public static let forcePythonDiscoveryKey = "GRIZZYCLAW_MCP_USE_PYTHON"

    public static var cachedScriptURL: URL {
        GrizzyClawPaths.userDataDirectory.appendingPathComponent("support/mcp_discover.py", isDirectory: false)
    }
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
        let expanded =
            (mcpServersFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "~/.grizzyclaw/grizzyclaw.json" : mcpServersFile) as NSString
        let path = expanded.expandingTildeInPath
        let cacheKey = CacheKey(
            path: path,
            modificationTime: ((try? FileManager.default.attributesOfItem(atPath: path)[
                .modificationDate] as? Date) ?? nil)?.timeIntervalSince1970,
            onlyServerNames: onlyServerNames?.sorted()
        )

        if forceRefresh {
            await DiscoveryCache.shared.removeAll(path: path)
        } else if let cached = await DiscoveryCache.shared.get(cacheKey) {
            return cached
        }

        let forcePython = ProcessInfo.processInfo.environment[Self.forcePythonDiscoveryKey] == "1"
        if !forcePython {
            do {
                let url = URL(fileURLWithPath: path)
                let rows = try MCPServersFileIO.load(url: url)
                let rowsToProbe = probeRows(rows: rows, onlyServerNames: onlyServerNames)
                if rowsToProbe.isEmpty {
                    if let filter = onlyServerNames, !filter.isEmpty {
                        return MCPToolsDiscoveryResult(
                            servers: [:],
                            errorMessage:
                                "No MCP server in the JSON file matches the requested name(s).")
                    }
                    let mergedEmpty = MCPToolsDiscoveryResult(servers: [:], errorMessage: nil)
                        .mergingPythonInternalTools()
                    await DiscoveryCache.shared.put(mergedEmpty, for: cacheKey)
                    return mergedEmpty
                }
                let native = try await GrizzyMCPNativeRuntime.shared.discoverTools(servers: rowsToProbe)
                let merged = native.mergingPythonInternalTools()
                await DiscoveryCache.shared.put(merged, for: cacheKey)
                return merged
            } catch {
                GrizzyClawLog.error(
                    "MCP native discovery failed, falling back to Python: \(error.localizedDescription)")
            }
        }

        let pythonMerged = try await discoverViaPythonScript(path: path)
        await DiscoveryCache.shared.put(pythonMerged, for: cacheKey)
        return pythonMerged
    }

    private static func discoverViaPythonScript(path: String) async throws -> MCPToolsDiscoveryResult {
        guard let scriptURL = resolveMcpDiscoverScriptURL() else {
            throw MCPToolsDiscoveryError.scriptResourceMissing
        }
        let python = resolvePython3Executable()
        guard FileManager.default.isExecutableFile(atPath: python) else {
            throw MCPToolsDiscoveryError.pythonNotFound
        }

        let scriptPath = scriptURL.path
        let outData: Data = try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: python)
            proc.arguments = [scriptPath, path]
            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            try proc.run()
            let killTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(43 * 1_000_000_000))
                if proc.isRunning { proc.terminate() }
            }
            proc.waitUntilExit()
            killTask.cancel()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !outData.isEmpty else {
                if !errText.isEmpty { throw MCPToolsDiscoveryError.invalidJSON(errText) }
                throw MCPToolsDiscoveryError.emptyOutput
            }
            return outData
        }.value
        guard let raw = try JSONSerialization.jsonObject(with: outData) as? [String: Any] else {
            throw MCPToolsDiscoveryError.invalidJSON("not an object")
        }

        let err: String?
        if let e = raw["error"] as? String, !e.isEmpty {
            err = e
        } else if raw["error"] is NSNull {
            err = nil
        } else {
            err = raw["error"] as? String
        }

        var servers: [String: [MCPToolDescriptor]] = [:]
        if let srv = raw["servers"] as? [String: Any] {
            for (name, val) in srv {
                guard let rows = val as? [[Any]] else { continue }
                var tools: [MCPToolDescriptor] = []
                for row in rows {
                    guard row.count >= 1 else { continue }
                    let tool = String(describing: row[0])
                    let desc = row.count >= 2 ? String(describing: row[1]) : ""
                    if !tool.isEmpty {
                        tools.append(MCPToolDescriptor(name: tool, description: desc))
                    }
                }
                if !tools.isEmpty { servers[name] = tools }
            }
        }
        return MCPToolsDiscoveryResult(servers: servers, errorMessage: err).mergingPythonInternalTools()
    }

    private static func resolveMcpDiscoverScriptURL() -> URL? {
        let fm = FileManager.default
        if let raw = ProcessInfo.processInfo.environment[Self.environmentScriptKey], !raw.isEmpty {
            let u = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
            if fm.isReadableFile(atPath: u.path) { return u }
        }
        if let bundled = locateBundledMcpDiscoverScript() {
            try? fm.createDirectory(at: cachedScriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: cachedScriptURL)
            try? fm.copyItem(at: bundled, to: cachedScriptURL)
            return bundled
        }
        if fm.isReadableFile(atPath: cachedScriptURL.path) { return cachedScriptURL }
        return nil
    }

    private static func locateBundledMcpDiscoverScript() -> URL? {
        let fm = FileManager.default
        let filename = "mcp_discover.py"
        let bundles: [Bundle] = [Bundle.module, Bundle.main, Bundle(for: MCPToolsDiscoveryBundleAnchor.self)]
        for b in bundles {
            if let u = b.url(forResource: "mcp_discover", withExtension: "py"), fm.isReadableFile(atPath: u.path) {
                return u
            }
            if let r = b.resourceURL {
                let direct = r.appendingPathComponent(filename)
                if fm.isReadableFile(atPath: direct.path) { return direct }
                let alt = r.appendingPathComponent("Resources/\(filename)")
                if fm.isReadableFile(atPath: alt.path) { return alt }
            }
        }
        return nil
    }

    private static func resolvePython3Executable() -> String {
        for p in ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return "/usr/bin/python3"
    }

    static func probeRows(rows: [MCPServerRow], onlyServerNames: Set<String>? = nil)
        -> [MCPServerRow]
    {
        let enabledRows = MCPServersFileIO.filterMCPRowsForRuntimePlatform(rows.filter(\.enabled))
        guard let filter = onlyServerNames, !filter.isEmpty else {
            return enabledRows
        }
        return
            enabledRows
            .filter { filter.contains($0.name) }
            .map { MCPServerRow(name: $0.name, enabled: true, dictionary: $0.dictionary) }
    }

    /// Validates a local stdio server by writing a temporary `grizzyclaw.json` and running native discovery on it.
    public static func validateStdioConfiguration(
        command: String, args: [String], env: [String: String]
    ) async -> (ok: Bool, message: String) {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else {
            return (false, "No command set")
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "grizzyclaw_mcp_validate_\(UUID().uuidString).json", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: temp) }
        let cfg: [String: Any] = [
            "command": cmd,
            "args": args,
            "env": env,
        ]
        let payload: [String: Any] = [
            "mcpServers": [
                "_validate": cfg
            ]
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

private final class MCPToolsDiscoveryBundleAnchor: NSObject {}

// MARK: - Built-in Grizzy tools (native parity)

extension MCPToolsDiscoveryResult {
    public struct InternalTool: Sendable {
        public let server: String
        public let name: String
        public let description: String
        public let inputSchema: JSONValue?

        public init(
            server: String, name: String, description: String, inputSchema: JSONValue? = nil
        ) {
            self.server = server
            self.name = name
            self.description = description
            self.inputSchema = inputSchema
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
            description:
                "Create a scheduled task in the scheduler using a cron expression and task message."
        ),
        .init(
            server: "grizzyclaw",
            name: "list_scheduled_tasks",
            description: "List scheduled tasks currently saved in the scheduler."
        ),
        .init(
            server: "grizzyclaw",
            name: "search_transcripts",
            description: "Search saved chat session transcripts on disk (workspace sessions).",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("Substring query to search for (case-insensitive)."),
                    ]),
                    "top_k": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "Max number of matches to return (default 10, clamp 1..50)."),
                        "default": .int(10),
                    ]),
                ]),
                "required": .array([.string("query")]),
            ])
        ),
        .init(
            server: "grizzyclaw",
            name: "list_installed_skills",
            description: "List installed skills available to enable in workspaces.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([:]),
            ])
        ),
        .init(
            server: "grizzyclaw",
            name: "capabilities_search",
            description:
                "Search installed skills and available tools by keyword and return capability IDs for loading.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "queries": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string(
                            "One or more search queries describing what capability you need."),
                    ])
                ]),
                "required": .array([.string("queries")]),
            ])
        ),
        .init(
            server: "grizzyclaw",
            name: "capabilities_load",
            description:
                "Load capability IDs returned by capabilities_search (skills only for now).",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "ids": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("IDs from capabilities_search (e.g. skill/<id>)."),
                    ])
                ]),
                "required": .array([.string("ids")]),
            ])
        ),
        .init(
            server: "grizzyclaw",
            name: "run_scheduled_task",
            description: "Run a scheduled task immediately by task id."
        ),
    ]

    /// `pythonInternalTools` plus Osaurus `ToolRegistry` parity tools plus bundled osaurus-tools plugin manifests.
    public static let allBundledInternalTools: [InternalTool] =
        pythonInternalTools + OsaurusParityToolDescriptors.tools
        + OsaurusBundledPluginToolRegistry.internalTools

    /// Flat merge: internal pairs first, then discovered (stable), deduped by (server, tool).
    public func mergingPythonInternalTools() -> MCPToolsDiscoveryResult {
        var seen = Set<String>()
        var flat: [(String, MCPToolDescriptor)] = []
        func pairKey(_ s: String, _ n: String) -> String { s + "\u{1E}" + n }
        for t in Self.allBundledInternalTools {
            let k = pairKey(t.server, t.name)
            guard !seen.contains(k) else { continue }
            seen.insert(k)
            flat.append(
                (
                    t.server,
                    MCPToolDescriptor(
                        name: t.name, description: t.description, inputSchema: t.inputSchema)
                ))
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
    public func filteredByWorkspaceAllowlist(_ allow: [(String, String)]) -> MCPToolsDiscoveryResult
    {
        guard !allow.isEmpty else { return self }
        let knownServers = Array(servers.keys)
        var ok = Set<String>()
        for (a, b) in allow {
            ok.insert(a + "\u{1E}" + b)
        }
        for (asrv, atool) in allow {
            let canonSrv = MCPIdentityResolution.canonicalServerName(
                modelOutput: asrv, knownServers: knownServers)
            guard let toolList = servers[canonSrv] else { continue }
            let names = toolList.map(\.name)
            let canonTool = MCPIdentityResolution.canonicalToolName(
                modelOutput: atool, knownTools: names)
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
