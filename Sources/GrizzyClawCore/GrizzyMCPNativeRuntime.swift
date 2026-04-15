import Foundation
import MCP
import System

// MARK: - Errors

public enum GrizzyMCPNativeError: LocalizedError {
    case serverNotFound(String)
    case serverDisabled(String)
    case notConnected(String)
    case invalidURL(String)
    case localExecutableInvalid(String)
    case localSpawnFailed(String)
    case timeout
    case toolExecutionFailed(String)
    case unsupportedArgumentType(String)

    public var errorDescription: String? {
        switch self {
        case .serverNotFound(let n): return "MCP server not in config: \(n)"
        case .serverDisabled(let n): return "MCP server disabled: \(n)"
        case .notConnected(let n): return "Not connected to MCP server: \(n)"
        case .invalidURL(let u): return "Invalid MCP URL: \(u)"
        case .localExecutableInvalid(let m): return m
        case .localSpawnFailed(let m): return m
        case .timeout: return "MCP request timed out"
        case .toolExecutionFailed(let m): return m
        case .unsupportedArgumentType(let m): return "Unsupported MCP argument type: \(m)"
        }
    }
}

/// Native MCP client (HTTP + stdio) using the official [swift-sdk](https://github.com/modelcontextprotocol/swift-sdk), aligned with Osaurus `MCPProviderManager`.
@MainActor
public final class GrizzyMCPNativeRuntime: ObservableObject {
    public static let shared = GrizzyMCPNativeRuntime()

    private struct LocalSession {
        let process: Process
        let stdinPipe: Pipe
        let stdoutPipe: Pipe
    }

    private var clients: [String: Client] = [:]
    private var localSessions: [String: LocalSession] = [:]

    private init() {}

    private static let clientName = "GrizzyClaw"
    private static let clientVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    // MARK: - Discovery (list tools for all enabled servers)

    public func discoverTools(servers: [MCPServerRow]) async throws -> MCPToolsDiscoveryResult {
        var serversMap: [String: [MCPToolDescriptor]] = [:]
        var errs: [String] = []

        for row in servers where row.enabled {
            do {
                let pairs = try await Self.discoverToolsForRow(row)
                serversMap[row.name] = pairs
            } catch {
                GrizzyClawLog.error("MCP discovery [\(row.name)]: \(error.localizedDescription)")
                errs.append("\(row.name): \(error.localizedDescription)")
                // Keep going so one broken server does not erase working ones.
                continue
            }
        }

        let errMsg: String?
        if errs.isEmpty {
            errMsg = nil
        } else {
            errMsg = errs.joined(separator: "\n")
        }
        return MCPToolsDiscoveryResult(servers: serversMap, errorMessage: errMsg)
    }

    private nonisolated static func discoverToolsForRow(_ row: MCPServerRow) async throws -> [MCPToolDescriptor] {
        let discT = discoveryTimeout(from: row)
        let tools: [Tool]
        if row.dictionary["url"] != nil {
            let client = try await connectRemoteDiscoveryClient(row: row)
            defer { Task { await client.disconnect() } }
            tools = try await GrizzyAsyncTimeout.run(seconds: discT, timeoutError: GrizzyMCPNativeError.timeout) {
                try await listAllTools(client: client)
            }
        } else {
            tools = try await discoverLocalTools(row: row, timeout: discT)
        }
        return tools.map { t in
            MCPToolDescriptor(
                name: t.name,
                description: String((t.description ?? "").prefix(400)),
                inputSchema: mcpSchemaJSONValue(t.inputSchema)
            )
        }
    }

