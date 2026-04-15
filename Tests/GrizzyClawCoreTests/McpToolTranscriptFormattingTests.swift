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

    func testToolMessageDisplayStringNormalizesEmbeddedJsonEnvelope() {
        let raw = """
        [Tool result macuse.call_tool_by_name]
        [{"content":"{\\"actions\\":[{\\"instruction\\":\\"Use calendar_reschedule_event to modify an event\\"}],\\"data\\":{\\"events\\":[{\\"calendar_title\\":\\"US Holidays\\",\\"start_date\\":\\"2026-04-15T00:00:00-04:00\\",\\"title\\":\\"Tax Day\\"}]},\\"summary\\":\\"Found 1 event(s)\\"}","type":"text"},{"name":"Search Calendar Events UI","mimeType":"text/html;profile=mcp-app","type":"resource_link","uri":"ui://calendar/event-list"}]
        """ + McpToolTranscriptFormatting.llmFollowUpInstructionSuffix

        let out = McpToolTranscriptFormatting.toolMessageDisplayString(rawContent: raw)

        XCTAssertTrue(out.contains("Found 1 event(s)"))
        XCTAssertTrue(out.contains("Tax Day"))
        XCTAssertTrue(out.contains("US Holidays"))
        XCTAssertFalse(out.contains("\"type\":\"text\""))
        XCTAssertFalse(out.contains("resource_link"))
    }
}
