import Foundation

/// Runs bundled `mcp_call_tool.py` (stdio JSON in → JSON out), matching Python `call_mcp_tool` behavior.
public enum MCPToolCallerError: Error, LocalizedError {
    case scriptMissing
    case pythonNotFound
    case emptyOutput
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .scriptMissing:
            return "mcp_call_tool.py not found in the app bundle. Set GRIZZYCLAW_MCP_CALL_TOOL or reinstall."
        case .pythonNotFound:
            return "python3 not found (install Python 3 and pip install mcp httpx)."
        case .emptyOutput:
            return "MCP tool call produced no output."
        case .invalidResponse(let s):
            return "MCP tool call parse error: \(s)"
        }
    }
}

public enum MCPToolCaller {
    public static let environmentScriptKey = "GRIZZYCLAW_MCP_CALL_TOOL"

    public static var cachedScriptURL: URL {
        GrizzyClawPaths.userDataDirectory.appendingPathComponent("support/mcp_call_tool.py", isDirectory: false)
    }

    /// Set `GRIZZYCLAW_MCP_USE_PYTHON=1` to skip the native Swift MCP client and use `mcp_call_tool.py`.
    public static let forcePythonCallKey = "GRIZZYCLAW_MCP_USE_PYTHON"

    /// Invoke one MCP tool; returns result text (including `**❌` error lines from the helper on failure).
    @MainActor
    public static func call(
        mcpServersFile: String,
        mcpServer: String,
        tool: String,
        arguments: [String: Any]
    ) async throws -> String {
        let expanded = (mcpServersFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "~/.grizzyclaw/grizzyclaw.json" : mcpServersFile) as NSString
        let path = expanded.expandingTildeInPath
        let normalizedArguments = normalizedArgumentsForLowContextMetaTool(
            server: mcpServer,
            tool: tool,
            arguments: arguments
        )

        let forcePython = ProcessInfo.processInfo.environment[Self.forcePythonCallKey] == "1"
        if !forcePython {
            do {
                return try await GrizzyMCPNativeRuntime.shared.callTool(
                    mcpServersFile: path,
                    server: mcpServer,
                    tool: tool,
                    arguments: normalizedArguments
                )
            } catch {
                GrizzyClawLog.error("MCP native tool call failed, falling back to Python: \(error.localizedDescription)")
            }
        }

        return try await callViaPythonHelper(
            mcpFilePath: path,
            mcpServer: mcpServer,
            tool: tool,
            arguments: normalizedArguments
        )
    }

    static func normalizedArgumentsForLowContextMetaTool(
        server: String,
        tool: String,
        arguments: [String: Any]
    ) -> [String: Any] {
        guard tool == "get_tool_definitions" else { return arguments }
        guard let names = arguments["names"] as? [Any] else { return arguments }

        let normalizedNames = names.compactMap { item -> String? in
            let text = String(describing: item).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        let lowercased = normalizedNames.map { $0.lowercased() }
        let obviousPlaceholders = Set(["item", "items", "tool", "tools", "function", "functions", "name", "names"])
        let shouldPatch =
            normalizedNames.isEmpty
            || (normalizedNames.count == 1 && obviousPlaceholders.contains(lowercased[0]))
        guard shouldPatch else { return arguments }

        var patched = arguments
        patched["names"] = ["*"]
        let trimmedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalSummary = normalizedNames.isEmpty ? "empty names" : "placeholder names \(normalizedNames)"
        GrizzyClawLog.info("MCP normalized \(trimmedServer).get_tool_definitions \(originalSummary) -> [\"*\"]")
        return patched
    }

    @MainActor
    private static func callViaPythonHelper(
        mcpFilePath: String,
        mcpServer: String,
        tool: String,
        arguments: [String: Any]
    ) async throws -> String {
        guard let scriptURL = resolveScriptURL() else {
            throw MCPToolCallerError.scriptMissing
        }
        let python = resolvePython3Executable()
        guard FileManager.default.isExecutableFile(atPath: python) else {
            throw MCPToolCallerError.pythonNotFound
        }

        let payload: [String: Any] = [
            "mcp_file": mcpFilePath,
            "mcp": mcpServer,
            "tool": tool,
            "arguments": sanitizedJSONObject(arguments) as? [String: Any] ?? [:],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])

        return try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: python)
            proc.arguments = [scriptURL.path]

            let inPipe = Pipe()
            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardInput = inPipe
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            try proc.run()
            try inPipe.fileHandleForWriting.write(contentsOf: data)
            try inPipe.fileHandleForWriting.close()

