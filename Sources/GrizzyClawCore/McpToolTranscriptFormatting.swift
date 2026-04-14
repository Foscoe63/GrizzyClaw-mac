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
}
