import Foundation

/// Mirrors `grizzyclaw/agent/command_parsers.py` `find_json_blocks` for `TOOL_CALL` and balanced `{…}` extraction.
public enum ToolCallCommandParsing {
    /// Local models often omit `TOOL_CALL =` and emit `{"mcp":...}` (sometimes after junk like `commentary to=…json`).
    private static let looseMcpJsonStart = try! NSRegularExpression(
        pattern: #"\{\s*"mcp"\s*:"#,
        options: [.caseInsensitive]
    )

    /// Bundled **MLX** (and some other local) models often emit routing in the prefix and **only** argument JSON: `commentary to=ddg-search[id=x].search json{"query":"…"}`.
    private static let commentaryRoutedArgs = try! NSRegularExpression(
        pattern: #"(?i)commentary\s+to=([a-zA-Z0-9_.-]+)(?:\[[^\]]*\])?\.([a-zA-Z0-9_.-]+)\s+(?:(?:json|arguments)\s*)?\{"#,
        options: []
    )

    /// Same intent as ``commentaryRoutedArgs``, but some models use ` tool=search ` instead of `.search` before `{…}`.
    private static let commentaryRoutedToolEqualsArgs = try! NSRegularExpression(
        pattern: #"(?i)commentary\s+to=([a-zA-Z0-9_.-]+)(?:\[[^\]]*\])?\s+tool=([a-zA-Z0-9_.-]+)\s+(?:(?:json|arguments)\s*)?\{"#,
        options: []
    )

    /// Some models emit only the server route and args object: `commentary to=ddg-search json{"query":"…"}`.
    private static let commentaryRoutedServerOnlyArgs = try! NSRegularExpression(
        pattern: #"(?i)commentary\s+to=([a-zA-Z0-9_.-]+)(?:\[[^\]]*\])?\s+(?:(?:json|arguments)\s*)?\{"#,
        options: []
    )

    /// Returns JSON object bodies for each `TOOL_CALL = {…}` **plus** any standalone `{"mcp":…,"tool":…}` objects (common with small local models, including MLX).
    public static func findToolCallJsonObjects(in text: String) -> [String] {
        var blocks: [String] = []
        var seen = Set<String>()
        for explicit in findExplicitToolCallJsonObjects(in: text) {
            if seen.insert(explicit).inserted {
                blocks.append(explicit)
            }
        }
        for loose in findLooseMcpToolJsonObjects(in: text) {
            if seen.insert(loose).inserted {
                blocks.append(loose)
            }
        }
        for syn in findCommentaryRoutedSyntheticJsonObjects(in: text) {
            if seen.insert(syn).inserted {
                blocks.append(syn)
            }
        }
        return blocks
    }

    private static let commentaryRoutedPatterns: [NSRegularExpression] = [
        commentaryRoutedArgs,
        commentaryRoutedToolEqualsArgs,
    ]

