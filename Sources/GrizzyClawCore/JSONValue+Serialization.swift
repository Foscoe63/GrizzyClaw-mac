import Foundation

extension JSONValue {
    /// Decodes from a JSON-compatible object tree (e.g. `[String: Any]` from `JSONSerialization`).
    public static func decode(fromJSONObject root: Any) throws -> JSONValue {
        let data = try JSONSerialization.data(withJSONObject: root, options: [])
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Converts to types suitable for `JSONSerialization` (uses `NSNull` for `.null`).
    public func jsonSerializationValue() throws -> Any {
        switch self {
        case .object(let d):
            var out: [String: Any] = [:]
            for (k, v) in d {
                out[k] = try v.jsonSerializationValue()
            }
            return out
        case .array(let arr):
            return try arr.map { try $0.jsonSerializationValue() }
        case .string(let s):
            return s
        case .int(let i):
            return i
        case .double(let d):
            return d
        case .bool(let b):
            return b
        case .null:
            return NSNull()
        }
    }
}
