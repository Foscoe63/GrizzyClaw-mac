import Foundation
import MCP

/// JSON / Foundation values ↔ `MCP.Value` and tool result text — mirrors Osaurus `MCPProviderTool` helpers.
public enum GrizzyMCPValueConversion {
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
}
