import Foundation

/// Mirrors Python `grizzyclaw.config._normalize_skill_name` closely enough for marketplace de-duplication and row keys.
public enum SkillNameNormalizer {
    public static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return s }
        s = s.precomposedStringWithCanonicalMapping
        // Dash-like → hyphen
        let dashPattern = try! NSRegularExpression(
            pattern: "[\\-\\u2010\\u2011\\u2012\\u2013\\u2014\\u2015\\u2212\\uFE58\\uFE63\\uFF0D]+",
            options: []
        )
        let r = NSRange(s.startIndex..<s.endIndex, in: s)
        s = dashPattern.stringByReplacingMatches(in: s, options: [], range: r, withTemplate: "-")
        s = s.replacingOccurrences(of: "-", with: " <HYPHEN> ")
        let symPattern = try! NSRegularExpression(pattern: "[^\\w\\s]", options: [])
        let r2 = NSRange(s.startIndex..<s.endIndex, in: s)
        s = symPattern.stringByReplacingMatches(in: s, options: [], range: r2, withTemplate: " ")
        s = s.replacingOccurrences(of: "<HYPHEN>", with: "-")
        let ws = try! NSRegularExpression(pattern: "\\s+", options: [])
        let r3 = NSRange(s.startIndex..<s.endIndex, in: s)
        s = ws.stringByReplacingMatches(in: s, options: [], range: r3, withTemplate: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
