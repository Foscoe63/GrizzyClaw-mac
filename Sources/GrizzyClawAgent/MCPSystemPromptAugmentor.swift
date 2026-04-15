import Foundation
import GrizzyClawCore

/// Appends MCP tool instructions (Python `AgentCore` parity, compact) to the workspace system prompt.
public enum MCPSystemPromptAugmentor {
    /// When non-empty, append to system prompt so the model emits `TOOL_CALL = { "mcp", "tool", "arguments" }` like the Python app.
    public static func mcpSuffix(
        discovery: MCPToolsDiscoveryResult,
        includeSchemas: Bool = false,
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

        let lowContextServers = discovery.servers.keys.sorted().filter { srv in
            guard let tools = discovery.servers[srv] else { return false }
            return hasLowContextMetaTools(server: srv, tools: tools, toolEnabled: toolEnabled)
        }
        if !lowContextServers.isEmpty {
            lines.append(
                "If a server exposes both `get_tool_definitions` and `call_tool_by_name`, it is in Low Context Mode. "
                    + "For those servers, do not guess direct tool names. First call `get_tool_definitions`, then call `call_tool_by_name` using the exact discovered tool name and required arguments."
            )
            lines.append(
                "When the user asks to use a Low Context server, do not explain this workflow in prose. "
                    + "Your next assistant turn must start with the `TOOL_CALL` for `get_tool_definitions`."
            )
            lines.append(
                "Never send `get_tool_definitions` with an empty `names` array. "
                    + "Use a relevant wildcard like `calendar_*`, or if you truly need broad discovery, use `[\"*\"]`."
            )
            for srv in lowContextServers {
                lines.append(
                    "Low Context workflow for \(srv): first `TOOL_CALL = { \"mcp\": \"\(srv)\", \"tool\": \"get_tool_definitions\", \"arguments\": { \"names\": [\"calendar_*\"] } }`, then use the returned example/schema to call `call_tool_by_name`."
                )
                lines.append(
                    "If the user asks \(srv) to list calendars, your first reply should be that exact `get_tool_definitions` TOOL_CALL, not a description of what you plan to do."
                )
            }
        }

        for srv in discovery.servers.keys.sorted() {
            guard let tools = discovery.servers[srv] else { continue }
            for t in tools {
                guard toolEnabled(srv, t.name) else { continue }
                let short = t.description.trimmingCharacters(in: .whitespacesAndNewlines)
                let desc = short.count > 120 ? String(short.prefix(120)) + "…" : short
                lines.append("- \(srv).\(t.name): \(desc)")
                lines.append("  Example: TOOL_CALL = { \"mcp\": \"\(srv)\", \"tool\": \"\(t.name)\", \"arguments\": {} }")
                if includeSchemas {
                    for schemaLine in schemaGuidanceLines(for: t) {
                        lines.append("  \(schemaLine)")
                    }
                }
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

    private static func schemaGuidanceLines(for tool: MCPToolDescriptor) -> [String] {
        guard let schema = tool.inputSchema else { return [] }
        guard case .object(let root) = schema, !root.isEmpty else { return [] }

        var lines: [String] = []
        if let summary = schemaObjectSignature(schema) {
            lines.append("Arguments shape: \(summary)")
        }

        let required = requiredPropertyNames(schema)
        if !required.isEmpty {
            lines.append("Required keys: \(required.joined(separator: ", "))")
        }

        if let example = exampleArgumentsJSONString(schema: schema) {
            lines.append("Example arguments: \(example)")
        }
        return lines
    }

    private static func hasLowContextMetaTools(
        server: String,
        tools: [MCPToolDescriptor],
        toolEnabled: (String, String) -> Bool
    ) -> Bool {
        let names = Set(tools.map(\.name))
        return names.contains("get_tool_definitions")
            && names.contains("call_tool_by_name")
            && toolEnabled(server, "get_tool_definitions")
            && toolEnabled(server, "call_tool_by_name")
    }

    private static func schemaObjectSignature(_ schema: JSONValue) -> String? {
        guard let properties = objectValue(schema, forKey: "properties"), !properties.isEmpty else {
            let typeName = schema.string(forKey: "type")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return typeName.isEmpty ? nil : typeName
        }

        let required = Set(requiredPropertyNames(schema))
        let orderedKeys = properties.keys.sorted()
        let shownKeys = Array(orderedKeys.prefix(6))
        let entries = shownKeys.map { key -> String in
            let typeDesc = compactTypeDescription(properties[key] ?? .null)
            let requirement = required.contains(key) ? "required" : "optional"
            return "\(key): \(typeDesc) (\(requirement))"
        }
        let suffix = orderedKeys.count > shownKeys.count ? ", ..." : ""
        return "{ " + entries.joined(separator: ", ") + suffix + " }"
    }

    private static func compactTypeDescription(_ schema: JSONValue) -> String {
        if let enumValues = stringEnumValues(schema), !enumValues.isEmpty {
            let shown = enumValues.prefix(4).map { "\"\($0)\"" }.joined(separator: " | ")
            return enumValues.count > 4 ? "enum[\(shown) | ...]" : "enum[\(shown)]"
        }
        if let constSchema = schemaObjectValue(schema, forKey: "const"),
           let constValue = scalarJSONString(constSchema) {
            return "const \(constValue)"
        }
        let typeName = normalizedTypeName(schema)
        if typeName == "array" {
            let itemDesc = schemaObjectValue(schema, forKey: "items").map(compactTypeDescription) ?? "any"
            return "array<\(itemDesc)>"
        }
        return typeName
    }

    private static func normalizedTypeName(_ schema: JSONValue) -> String {
        if let typeName = schema.string(forKey: "type")?.trimmingCharacters(in: .whitespacesAndNewlines), !typeName.isEmpty {
            return typeName
        }
        if case .object(let root) = schema {
            if root["properties"] != nil { return "object" }
            if root["enum"] != nil { return "enum" }
        }
        return "any"
    }

    private static func requiredPropertyNames(_ schema: JSONValue) -> [String] {
        guard let required = arrayValue(schema, forKey: "required") else { return [] }
        return required.compactMap {
            guard case .string(let value) = $0 else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func stringEnumValues(_ schema: JSONValue) -> [String]? {
        guard let enumValues = arrayValue(schema, forKey: "enum") else { return nil }
        let strings = enumValues.compactMap { (item: JSONValue) -> String? in
            guard case .string(let value) = item else { return nil }
            return value
        }
        return strings.isEmpty ? nil : strings
    }

    private static func exampleArgumentsJSONString(schema: JSONValue) -> String? {
        guard let properties = objectValue(schema, forKey: "properties"), !properties.isEmpty else { return nil }

        let required = requiredPropertyNames(schema)
        let orderedKeys: [String]
        if required.isEmpty {
            orderedKeys = Array(properties.keys.sorted().prefix(2))
        } else {
            orderedKeys = Array(required.prefix(6))
        }
        guard !orderedKeys.isEmpty else { return nil }

        var example: [String: JSONValue] = [:]
        for key in orderedKeys {
            guard let propertySchema = properties[key] else { continue }
            example[key] = exampleValue(for: propertySchema)
        }
        guard !example.isEmpty else { return nil }
        return jsonString(.object(example))
    }

    private static func exampleValue(for schema: JSONValue) -> JSONValue {
        if let constValue = schemaObjectValue(schema, forKey: "const") {
            return constValue
        }
        if let enumValues = arrayValue(schema, forKey: "enum"), let first = enumValues.first {
            return first
        }
        if let defaultValue = schemaObjectValue(schema, forKey: "default") {
            return defaultValue
        }

        switch normalizedTypeName(schema) {
        case "boolean":
            return .bool(false)
        case "integer":
            return .int(0)
        case "number":
            return .double(0)
        case "array":
            return .array([])
        case "object":
            return .object([:])
        case "null":
            return .null
        default:
            return .string("<string>")
        }
    }

    private static func jsonString(_ value: JSONValue) -> String? {
        do {
            let raw = try value.jsonSerializationValue()
            let data = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys])
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func scalarJSONString(_ value: JSONValue) -> String? {
        switch value {
        case .string(let string):
            return "\"\(string)\""
        case .int(let int):
            return String(int)
        case .double(let double):
            return String(double)
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null:
            return "null"
        default:
            return jsonString(value)
        }
    }

    private static func objectValue(_ json: JSONValue, forKey key: String) -> [String: JSONValue]? {
        guard case .object(let root) = json,
              let value = root[key],
              case .object(let object) = value
        else {
            return nil
        }
        return object
    }

    private static func schemaObjectValue(_ json: JSONValue, forKey key: String) -> JSONValue? {
        guard case .object(let root) = json else { return nil }
        return root[key]
    }

    private static func arrayValue(_ json: JSONValue, forKey key: String) -> [JSONValue]? {
        guard case .object(let root) = json,
              let value = root[key],
              case .array(let array) = value
        else {
            return nil
        }
        return array
    }
}
