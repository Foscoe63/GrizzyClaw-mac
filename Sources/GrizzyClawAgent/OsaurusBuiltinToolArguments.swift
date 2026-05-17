import Foundation

/// Loose argument parsing shared by bundled native tools (models vary key names).
enum OsaurusBuiltinToolArguments {
    static func string(from args: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let s = args[k] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
            if let n = args[k] as? NSNumber {
                return n.stringValue
            }
        }
        return nil
    }

    static func int(from args: [String: Any], keys: [String], default def: Int) -> Int {
        for k in keys {
            if let n = args[k] as? NSNumber {
                return n.intValue
            }
            if let s = args[k] as? String, let v = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return v
            }
        }
        return def
    }

    static func dictionary(from args: [String: Any], keys: [String]) -> [String: String]? {
        for k in keys {
            guard let raw = args[k] else { continue }
            if let d = raw as? [String: String] { return d }
            if let d = raw as? [String: Any] {
                var out: [String: String] = [:]
                for (kk, vv) in d {
                    if let s = vv as? String {
                        out[kk] = s
                    } else if let n = vv as? NSNumber {
                        out[kk] = n.stringValue
                    }
                }
                if !out.isEmpty { return out }
            }
        }
        return nil
    }
}
