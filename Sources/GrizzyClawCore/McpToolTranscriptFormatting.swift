import Foundation

/// Shared strings and display cleanup for MCP tool rounds (must stay in sync with `ChatSessionModel` injection).
public enum McpToolTranscriptFormatting: Sendable {
    /// Appended to synthetic tool user messages for the LLM; stripped when showing tool bubbles.
    public static let llmFollowUpInstructionSuffix: String =
        "\n\nIf the results above are not enough to fully answer, output another TOOL_CALL. Otherwise answer concisely. Do NOT repeat the same TOOL_CALL."

    /// Removes the LLM instruction block from raw tool content (literal prefix, robust to trailing edits).
    public static func stripLlmInstructionFromToolDisplay(_ full: String) -> String {
        let marker = "\n\nIf the results above are not enough"
        guard let r = full.range(of: marker, options: .literal) else {
            return full.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(full[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips MCP framing for transcript display; never returns an empty string when the raw message indicated an error or had content.
    public static func toolMessageDisplayString(rawContent: String) -> String {
        var t = stripLlmInstructionFromToolDisplay(rawContent)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        let hadToolError = rawContent.range(of: "[Tool error]", options: .literal) != nil
        let blocks = t.components(separatedBy: "\n\n")
        let cleaned: [String] = blocks.compactMap { block in
            var b = block.trimmingCharacters(in: .whitespacesAndNewlines)
            if b.hasPrefix("[Tool result ") {
                if let idx = b.firstIndex(of: "\n") {
                    b = String(b[b.index(after: idx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    b = ""
                }
            } else if b.hasPrefix("[Tool error]") {
                if let idx = b.firstIndex(of: "\n") {
                    b = String(b[b.index(after: idx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    b = ""
                }
            }
            b = compactToolResultBody(b)
            return b.isEmpty ? nil : b
        }
        let joined = cleaned.joined(separator: "\n\n")
        if !joined.isEmpty {
            return joined
        }
        if hadToolError {
            return "Tool error (no additional details)."
        }
        return "(Empty tool result)"
    }

    public static func compactToolResultBody(_ rawBody: String) -> String {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return body }
        let normalized = GrizzyMCPValueConversion.normalize(rawToolResult: body)
        if let formatted = compactStructuredResult(normalized) {
            return formatted
        }
        if !normalized.textBlocks.isEmpty {
            return normalized.textBlocks.joined(separator: "\n\n")
        }
        if let link = normalized.resourceLinks.first {
            let label = link.title ?? link.name
            return "Interactive result available: \(label)"
        }
        return body
    }

    private static func compactStructuredResult(_ normalized: GrizzyMCPValueConversion.NormalizedToolResult) -> String? {
        guard let object = preferredStructuredObject(from: normalized.structuredItems) else { return nil }
        var lines: [String] = []
        if let summary = stringValue(object["summary"]),
           !summary.isEmpty
        {
            lines.append(summary)
        }
        if case .object(let data)? = object["data"] {
            if let calendars = arrayOfObjects(data["calendars"]) {
                if !lines.isEmpty { lines.append("") }
                lines.append(contentsOf: compactCalendarLines(calendars))
            } else if let events = arrayOfObjects(data["events"]) {
                if !lines.isEmpty { lines.append("") }
                lines.append(contentsOf: compactEventLines(events))
            }
        }
        if lines.isEmpty,
           let response = stringValue(object["response"]),
           !response.isEmpty
        {
            lines.append(response)
        }
        if lines.isEmpty, !normalized.textBlocks.isEmpty {
            lines.append(contentsOf: normalized.textBlocks)
        }
        let rendered = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return rendered.isEmpty ? nil : rendered
    }

    private static func preferredStructuredObject(from items: [JSONValue]) -> [String: JSONValue]? {
        for item in items {
            guard case .object(let object) = item else { continue }
            if object["summary"] != nil || object["data"] != nil || object["response"] != nil || object["actions"] != nil {
                return object
            }
        }
        for item in items {
            if case .object(let object) = item { return object }
        }
        return nil
    }

    private static func compactCalendarLines(_ calendars: [[String: JSONValue]]) -> [String] {
        calendars.map { calendar in
            let title = stringValue(calendar["title"]) ?? "Untitled"
            let source = stringValue(calendar["source"])
            return source.map { "- \(title) (\($0))" } ?? "- \(title)"
        }
    }

    private static func compactEventLines(_ events: [[String: JSONValue]]) -> [String] {
        if events.isEmpty {
            return ["- No events found"]
        }
        return events.prefix(20).map { event in
            let title =
                stringValue(event["title"])
                ?? stringValue(event["name"])
                ?? "Untitled"
            let start =
                stringValue(event["start_date"])
                ?? stringValue(event["start"])
                ?? stringValue(event["date"])
            let calendar =
                stringValue(event["calendar"])
                ?? stringValue(event["calendar_title"])
                ?? nestedStringValue(event["calendar"], key: "title")
            var suffix: [String] = []
            if let start, !start.isEmpty { suffix.append(start) }
            if let calendar, !calendar.isEmpty { suffix.append(calendar) }
            if suffix.isEmpty { return "- \(title)" }
            return "- \(title) — \(suffix.joined(separator: " • "))"
        }
    }

    private static func arrayOfObjects(_ value: JSONValue?) -> [[String: JSONValue]]? {
        guard case .array(let array)? = value else { return nil }
        return array.compactMap {
            guard case .object(let object) = $0 else { return nil }
            return object
        }
    }

    private static func stringValue(_ value: JSONValue?) -> String? {
        guard case .string(let text)? = value else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nestedStringValue(_ value: JSONValue?, key: String) -> String? {
        guard case .object(let object)? = value else { return nil }
        return stringValue(object[key])
    }
}
