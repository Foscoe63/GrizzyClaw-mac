import XCTest
import GrizzyClawCore

final class GrizzyMCPValueConversionTests: XCTestCase {
    func testNormalizeRawToolResultParsesTextEnvelopeAndResourceLinks() {
        let raw = """
        [{"content":"{\\"actions\\":[{\\"instruction\\":\\"Search for today's events\\",\\"tool_call\\":{\\"tool\\":\\"calendar_search_events\\",\\"arguments\\":{\\"start_date\\":\\"today\\",\\"end_date\\":\\"+1d\\"}}}],\\"summary\\":\\"Found 2 event(s)\\"}","type":"text"},{"name":"Search Calendar Events UI","mimeType":"text/html;profile=mcp-app","type":"resource_link","uri":"ui://calendar/event-list"}]
        """

        let normalized = GrizzyMCPValueConversion.normalize(rawToolResult: raw)

        XCTAssertEqual(normalized.textBlocks, [])
        XCTAssertEqual(normalized.structuredItems.count, 1)
        XCTAssertEqual(normalized.resourceLinks.count, 1)
        XCTAssertEqual(normalized.resourceLinks.first?.name, "Search Calendar Events UI")
    }

    func testReturnedActionCallsParsesEmbeddedJsonInsideTextEnvelope() {
        let raw = """
        [{"content":"{\\"actions\\":[{\\"instruction\\":\\"Search for today's events\\",\\"tool_call\\":{\\"tool\\":\\"calendar_search_events\\",\\"arguments\\":{\\"start_date\\":\\"today\\",\\"end_date\\":\\"+1d\\"}}}],\\"summary\\":\\"Found 2 event(s)\\"}","type":"text"}]
        """

        let actions = GrizzyMCPValueConversion.returnedActionCalls(from: raw)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].tool, "calendar_search_events")
        XCTAssertEqual(actions[0].jsonObjectArguments()["start_date"] as? String, "today")
        XCTAssertEqual(actions[0].jsonObjectArguments()["end_date"] as? String, "+1d")
    }

    func testActionCallDetectsAngleBracketPlaceholder() {
        let bad = GrizzyMCPValueConversion.ActionCall(
            tool: "calendar_open_event",
            arguments: ["event": .string("<value>")]
        )
        XCTAssertTrue(bad.hasPlaceholderArguments())

        let good = GrizzyMCPValueConversion.ActionCall(
            tool: "calendar_search_events",
            arguments: [
                "start_date": .string("today"),
                "end_date": .string("+1d"),
            ]
        )
        XCTAssertFalse(good.hasPlaceholderArguments())
    }
}