    private nonisolated static func mcpSchemaJSONValue(_ schema: Value) -> JSONValue? {
        do {
            let data = try JSONEncoder().encode(schema)
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            GrizzyClawLog.error("MCP schema conversion failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func listAllTools(client: Client) async throws -> [Tool] {
        var all: [Tool] = []
        var cursor: String?
        repeat {
            let (tools, next) = try await client.listTools(cursor: cursor)
            all.append(contentsOf: tools)
            cursor = next
        } while cursor != nil
        return all
    }

    private nonisolated static func connectRemoteDiscoveryClient(row: MCPServerRow) async throws -> Client {
        guard let urlStr = row.dictionary["url"] as? String,
              let endpoint = URL(string: urlStr.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            throw GrizzyMCPNativeError.invalidURL((row.dictionary["url"] as? String) ?? "")
        }
        let disc = discoveryTimeout(from: row)
        let configuration = URLSessionConfiguration.default
        let headers = Self.stringHeaders(from: row.dictionary["headers"])
        if !headers.isEmpty {
            configuration.httpAdditionalHeaders = headers
        }
        configuration.timeoutIntervalForRequest = disc
        configuration.timeoutIntervalForResource = disc
        let transport = HTTPClientTransport(
            endpoint: endpoint,
            configuration: configuration,
            streaming: false
        )
        let client = Client(name: "GrizzyClaw", version: "1.0.0")
        _ = try await GrizzyAsyncTimeout.run(seconds: disc, timeoutError: GrizzyMCPNativeError.timeout) {
            try await client.connect(transport: transport)
        }
        return client
    }

    private nonisolated static func discoverLocalTools(row: MCPServerRow, timeout: TimeInterval) async throws -> [Tool] {
        guard let cmd = row.dictionary["command"] as? String,
              !cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw GrizzyMCPNativeError.localExecutableInvalid("No command for local MCP server \(row.name)")
        }
        guard let resolved = MCPLocalMCPProcessController.resolveExecutable(cmd) else {
            throw GrizzyMCPNativeError.localExecutableInvalid("Command not found: \(cmd)")
        }
        let args = MCPServerRuntimeStatus.normalizeMCPArgs(row.dictionary["args"])
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = args
        if let env = row.dictionary["env"] as? [String: Any] {
            process.environment = MCPLocalMCPProcessController.expandedEnvironmentForMCP(merging: env)
        } else {
            process.environment = MCPLocalMCPProcessController.expandedEnvironmentForMCP(merging: nil)
        }
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw GrizzyMCPNativeError.localSpawnFailed(error.localizedDescription)
        }
        let readFd = FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor)
        let writeFd = FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)
        let transport = StdioTransport(input: readFd, output: writeFd)
        let client = Client(name: "GrizzyClaw", version: "1.0.0")
        defer {
            Task { await client.disconnect() }
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        _ = try await GrizzyAsyncTimeout.run(seconds: timeout, timeoutError: GrizzyMCPNativeError.timeout) {
            try await client.connect(transport: transport)
        }
        return try await GrizzyAsyncTimeout.run(seconds: timeout, timeoutError: GrizzyMCPNativeError.timeout) {
            try await listAllTools(client: client)
        }
    }

    // MARK: - Tool call

    public func callTool(
        mcpServersFile: String,
        server: String,
        tool: String,
        arguments: [String: Any]
    ) async throws -> String {
        let expanded = (mcpServersFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "~/.grizzyclaw/grizzyclaw.json" : mcpServersFile) as NSString
        let path = expanded.expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        let rows = try MCPServersFileIO.load(url: url)
        let knownServers = rows.map(\.name)
        let canonicalRequestedServer = MCPIdentityResolution.canonicalServerName(
            modelOutput: server,
            knownServers: knownServers
        )
        guard let row = rows.first(where: {
            MCPIdentityResolution.canonicalServerName(modelOutput: $0.name, knownServers: knownServers)
                == canonicalRequestedServer
        }) else {
            throw GrizzyMCPNativeError.serverNotFound(canonicalRequestedServer)
        }
        guard row.enabled else {
            throw GrizzyMCPNativeError.serverDisabled(canonicalRequestedServer)
        }

        if clients[row.name] == nil {
            _ = try await connectClient(for: row)
        }
        guard let client = clients[row.name] else {
            throw GrizzyMCPNativeError.notConnected(canonicalRequestedServer)
        }

        let args = try GrizzyMCPValueConversion.mcpValues(from: arguments)
        let toolTimeout = toolCallTimeout(from: row)

        let (content, isError) = try await Self.callMCPTool(
            client: client,
            toolName: tool,
            arguments: args,
            timeout: toolTimeout
        )
        if let isError, isError {
            let errorText = GrizzyMCPValueConversion.string(from: content)
            throw GrizzyMCPNativeError.toolExecutionFailed(errorText.isEmpty ? "Tool returned error" : errorText)
        }
        return GrizzyMCPValueConversion.string(from: content)
    }

    private nonisolated static func callMCPTool(
        client: Client,
        toolName: String,
        arguments: [String: Value],
        timeout: TimeInterval
    ) async throws -> ([Tool.Content], Bool?) {
        try await GrizzyAsyncTimeout.run(seconds: timeout, timeoutError: GrizzyMCPNativeError.timeout) {
            try await client.callTool(name: toolName, arguments: arguments)
        }
    }

    // MARK: - Validate (add / edit sheet)

    public func testRemote(urlString: String, headers: [String: String]) async throws -> Int {
        guard let endpoint = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw GrizzyMCPNativeError.invalidURL(urlString)
        }
        let configuration = URLSessionConfiguration.default
        if !headers.isEmpty {
            configuration.httpAdditionalHeaders = headers
        }
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        let transport = HTTPClientTransport(
            endpoint: endpoint,
            configuration: configuration,
            streaming: false
        )
        let client = Client(name: Self.clientName, version: Self.clientVersion)
        _ = try await client.connect(transport: transport)
        let n = try await Self.listAllTools(client: client).count
        await client.disconnect()
        return n
    }

    public func testLocal(
        command: String,
        args: [String],
        env: [String: String]
    ) async throws -> Int {
        let exe = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let resolved = MCPLocalMCPProcessController.resolveExecutable(exe) else {
            throw GrizzyMCPNativeError.localExecutableInvalid("Command not found: \(exe)")
        }
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = args
        let merged = MCPLocalMCPProcessController.expandedEnvironmentForMCP(merging: env)
        process.environment = merged
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw GrizzyMCPNativeError.localSpawnFailed(error.localizedDescription)
        }
        let readHandle = stdoutPipe.fileHandleForReading
        let writeHandle = stdinPipe.fileHandleForWriting
        let readFd = FileDescriptor(rawValue: readHandle.fileDescriptor)
        let writeFd = FileDescriptor(rawValue: writeHandle.fileDescriptor)
        let transport = StdioTransport(input: readFd, output: writeFd)
        let client = Client(name: Self.clientName, version: Self.clientVersion)
        do {
            _ = try await client.connect(transport: transport)
            let n = try await withTimeout(seconds: 25) {
                try await Self.listAllTools(client: client)
            }.count
            await client.disconnect()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            return n
        } catch {
            await client.disconnect()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            throw error
        }
    }

    // MARK: - Connect / disconnect

    private func connectClient(for row: MCPServerRow) async throws -> Client {
        if let existing = clients[row.name] {
            return existing
        }
        if row.dictionary["url"] != nil {
            return try await connectRemote(row: row)
        }
        return try await connectLocal(row: row)
    }

    private func connectRemote(row: MCPServerRow) async throws -> Client {
        guard let urlStr = row.dictionary["url"] as? String,
              let endpoint = URL(string: urlStr.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            throw GrizzyMCPNativeError.invalidURL((row.dictionary["url"] as? String) ?? "")
        }
        let disc = Self.discoveryTimeout(from: row)
        let toolT = toolCallTimeout(from: row)
        let configuration = URLSessionConfiguration.default
        let headers = Self.stringHeaders(from: row.dictionary["headers"])
        if !headers.isEmpty {
            configuration.httpAdditionalHeaders = headers
        }
        configuration.timeoutIntervalForRequest = disc
        configuration.timeoutIntervalForResource = max(disc, toolT)
        let transport = HTTPClientTransport(
            endpoint: endpoint,
            configuration: configuration,
            streaming: false
        )
        let client = Client(name: Self.clientName, version: Self.clientVersion)
        _ = try await client.connect(transport: transport)
        clients[row.name] = client
        return client
    }

    private func connectLocal(row: MCPServerRow) async throws -> Client {
        guard let cmd = row.dictionary["command"] as? String,
              !cmd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw GrizzyMCPNativeError.localExecutableInvalid("No command for local MCP server \(row.name)")
        }
        guard let resolved = MCPLocalMCPProcessController.resolveExecutable(cmd) else {
            throw GrizzyMCPNativeError.localExecutableInvalid("Command not found: \(cmd)")
        }
        let args = MCPServerRuntimeStatus.normalizeMCPArgs(row.dictionary["args"])
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = args
        if let env = row.dictionary["env"] as? [String: Any] {
            process.environment = MCPLocalMCPProcessController.expandedEnvironmentForMCP(merging: env)
        } else {
            process.environment = MCPLocalMCPProcessController.expandedEnvironmentForMCP(merging: nil)
        }
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw GrizzyMCPNativeError.localSpawnFailed(error.localizedDescription)
        }
        localSessions[row.name] = LocalSession(process: process, stdinPipe: stdinPipe, stdoutPipe: stdoutPipe)
        let readFd = FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor)
        let writeFd = FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)
        let transport = StdioTransport(input: readFd, output: writeFd)
        let client = Client(name: Self.clientName, version: Self.clientVersion)
        do {
            _ = try await client.connect(transport: transport)
        } catch {
            cleanupFailedLocal(name: row.name)
            throw error
        }
        clients[row.name] = client
        return client
    }

    private func cleanupFailedLocal(name: String) {
        clients.removeValue(forKey: name)
        if let session = localSessions.removeValue(forKey: name) {
            if session.process.isRunning { session.process.terminate() }
            session.process.waitUntilExit()
        }
    }

    public func disconnect(name: String) {
        Task {
            if let c = clients.removeValue(forKey: name) {
                await c.disconnect()
            }
            if let session = localSessions.removeValue(forKey: name) {
                if session.process.isRunning { session.process.terminate() }
                session.process.waitUntilExit()
            }
        }
    }

    public func disconnectAll() {
        let names = Array(clients.keys)
        for n in names {
            disconnect(name: n)
        }
    }

    private nonisolated static func discoveryTimeout(from row: MCPServerRow) -> TimeInterval {
        if let t = row.dictionary["timeout_s"] as? Int, t > 0 {
            return TimeInterval(min(300, max(5, t)))
        }
        return 10
    }

    private func toolCallTimeout(from row: MCPServerRow) -> TimeInterval {
        Self.discoveryTimeout(from: row) + 20
    }

    private nonisolated static func stringHeaders(from any: Any?) -> [String: String] {
        guard let h = any as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in h {
            out[String(describing: k)] = String(describing: v)
        }
        return out
    }

    private func withTimeout<T: Sendable>(seconds: TimeInterval, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await GrizzyAsyncTimeout.run(seconds: seconds, timeoutError: GrizzyMCPNativeError.timeout, operation: op)
    }
}
