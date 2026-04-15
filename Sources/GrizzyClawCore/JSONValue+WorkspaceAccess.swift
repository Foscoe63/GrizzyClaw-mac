import Foundation

extension JSONValue {
    public func contains(key: String) -> Bool {
        guard case .object(let d) = self else { return false }
        return d[key] != nil
    }

    /// Returns keys when `.object`, else empty.
    public var objectKeys: [String] {
        if case .object(let d) = self { return Array(d.keys) }
        return []
    }

    public func string(forKey key: String) -> String? {
        guard case .object(let d) = self, let v = d[key] else { return nil }
        switch v {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let dbl): return String(dbl)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    public func double(forKey key: String) -> Double? {
        guard case .object(let d) = self, let v = d[key] else { return nil }
        switch v {
        case .double(let d): return d
        case .int(let i): return Double(i)
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    public func int(forKey key: String) -> Int? {
        guard case .object(let d) = self, let v = d[key] else { return nil }
        switch v {
        case .int(let i): return i
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    public func bool(forKey key: String) -> Bool? {
        guard case .object(let d) = self, let v = d[key] else { return nil }
        switch v {
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .string(let s):
            let t = s.lowercased()
            if ["1", "true", "yes"].contains(t) { return true }
            if ["0", "false", "no"].contains(t) { return false }
            return nil
        default: return nil
        }
    }

    /// `enabled_skills` string list (Python `WorkspaceConfig.enabled_skills`).
    public func stringArray(forKey key: String) -> [String] {
        guard case .object(let d) = self, let v = d[key] else { return [] }
        guard case .array(let arr) = v else { return [] }
        return arr.compactMap { item in
            if case .string(let s) = item { return s }
            return nil
        }
    }

    /// `enabled_skills` with override detection support: missing/`null` means inherit, array means explicit override.
    public func stringArrayIfPresent(forKey key: String) -> [String]? {
        guard case .object(let d) = self, let v = d[key] else { return nil }
        if case .null = v { return nil }
        guard case .array(let arr) = v else { return nil }
        return arr.compactMap { item in
            if case .string(let s) = item { return s }
            return nil
        }
    }

    /// `mcp_tool_allowlist`: `null` or `[[server, tool], ...]` (Python tuple list).
    public func mcpToolAllowlistPairs(forKey key: String = "mcp_tool_allowlist") -> [(String, String)]? {
        guard case .object(let d) = self, let v = d[key] else { return nil }
        switch v {
        case .null:
            return nil
        case .array(let rows):
            var out: [(String, String)] = []
            for row in rows {
                guard case .array(let pair) = row, pair.count >= 2 else { continue }
                guard case .string(let a) = pair[0], case .string(let b) = pair[1] else { continue }
                if !a.isEmpty, !b.isEmpty { out.append((a, b)) }
            }
            return out
        default:
            return nil
        }
    }
}
