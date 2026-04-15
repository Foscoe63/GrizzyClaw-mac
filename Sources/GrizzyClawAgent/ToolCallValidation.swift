import Foundation
import GrizzyClawCore

public enum ToolCallValidation {
    public static func isKnownTool(
        server: String,
        tool: String,
        discovery: MCPToolsDiscoveryResult?
    ) -> Bool {
        guard let merged = discovery?.mergingPythonInternalTools() else { return true }
        return merged.servers[server]?.contains(where: { $0.name == tool }) == true
    }

    public static func invalidToolMessage(
        requestedServer: String,
        requestedTool: String,
        discovery: MCPToolsDiscoveryResult?
    ) -> String {
        let availableSummary: String = {
            guard let merged = discovery?.mergingPythonInternalTools() else { return "" }
            let serverNames = Array(merged.servers.keys.sorted().prefix(6))
            let examples: [String] = serverNames.compactMap { (server: String) -> String? in
                guard let first = merged.servers[server]?.first?.name else { return nil }
                return "\(server).\(first)"
            }
            guard !examples.isEmpty else { return "" }
            return " Available examples: " + examples.joined(separator: ", ") + "."
        }()

        return """
        **❌ Unknown tool `\(requestedServer).\(requestedTool)`.**
        Use only exact discovered MCP server/tool names for this session. For recurring reminders or background jobs, use `grizzyclaw.create_scheduled_task`, not calendar event tools or invented names like `mcp.events.events`.\(availableSummary)
        """
    }

    public static func lowContextMissingToolCallMessage(
        assistantText: String,
        messages: [ChatMessage],
        discovery: MCPToolsDiscoveryResult?
    ) -> String? {
        guard let server = lowContextNarrationServer(
            assistantText: assistantText,
            messages: messages,
            discovery: discovery
        ) else { return nil }

        return """
        [Tool error]
        **❌ Low Context MCP workflow was not executed for `\(server)`.**
        Do not explain the workflow or invent tool results. Your next reply must be only a TOOL_CALL for `get_tool_definitions` with a non-empty `names` array.
        Use a relevant wildcard such as `calendar_*`; if unsure, use `["*"]`.

        Example:
        TOOL_CALL = { "mcp": "\(server)", "tool": "get_tool_definitions", "arguments": { "names": ["*"] } }
        """
    }

    public static func lowContextFallbackToolCallJSON(
        assistantText: String,
        messages: [ChatMessage],
        discovery: MCPToolsDiscoveryResult?
    ) -> String? {
        guard let server = lowContextNarrationServer(
            assistantText: assistantText,
            messages: messages,
            discovery: discovery
        ) else { return nil }
        let wildcard = preferredLowContextWildcard(assistantText: assistantText, messages: messages)
        let namesJSON = wildcard.map { "\"\($0)\"" }.joined(separator: ", ")
        return """
        { "mcp": "\(server)", "tool": "get_tool_definitions", "arguments": { "names": [\(namesJSON)] } }
        """
    }

    private static func lowContextNarrationServer(
        assistantText: String,
        messages: [ChatMessage],
        discovery: MCPToolsDiscoveryResult?
    ) -> String? {
        guard let merged = discovery?.mergingPythonInternalTools() else { return nil }
        let lowContextServers = merged.servers.compactMap { server, tools -> String? in
            let names = Set(tools.map(\.name))
            return names.contains("get_tool_definitions") && names.contains("call_tool_by_name") ? server : nil
        }.sorted()
        guard !lowContextServers.isEmpty else { return nil }

        let assistantLower = assistantText.lowercased()
        let lastUserText = messages
            .reversed()
            .first(where: { $0.role == .user })?
            .content
            .lowercased() ?? ""

        let mentionedServer = lowContextServers.first(where: { server in
            let key = server.lowercased()
            return lastUserText.contains(key) || assistantLower.contains(key)
        }) ?? (lowContextServers.count == 1 ? lowContextServers[0] : nil)

        guard let server = mentionedServer else { return nil }

        let looksLikeWorkflowNarration =
            assistantLower.contains("get_tool_definitions")
            || assistantLower.contains("call_tool_by_name")
            || assistantLower.contains("according to instructions")
            || assistantLower.contains("the user wants to")

        let looksLikeHallucinatedSuccess =
            assistantLower.contains("i've retrieved")
            || assistantLower.contains("i have retrieved")
            || assistantLower.contains("here’s a concise summary")
            || assistantLower.contains("here's a concise summary")
            || assistantLower.contains("let me know which of these actions")

        guard looksLikeWorkflowNarration || looksLikeHallucinatedSuccess else { return nil }
        return server
    }

    private static func preferredLowContextWildcard(
        assistantText: String,
        messages: [ChatMessage]
    ) -> [String] {
        let lastUserText = messages
            .reversed()
            .first(where: { $0.role == .user })?
            .content
            .lowercased() ?? ""
        let combined = assistantText.lowercased() + "\n" + lastUserText
        if combined.contains("calendar") {
            return ["calendar_*"]
        }
        return ["*"]
    }
}
