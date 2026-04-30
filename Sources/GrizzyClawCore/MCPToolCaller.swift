import Foundation

/// Invokes MCP tools via the native Swift runtime (`GrizzyMCPNativeRuntime`).
/// The legacy Python fallback (`mcp_call_tool.py`) has been removed — the app no longer
/// depends on a Python interpreter or the `grizzyclaw` CLI.
public enum MCPToolCallerError: Error, LocalizedError {
    case nativeCallFailed(String)

    public var errorDescription: String? {
        switch self {
        case .nativeCallFailed(let s):
            return "MCP tool call failed: \(s)"
        }
    }
}

public enum MCPToolCaller {
    /// Invoke one MCP tool; returns the result text.
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

        do {
            return try await GrizzyMCPNativeRuntime.shared.callTool(
                mcpServersFile: path,
                server: mcpServer,
                tool: tool,
                arguments: normalizedArguments
            )
        } catch {
            GrizzyClawLog.error("MCP native tool call failed: \(error.localizedDescription)")
            throw MCPToolCallerError.nativeCallFailed(error.localizedDescription)
        }
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
}
