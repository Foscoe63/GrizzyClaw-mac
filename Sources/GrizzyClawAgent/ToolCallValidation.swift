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
}
