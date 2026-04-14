import XCTest
import GrizzyClawCore

final class McpToolTranscriptFormattingTests: XCTestCase {
    func testStripLlmInstructionUsesSharedMarker() {
        let body = "line1\nline2"
        let raw = body + McpToolTranscriptFormatting.llmFollowUpInstructionSuffix
        let stripped = McpToolTranscriptFormatting.stripLlmInstructionFromToolDisplay(raw)
        XCTAssertEqual(stripped, body)
    }

    func testToolMessageDisplayStringStripsToolResultPrefix() {
        let raw = "[Tool result foo.bar]\nHello world" + McpToolTranscriptFormatting.llmFollowUpInstructionSuffix
        let out = McpToolTranscriptFormatting.toolMessageDisplayString(rawContent: raw)
        XCTAssertEqual(out, "Hello world")
    }

    func testToolErrorOneLinerShowsFallback() {
        let raw = "[Tool error]"
        let out = McpToolTranscriptFormatting.toolMessageDisplayString(rawContent: raw)
        XCTAssertEqual(out, "Tool error (no additional details).")
    }

    func testEmptySuccessShowsPlaceholder() {
        let raw = "[Tool result x.y]\n" + McpToolTranscriptFormatting.llmFollowUpInstructionSuffix
        let out = McpToolTranscriptFormatting.toolMessageDisplayString(rawContent: raw)
        XCTAssertEqual(out, "(Empty tool result)")
    }
}
