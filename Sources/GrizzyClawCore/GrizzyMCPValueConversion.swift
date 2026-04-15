import Foundation
import MCP

/// JSON / Foundation values ↔ `MCP.Value` and tool result text — mirrors Osaurus `MCPProviderTool` helpers.
public enum GrizzyMCPValueConversion {
    public struct ResourceLink: Sendable, Equatable {
        public let uri: String
        public let name: String
        public let title: String?
        public let description: String?
        public let mimeType: String?

        public init(
            uri: String,
            name: String,
            title: String? = nil,
            description: String? = nil,
            mimeType: String? = nil
        ) {
            self.uri = uri
            self.name = name
            self.title = title
            self.description = description
            self.mimeType = mimeType
        }
    }

    public struct ActionCall: Sendable, Equatable {
        public let tool: String
        public let arguments: [String: JSONValue]

        public init(tool: String, arguments: [String: JSONValue]) {
            self.tool = tool
            self.arguments = arguments
        }

        public func jsonObjectArguments() -> [String: Any] {
            var out: [String: Any] = [:]
            for (key, value) in arguments {
                out[key] = (try? value.jsonSerializationValue()) ?? NSNull()
            }
            return out
        }

        /// True when arguments still contain template tokens like `<value>` (models often emit these for low-context follow-ups).
        public func hasPlaceholderArguments() -> Bool {
            func check(_ v: JSONValue) -> Bool {
                switch v {
                case .string(let s):
                    return Self.isPlaceholderTemplateString(s)
                case .array(let items):
                    return items.contains(where: check)
                case .object(let obj):
                    return obj.values.contains(where: check)
                default:
                    return false
                }
            }
            return arguments.values.contains(where: check)
        }

        private static func isPlaceholderTemplateString(_ raw: String) -> Bool {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { return false }
            let lower = s.lowercased()
            if lower == "<value>" { return true }
            if s.count >= 3, s.first == "<", s.last == ">" { return true }
            return false
        }
    }

    public struct NormalizedToolResult: Sendable, Equatable {
        public let textBlocks: [String]
        public let structuredItems: [JSONValue]
        public let resourceLinks: [ResourceLink]

        public init(
            textBlocks: [String] = [],
            structuredItems: [JSONValue] = [],
            resourceLinks: [ResourceLink] = []
        ) {
            self.textBlocks = textBlocks
            self.structuredItems = structuredItems
            self.resourceLinks = resourceLinks
        }
    }

    public static func mcpValues(from arguments: [String: Any]) throws -> [String: Value] {
        var result: [String: Value] = [:]
        for (key, value) in arguments {
            result[key] = try convertToMCPValue(value)
        }
        return result
    }

    private static func convertToMCPValue(_ value: Any) throws -> Value {
        switch value {
        case let stringValue as String:
            return .string(stringValue)
        case let boolValue as Bool:
            return .bool(boolValue)
        case let intValue as Int:
            return .int(intValue)
        case let doubleValue as Double:
            return .double(doubleValue)
        case let arrayValue as [Any]:
            let mcpArray = try arrayValue.map { try convertToMCPValue($0) }
            return .array(mcpArray)
        case let dictValue as [String: Any]:
            var mcpObject: [String: Value] = [:]
            for (k, v) in dictValue {
                mcpObject[k] = try convertToMCPValue(v)
            }
            return .object(mcpObject)
        case is NSNull:
            return .null
        default:
            if let jsonData = try? JSONSerialization.data(withJSONObject: value),
               let jsonString = String(data: jsonData, encoding: .utf8)
            {
                return .string(jsonString)
            }
            throw GrizzyMCPNativeError.unsupportedArgumentType(String(describing: type(of: value)))
        }
    }