            proc.waitUntilExit()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !outData.isEmpty else {
                if !errText.isEmpty {
                    throw MCPToolCallerError.invalidResponse(errText)
                }
                throw MCPToolCallerError.emptyOutput
            }

            let obj = try JSONSerialization.jsonObject(with: outData) as? [String: Any]
            guard let obj else {
                throw MCPToolCallerError.invalidResponse(String(data: outData, encoding: .utf8) ?? "")
            }
            if let err = obj["error"] as? String, !err.isEmpty, (obj["result"] as? String) == nil {
                throw MCPToolCallerError.invalidResponse(err)
            }
            if let r = obj["result"] as? String {
                return r
            }
            if obj["result"] is NSNull {
                throw MCPToolCallerError.invalidResponse((obj["error"] as? String) ?? "unknown")
            }
            throw MCPToolCallerError.invalidResponse(String(data: outData, encoding: .utf8) ?? "")
        }.value
    }

    private static func sanitizedJSONObject(_ value: Any) -> Any {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case let int as Int:
            return int
        case let double as Double:
            return double
        case let number as NSNumber:
            return number
        case is NSNull:
            return NSNull()
        case let dict as [String: Any]:
            var out: [String: Any] = [:]
            for (key, nested) in dict {
                out[key] = sanitizedJSONObject(nested)
            }
            return out
        case let array as [Any]:
            return array.map { sanitizedJSONObject($0) }
        default:
            return String(describing: value)
        }
    }

    private static func resolveScriptURL() -> URL? {
        let fm = FileManager.default
        if let raw = ProcessInfo.processInfo.environment[Self.environmentScriptKey], !raw.isEmpty {
            let u = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
            if fm.isReadableFile(atPath: u.path) { return u }
        }
        if let bundled = locateBundledMcpCallScript() {
            try? fm.createDirectory(at: cachedScriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: cachedScriptURL)
            try? fm.copyItem(at: bundled, to: cachedScriptURL)
            return bundled
        }
        if fm.isReadableFile(atPath: cachedScriptURL.path) {
            return cachedScriptURL
        }
        return nil
    }

    private static func locateBundledMcpCallScript() -> URL? {
        let fm = FileManager.default
        let filename = "mcp_call_tool.py"
        let bundles: [Bundle] = [Bundle.module, Bundle.main, Bundle(for: MCPToolCallerBundleAnchor.self)]
        for b in bundles {
            if let u = b.url(forResource: "mcp_call_tool", withExtension: "py"), fm.isReadableFile(atPath: u.path) {
                return u
            }
            if let r = b.resourceURL {
                let direct = r.appendingPathComponent(filename)
                if fm.isReadableFile(atPath: direct.path) { return direct }
                let alt = r.appendingPathComponent("Resources/\(filename)")
                if fm.isReadableFile(atPath: alt.path) { return alt }
            }
        }
        if let res = Bundle.main.resourceURL,
           let found = findNamedFile(filename, under: res, maxEntries: 1200) {
            return found
        }
        let fw = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        if fm.fileExists(atPath: fw.path),
           let found = findNamedFile(filename, under: fw, maxEntries: 2500) {
            return found
        }
        if let exe = Bundle.main.executableURL {
            var dir = exe.deletingLastPathComponent()
            for _ in 0..<10 {
                for leaf in ["GrizzyClawCore_GrizzyClawCore.bundle", "GrizzyClawCore.bundle"] {
                    let bURL = dir.appendingPathComponent(leaf)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: bURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
                    let cand = bURL.appendingPathComponent("Contents/Resources/\(filename)")
                    if fm.isReadableFile(atPath: cand.path) { return cand }
                    if let bu = Bundle(url: bURL), let u = bu.url(forResource: "mcp_call_tool", withExtension: "py"),
                       fm.isReadableFile(atPath: u.path) {
                        return u
                    }
                }
                if dir.path == "/" { break }
                dir = dir.deletingLastPathComponent()
            }
        }
        return nil
    }

    private static func findNamedFile(_ name: String, under root: URL, maxEntries: Int) -> URL? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        var n = 0
        for case let u as URL in en {
            n += 1
            if n > maxEntries { return nil }
            if u.lastPathComponent == name, fm.isReadableFile(atPath: u.path) { return u }
        }
        return nil
    }

    private static func resolvePython3Executable() -> String {
        let pipxCandidates = [
            "~/.local/pipx/venvs/mcp/bin/python",
            "~/.local/pipx/venvs/mcp/bin/python3",
        ].map { ($0 as NSString).expandingTildeInPath }
        for p in pipxCandidates where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        for p in ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
        where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        return "/usr/bin/python3"
    }
}

private final class MCPToolCallerBundleAnchor: NSObject {}
