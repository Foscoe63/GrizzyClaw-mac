import Foundation

/// Loose JSON for nested `config` blobs (Python `WorkspaceConfig` dict).
public indirect enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var arr: [JSONValue] = []
            while !unkeyed.isAtEnd {
                arr.append(try unkeyed.decode(JSONValue.self))
            }
            self = .array(arr)
            return
        }
        if let keyed = try? decoder.container(keyedBy: DynamicCodingKeys.self) {
            var dict: [String: JSONValue] = [:]
            for key in keyed.allKeys {
                dict[key.stringValue] = try keyed.decode(JSONValue.self, forKey: key)
            }
            self = .object(dict)
            return
        }
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
            return
        }
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
            return
        }
        if let s = try? c.decode(String.self) {
            self = .string(s)
            return
        }
        if let i = try? c.decode(Int.self) {
            self = .int(i)
            return
        }
        if let d = try? c.decode(Double.self) {
            self = .double(d)
            return
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSONValue"))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let dict):
            var keyed = encoder.container(keyedBy: DynamicCodingKeys.self)
            for (k, v) in dict {
                let key = DynamicCodingKeys(stringValue: k)!
                try keyed.encode(v, forKey: key)
            }
        case .array(let arr):
            var unkeyed = encoder.unkeyedContainer()
            for v in arr {
                try unkeyed.encode(v)
            }
        case .string(let s):
            var c = encoder.singleValueContainer()
            try c.encode(s)
        case .int(let i):
            var c = encoder.singleValueContainer()
            try c.encode(i)
        case .double(let d):
            var c = encoder.singleValueContainer()
            try c.encode(d)
        case .bool(let b):
            var c = encoder.singleValueContainer()
            try c.encode(b)
        case .null:
            var c = encoder.singleValueContainer()
            try c.encodeNil()
        }
    }

    private struct DynamicCodingKeys: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
}