    public static func string(from content: [Tool.Content]) -> String {
        var results: [[String: Any]] = []
        for item in content {
            switch item {
            case .text(let text, _, _):
                results.append(["type": "text", "content": text])
            case .image(let data, let mimeType, _, _):
                results.append([
                    "type": "image",
                    "data": data,
                    "mimeType": mimeType,
                ])
            case .audio(let data, let mimeType, _, _):
                results.append([
                    "type": "audio",
                    "data": data,
                    "mimeType": mimeType,
                ])
            case .resource(let resource, _, _):
                results.append([
                    "type": "resource",
                    "resource": String(describing: resource),
                ])
            case .resourceLink(let uri, let name, let title, let description, let mimeType, _):
                var row: [String: Any] = [
                    "type": "resource_link",
                    "uri": uri,
                    "name": name,
                ]
                if let title { row["title"] = title }
                if let description { row["description"] = description }
                if let mimeType { row["mimeType"] = mimeType }
                results.append(row)
            }
        }
        if results.count == 1, let content = results[0]["content"] as? String {
            return content
        }
        if let jsonData = try? JSONSerialization.data(withJSONObject: results),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            return jsonString
        }
        return "[]"
    }

    public static func normalize(rawToolResult: String) -> NormalizedToolResult {
        let trimmed = rawToolResult.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return NormalizedToolResult() }

        if let value = decodeJSONValue(from: trimmed) {
            return normalize(jsonValue: value)
        }
        return NormalizedToolResult(textBlocks: [trimmed])
    }

    public static func returnedActionCalls(from rawToolResult: String) -> [ActionCall] {
        let normalized = normalize(rawToolResult: rawToolResult)
        return normalized.structuredItems.flatMap(extractActionCalls)
    }

    private static func normalize(jsonValue: JSONValue) -> NormalizedToolResult {
        switch jsonValue {
        case .array(let items):
            if let envelope = normalizeEnvelopeArray(items) {
                return envelope
            }
            return NormalizedToolResult(structuredItems: [jsonValue])
        case .object:
            return NormalizedToolResult(structuredItems: [jsonValue])
        case .string(let text):
            return NormalizedToolResult(textBlocks: [text.trimmingCharacters(in: .whitespacesAndNewlines)])
        case .int, .double, .bool, .null:
            return NormalizedToolResult(textBlocks: [string(from: jsonValue)])
        }
    }

    private static func normalizeEnvelopeArray(_ items: [JSONValue]) -> NormalizedToolResult? {
        guard !items.isEmpty else { return NormalizedToolResult() }
        var textBlocks: [String] = []
        var structuredItems: [JSONValue] = []
        var resourceLinks: [ResourceLink] = []
        var recognizedAny = false

        for item in items {
            guard case .object(let row) = item,
                  case .string(let type)? = row["type"]
            else {
                return nil
            }

            recognizedAny = true
            switch type {
            case "text":
                if case .string(let content)? = row["content"] {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    if let nested = decodeJSONValue(from: trimmed) {
                        let normalized = normalize(jsonValue: nested)
                        textBlocks.append(contentsOf: normalized.textBlocks)
                        structuredItems.append(contentsOf: normalized.structuredItems)
                        resourceLinks.append(contentsOf: normalized.resourceLinks)
                    } else {
                        textBlocks.append(trimmed)
                    }
                }
            case "resource_link":
                guard case .string(let uri)? = row["uri"],
                      case .string(let name)? = row["name"]
                else { continue }
                let title = stringField(row["title"])
                let description = stringField(row["description"])
                let mimeType = stringField(row["mimeType"])
                resourceLinks.append(
                    ResourceLink(
                        uri: uri,
                        name: name,
                        title: title,
                        description: description,
                        mimeType: mimeType
                    )
                )
            case "image", "audio", "resource":
                continue
            default:
                return nil
            }
        }

        guard recognizedAny else { return nil }
        return NormalizedToolResult(
            textBlocks: textBlocks.filter { !$0.isEmpty },
            structuredItems: structuredItems,
            resourceLinks: resourceLinks
        )
    }

    private static func decodeJSONValue(from raw: String) -> JSONValue? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return nil
        }
        return try? JSONValue.decode(fromJSONObject: object)
    }

    private static func extractActionCalls(from jsonValue: JSONValue) -> [ActionCall] {
        guard case .object(let object) = jsonValue,
              case .array(let actions)? = object["actions"]
        else {
            return []
        }

        return actions.compactMap { action in
            guard case .object(let actionObject) = action,
                  case .object(let toolCall)? = actionObject["tool_call"],
                  case .string(let tool)? = toolCall["tool"]
            else {
                return nil
            }
            let arguments: [String: JSONValue]
            if case .object(let args)? = toolCall["arguments"] {
                arguments = args
            } else {
                arguments = [:]
            }
            return ActionCall(tool: tool, arguments: arguments)
        }
    }

    private static func stringField(_ value: JSONValue?) -> String? {
        guard case .string(let text)? = value else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func string(from value: JSONValue) -> String {
        switch value {
        case .string(let text): return text
        case .int(let int): return String(int)
        case .double(let double): return String(double)
        case .bool(let bool): return bool ? "true" : "false"
        case .null: return "null"
        case .object, .array:
            if let object = try? value.jsonSerializationValue(),
               let data = try? JSONSerialization.data(withJSONObject: object),
               let string = String(data: data, encoding: .utf8)
            {
                return string
            }
            return ""
        }
    }
}