    /// Strips `[id=…]` / bracket suffixes models hallucinate after MCP server names (e.g. `ddg-search[id=8F800K]`).
    public static func normalizeMcpIdentifier(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = t.firstIndex(of: "[") else { return t }
        return String(t[..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns JSON object bodies (inside `{`…`}`) for each `TOOL_CALL = {` occurrence.
    private static func findExplicitToolCallJsonObjects(in text: String) -> [String] {
        let prefix = "TOOL_CALL"
        var blocks: [String] = []
        var searchRange = text.startIndex..<text.endIndex
        while let r = text.range(of: prefix, options: .caseInsensitive, range: searchRange, locale: nil) {
            let afterPrefix = text.index(r.upperBound, offsetBy: 0, limitedBy: text.endIndex) ?? text.endIndex
            guard let eqRange = text.range(of: "=", range: afterPrefix..<text.endIndex) else {
                searchRange = text.index(after: r.upperBound)..<text.endIndex
                continue
            }
            var i = text.index(after: eqRange.upperBound)
            while i < text.endIndex, text[i].isWhitespace { text.formIndex(after: &i) }
            if text[i..<text.endIndex].hasPrefix("```") {
                if let fence = text[i...].firstIndex(of: "\n") {
                    i = text.index(after: fence)
                }
            }
            while i < text.endIndex, text[i].isWhitespace { text.formIndex(after: &i) }
            guard i < text.endIndex, text[i] == "{" else {
                searchRange = text.index(after: r.upperBound)..<text.endIndex
                continue
            }
            if let pair = extractBalancedBrace(text, start: i) {
                blocks.append(String(text[pair]))
            }
            searchRange = text.index(after: r.upperBound)..<text.endIndex
        }
        return blocks
    }

    /// Builds `{"mcp","tool","arguments"}` from `commentary to=server[id].tool json{ ... }` or `commentary to=server[id] tool=tool json{ ... }` when the model omits mcp/tool keys.
    private static func findCommentaryRoutedSyntheticJsonObjects(in text: String) -> [String] {
        var out: [String] = []
        for pattern in commentaryRoutedPatterns {
            appendCommentarySyntheticJsonObjects(pattern: pattern, text: text, into: &out)
        }
        appendCommentaryServerOnlySyntheticJsonObjects(text: text, into: &out)
        return out
    }

    private static func appendCommentarySyntheticJsonObjects(
        pattern: NSRegularExpression,
        text: String,
        into out: inout [String]
    ) {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        pattern.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 3,
                  let mcpR = Range(match.range(at: 1), in: text),
                  let toolR = Range(match.range(at: 2), in: text),
                  let fullR = Range(match.range(at: 0), in: text)
            else { return }
            let braceStart = text.index(before: fullR.upperBound)
            guard braceStart < text.endIndex, text[braceStart] == "{" else { return }
            guard let argRange = extractBalancedBrace(text, start: braceStart) else { return }
            let argsRaw = String(text[argRange])
            guard let argsData = argsRaw.data(using: .utf8),
                  let argsObj = try? JSONSerialization.jsonObject(with: argsData),
                  let argsDict = argsObj as? [String: Any]
            else { return }
            let mcp = normalizeMcpIdentifier(String(text[mcpR]))
            let tool = normalizeMcpIdentifier(String(text[toolR]))
            guard !mcp.isEmpty, !tool.isEmpty else { return }
            let wrapper: [String: Any] = ["mcp": mcp, "tool": tool, "arguments": argsDict]
            guard let wstr = safeJSONString(from: wrapper)
            else { return }
            if !out.contains(wstr) {
                out.append(wstr)
            }
        }
    }

    private static func appendCommentaryServerOnlySyntheticJsonObjects(
        text: String,
        into out: inout [String]
    ) {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        commentaryRoutedServerOnlyArgs.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 2,
                  let mcpR = Range(match.range(at: 1), in: text),
                  let fullR = Range(match.range(at: 0), in: text)
            else { return }
            let braceStart = text.index(before: fullR.upperBound)
            guard braceStart < text.endIndex, text[braceStart] == "{" else { return }
            guard let argRange = extractBalancedBrace(text, start: braceStart) else { return }
            let argsRaw = String(text[argRange])
            guard let argsData = argsRaw.data(using: .utf8),
                  let argsObj = try? JSONSerialization.jsonObject(with: argsData),
                  let argsDict = argsObj as? [String: Any]
            else { return }
            let mcp = normalizeMcpIdentifier(String(text[mcpR]))
            guard !mcp.isEmpty else { return }
            let wrapper: [String: Any] = ["mcp": mcp, "arguments": argsDict]
            guard let wstr = safeJSONString(from: wrapper)
            else { return }
            if !out.contains(wstr) {
                out.append(wstr)
            }
        }
    }

    private static func findLooseMcpToolJsonObjects(in text: String) -> [String] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var blocks: [String] = []
        looseMcpJsonStart.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 1 else { return }
            guard let swiftRange = Range(match.range(at: 0), in: text) else { return }
            let braceStart = swiftRange.lowerBound
            guard let pair = extractBalancedBrace(text, start: braceStart) else { return }
            let body = String(text[pair])
            guard isPlausibleMcpToolPayload(body) else { return }
            if !blocks.contains(body) {
                blocks.append(body)
            }
        }
        return blocks
    }

    private static func isPlausibleMcpToolPayload(_ body: String) -> Bool {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        guard let mcp = obj["mcp"] as? String, let tool = obj["tool"] as? String else { return false }
        return !mcp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !tool.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Removes `TOOL_CALL = {…}` blocks (and optional leading `**`) so the bubble matches Python `strip_response_blocks` for tools.
    public static func stripToolCallBlocks(_ text: String) -> String {
        let trimmed = stripMisformattedToolCallPreamble(text)
        let prefix = "TOOL_CALL"
        var ranges: [Range<String.Index>] = []
        var searchRange = trimmed.startIndex..<trimmed.endIndex
        while let r = trimmed.range(of: prefix, options: .caseInsensitive, range: searchRange, locale: nil) {
            var blockStart = r.lowerBound
            if blockStart > trimmed.startIndex {
                let back = trimmed.index(blockStart, offsetBy: -2, limitedBy: trimmed.startIndex) ?? trimmed.startIndex
                let slice = trimmed[back..<blockStart]
                if slice.hasSuffix("**") {
                    blockStart = back
                }
            }
            let afterPrefix = r.upperBound
            guard let eqRange = trimmed.range(of: "=", range: afterPrefix..<trimmed.endIndex) else {
                searchRange = trimmed.index(after: r.upperBound)..<trimmed.endIndex
                continue
            }
            var i = trimmed.index(after: eqRange.upperBound)
            while i < trimmed.endIndex, trimmed[i].isWhitespace { i = trimmed.index(after: i) }
            if trimmed[i..<trimmed.endIndex].hasPrefix("```") {
                if let fence = trimmed[i...].firstIndex(of: "\n") {
                    i = trimmed.index(after: fence)
                }
            }
            while i < trimmed.endIndex, trimmed[i].isWhitespace { i = trimmed.index(after: i) }
            guard i < trimmed.endIndex, trimmed[i] == "{" else {
                searchRange = trimmed.index(after: r.upperBound)..<trimmed.endIndex
                continue
            }
            if let pair = extractBalancedBrace(trimmed, start: i) {
                ranges.append(blockStart..<pair.upperBound)
            }
            searchRange = trimmed.index(after: r.upperBound)..<trimmed.endIndex
        }
        ranges.append(contentsOf: rangesOfLooseMcpToolJson(in: trimmed))
        ranges.append(contentsOf: rangesOfCommentaryRoutedPreamble(in: trimmed))
        guard !ranges.isEmpty else { return trimmed.trimmingCharacters(in: .whitespacesAndNewlines) }
        var out = ""
        var pos = trimmed.startIndex
        for rg in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if pos < rg.lowerBound {
                out += String(trimmed[pos..<rg.lowerBound])
            }
            pos = rg.upperBound
        }
        if pos < trimmed.endIndex {
            out += String(trimmed[pos...])
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops `commentary to=…json` style noise before a loose `{"mcp":…}` blob.
    private static func stripMisformattedToolCallPreamble(_ text: String) -> String {
        guard let r = text.range(of: "{\"mcp\"", options: .caseInsensitive) else { return text }
        let head = text[..<r.lowerBound]
        let lower = head.lowercased()
        if lower.contains("commentary") || head.contains("to=") || lower.hasSuffix("json") {
            return String(text[r.lowerBound...])
        }
        return text
    }

    /// Strips `commentary to=… .tool json{…}` / `commentary to=… tool=… json{…}` (same span as synthesized tool call).
    private static func rangesOfCommentaryRoutedPreamble(in text: String) -> [Range<String.Index>] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var ranges: [Range<String.Index>] = []
        for pattern in commentaryRoutedPatterns {
            pattern.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                guard let match, match.numberOfRanges >= 3,
                      let fullR = Range(match.range(at: 0), in: text)
                else { return }
                let braceStart = text.index(before: fullR.upperBound)
                guard braceStart < text.endIndex, text[braceStart] == "{" else { return }
                guard let argRange = extractBalancedBrace(text, start: braceStart) else { return }
                ranges.append(fullR.lowerBound..<argRange.upperBound)
            }
        }
        commentaryRoutedServerOnlyArgs.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 2,
                  let fullR = Range(match.range(at: 0), in: text)
            else { return }
            let braceStart = text.index(before: fullR.upperBound)
            guard braceStart < text.endIndex, text[braceStart] == "{" else { return }
            guard let argRange = extractBalancedBrace(text, start: braceStart) else { return }
            ranges.append(fullR.lowerBound..<argRange.upperBound)
        }
        return ranges
    }

    private static func rangesOfLooseMcpToolJson(in text: String) -> [Range<String.Index>] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var ranges: [Range<String.Index>] = []
        looseMcpJsonStart.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 1 else { return }
            guard let swiftRange = Range(match.range(at: 0), in: text) else { return }
            let braceStart = swiftRange.lowerBound
            guard let pair = extractBalancedBrace(text, start: braceStart),
                  isPlausibleMcpToolPayload(String(text[pair]))
            else { return }
            ranges.append(braceStart..<pair.upperBound)
        }
        return ranges
    }

    private static func safeJSONString(from value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    /// From index of `{`, return range of full `{…}` with string awareness (matches Python `extract_balanced_brace`).
    public static func extractBalancedBrace(_ s: String, start: String.Index) -> Range<String.Index>? {
        guard start < s.endIndex, s[start] == "{" else { return nil }
        var depth = 0
        var i = start
        var inString: Character?
        var escape = false
        while i < s.endIndex {
            let c = s[i]
            if escape {
                escape = false
                s.formIndex(after: &i)
                continue
            }
            if let q = inString {
                if c == "\\" {
                    escape = true
                    s.formIndex(after: &i)
                    continue
                }
                if c == q {
                    inString = nil
                }
                s.formIndex(after: &i)
                continue
            }
            if c == "\"" || c == "'" {
                inString = c
                s.formIndex(after: &i)
                continue
            }
            if c == "{" {
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0 {
                    let end = s.index(after: i)
                    return start..<end
                }
            }
            s.formIndex(after: &i)
        }
        return nil
    }
}
