import Foundation

/// Coercion helpers aligned with Osaurus `ArgumentCoercion` for bundled tool parity.
public enum OsaurusArgumentCoercion {
    public static func stringArray(_ value: Any?) -> [String]? {
        if let arr = value as? [String] { return arr }
        if let anyArr = value as? [Any] {
            let mapped = anyArr.compactMap { $0 as? String }
            return mapped.isEmpty ? nil : mapped
        }
        if let str = value as? String {
            if let data = str.data(using: .utf8),
                let parsed = try? JSONSerialization.jsonObject(with: data) as? [String]
            {
                return parsed
            }
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return [trimmed] }
        }
        return nil
    }

    public static func bool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let s = value as? String {
            switch s.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }
}

// MARK: - clarify options (Osaurus `ClarifyTool`)

public enum OsaurusClarifyOptionsRules {
    public static let maxOptions = 6
    public static let maxOptionLength = 80

    /// Trim, drop empties, dedupe (case-insensitive, keeping first casing). Matches Osaurus `ClarifyTool.normalizeOptions`.
    public static func normalizeOptions(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for opt in raw {
            let trimmed = opt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                out.append(trimmed)
            }
        }
        return out
    }
}

// MARK: - complete summary gate (Osaurus `CompleteTool.validate`)

public enum OsaurusCompleteSummaryValidator {
    /// Returns nil when acceptable, otherwise a human-readable rejection reason.
    public static func validationMessage(for summary: String) -> String? {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 30 {
            return
                "`summary` is too short (\(trimmed.count) chars). Describe both what you did and how you verified it — about 30 characters of meaningful prose at minimum."
        }
        let normalised = trimmed.lowercased()
        let placeholders: Set<String> = [
            "done.", "done", "complete.", "complete", "completed.", "completed",
            "ok.", "ok", "okay.", "okay", "looks good.", "looks good",
            "all good.", "all good", "fine.", "fine", "finished.", "finished",
        ]
        if placeholders.contains(normalised) {
            return
                "`summary` looks like a placeholder. Describe the concrete work and the concrete verification step (a command, a file, a URL)."
        }
        return nil
    }
}
