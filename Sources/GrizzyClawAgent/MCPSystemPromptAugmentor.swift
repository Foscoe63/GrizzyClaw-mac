import Foundation
import GrizzyClawCore

/// Appends MCP tool instructions (Python `AgentCore` parity, compact) to the workspace system prompt.
public enum MCPSystemPromptAugmentor {
    /// When non-empty, append to system prompt so the model emits `TOOL_CALL = { "mcp", "tool", "arguments" }` like the Python app.
    public static func mcpSuffix(
        discovery: MCPToolsDiscoveryResult,
        toolEnabled: (String, String) -> Bool
    ) -> String {
        if discovery.servers.isEmpty { return "" }

        var lines: [String] = []
        lines.append("## MCP tools (native Mac chat)")
        lines.append(
            "Each line below is `server_id.tool_id`. In JSON, put **server_id** in \"mcp\" and **tool_id** in \"tool\" — they are different strings. "
                + "Do not put the server_id (left of the dot) in \"tool\"; do not invent tool names from memory."
        )
        lines.append(
            "When you need external data or actions, output exactly: TOOL_CALL = { \"mcp\": \"server_name\", \"tool\": \"tool_name\", \"arguments\": { ... } } "
                + "(plain text, no markdown fences around the JSON). "
                + "Do not prepend commentary, routing, or `to=` lines — only that TOOL_CALL line (or the same JSON object alone). "
                + "Use only server and tool names listed below that are enabled for this session (exact names, no extra brackets or ids). "
                + "Fill \"arguments\" with what the tool needs (e.g. search query). "
                + "After tool results appear in the next user message, continue the answer; do not repeat the same TOOL_CALL."
        )
        lines.append(
            "If the user asks to create a reminder, recurring job, or scheduler entry, prefer the built-in scheduler tool instead of writing sample code."
        )
        lines.append(
            "Do not invent server names like `mcp.events` or tool names like `events`; use only exact discovered names from the list below."
        )

        for srv in discovery.servers.keys.sorted() {
            guard let tools = discovery.servers[srv] else { continue }
            for t in tools {
                guard toolEnabled(srv, t.name) else { continue }
                let short = t.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let desc = short.count > 120 ? String(short.prefix(120)) + "…" : short
                lines.append("- \(srv).\(t.name): \(desc)")
                lines.append("  Example: TOOL_CALL = { \"mcp\": \"\(srv)\", \"tool\": \"\(t.name)\", \"arguments\": {} }")
                if srv == "grizzyclaw", t.name == "create_scheduled_task" {
                    lines.append(
                        "  Required arguments: { \"name\": string, \"cron\": string, \"message\": string, \"mcp_post_action\": optional object }"
                    )
                    lines.append(
                        "  Scheduler example: TOOL_CALL = { \"mcp\": \"grizzyclaw\", \"tool\": \"create_scheduled_task\", \"arguments\": { \"name\": \"Morning Iran conflict news search\", \"cron\": \"0 6 * * *\", \"message\": \"Search the internet for the latest news on the Iran conflict\" } }"
                    )
                }
            }
        }

        if lines.count <= 3 {
            return ""
        }
        return lines.joined(separator: "\n")
    }
}
