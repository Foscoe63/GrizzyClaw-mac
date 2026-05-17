import Foundation

/// Tiny HTML → text / pseudo-markdown helper for `fetch_html` (no JS, no full Readability).
enum OsaurusHTMLReadabilityLite {
    static func extract(from html: String, extract: String) -> [String: Any] {
        let mode = extract.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if mode == "raw" {
            return [
                "title": title(from: html) ?? "",
                "markdown": html,
                "word_count": html.split(whereSeparator: { $0.isWhitespace }).count,
            ]
        }
        if mode == "text" {
            let plain = stripToPlainText(html)
            return [
                "title": title(from: html) ?? "",
                "markdown": plain,
                "word_count": plain.split(whereSeparator: { $0.isWhitespace }).count,
            ]
        }
        let plain = stripToPlainText(html)
        let md = pseudoMarkdown(title: title(from: html), body: plain)
        return [
            "title": title(from: html) ?? "",
            "byline": "",
            "excerpt": String(plain.prefix(280)),
            "lang": "",
            "markdown": md,
            "word_count": plain.split(whereSeparator: { $0.isWhitespace }).count,
        ]
    }

    private static func title(from html: String) -> String? {
        guard let open = html.range(of: "<title", options: .caseInsensitive) else { return nil }
        guard let gt = html[open.upperBound...].firstIndex(of: ">") else { return nil }
        let afterOpen = html.index(after: gt)
        guard let close = html[afterOpen...].range(of: "</title>", options: .caseInsensitive) else {
            return nil
        }
        let inner = String(html[afterOpen..<close.lowerBound])
        let t = inner
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func stripToPlainText(_ html: String) -> String {
        var s = html
        for pat in ["(?is)<script[^>]*>[\\s\\S]*?</script>", "(?is)<style[^>]*>[\\s\\S]*?</style>"] {
            s = s.replacingOccurrences(of: pat, with: " ", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "(?is)<br\\s*/?>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?is)</p>", with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func pseudoMarkdown(title: String?, body: String) -> String {
        var parts: [String] = []
        if let t = title, !t.isEmpty {
            parts.append("# \(t)\n")
        }
        parts.append(body)
        return parts.joined(separator: "\n")
    }
}
