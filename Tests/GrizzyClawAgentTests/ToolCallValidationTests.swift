import XCTest
import GrizzyClawCore
@testable import GrizzyClawAgent

final class ToolCallValidationTests: XCTestCase {
    private func tool(_ name: String, _ description: String) -> MCPToolDescriptor {
        MCPToolDescriptor(name: name, description: description)
    }

    private func lowContextDiscovery() -> MCPToolsDiscoveryResult {
        MCPToolsDiscoveryResult(
            servers: [
                "macuse": [
                    tool("get_tool_definitions", "Describe tools"),
                    tool("call_tool_by_name", "Call tool")
                ]
            ],
            errorMessage: nil
        )
    }

    func testKnownToolPassesValidation() {
        let discovery = MCPToolsDiscoveryResult(
            servers: ["ddg-search": [tool("search", "Web search")]],
            errorMessage: nil
        )
        XCTAssertTrue(ToolCallValidation.isKnownTool(server: "ddg-search", tool: "search", discovery: discovery))
    }

    func testInventedEventsToolFailsValidation() {
        let discovery = MCPToolsDiscoveryResult(
            servers: ["grizzyclaw": [tool("create_scheduled_task", "Create task")]],
            errorMessage: nil
        )
        XCTAssertFalse(ToolCallValidation.isKnownTool(server: "mcp.events", tool: "events", discovery: discovery))
    }

    func testInvalidToolMessageGuidesSchedulerPath() {
        let discovery = MCPToolsDiscoveryResult(
            servers: ["grizzyclaw": [tool("create_scheduled_task", "Create task")]],
            errorMessage: nil
        )
        let msg = ToolCallValidation.invalidToolMessage(
            requestedServer: "mcp.events",
            requestedTool: "events",
            discovery: discovery
        )
        XCTAssertTrue(msg.contains("grizzyclaw.create_scheduled_task"))
        XCTAssertTrue(msg.contains("mcp.events.events"))
    }

    func testLowContextNarrationWithoutToolCallIsRejected() {
        let msg = ToolCallValidation.lowContextMissingToolCallMessage(
            assistantText: """
            The user wants to use macuse mcp-server and list the calendars on this Mac.
            According to instructions, we must first call get_tool_definitions.
            """,
            messages: [ChatMessage(role: .user, content: "use macuse mcp-server and list the calendars on this mac")],
            discovery: lowContextDiscovery()
        )
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg?.contains("macuse") == true)
        XCTAssertTrue(msg?.contains("TOOL_CALL") == true)
        XCTAssertTrue(msg?.contains("get_tool_definitions") == true)
    }

    func testLowContextHallucinatedResultsAreRejected() {
        let msg = ToolCallValidation.lowContextMissingToolCallMessage(
            assistantText: """
            I’ve retrieved the full set of macOS Calendar tool definitions.
            Let me know which of these actions you’d like to perform.
            """,
            messages: [ChatMessage(role: .user, content: "use macuse mcp-server and list the calendars on this mac")],
            discovery: lowContextDiscovery()
        )
        XCTAssertNotNil(msg)
        XCTAssertTrue(msg?.contains("calendar_*") == true)
    }

    func testLowContextFallbackSynthesizesCalendarDefinitionsCall() {
        let json = ToolCallValidation.lowContextFallbackToolCallJSON(
            assistantText: """
            The user wants to use macuse mcp-server and list the calendars on this Mac.
            According to instructions, we must first call get_tool_definitions.
            """,
            messages: [ChatMessage(role: .user, content: "use macuse mcp-server and list the calendars on this mac")],
            discovery: lowContextDiscovery()
        )
        XCTAssertNotNil(json)
        XCTAssertTrue(json?.contains("\"mcp\": \"macuse\"") == true)
        XCTAssertTrue(json?.contains("\"tool\": \"get_tool_definitions\"") == true)
        XCTAssertTrue(json?.contains("\"calendar_*\"") == true)
    }

    func testLowContextFallbackUsesGlobalWildcardWhenDomainUnknown() {
        let json = ToolCallValidation.lowContextFallbackToolCallJSON(
            assistantText: """
            According to instructions, we must first call get_tool_definitions.
            """,
            messages: [ChatMessage(role: .user, content: "use macuse mcp-server")],
            discovery: lowContextDiscovery()
        )
        XCTAssertNotNil(json)
        XCTAssertTrue(json?.contains("\"*\"") == true)
    }

    func testNormalAssistantReplyIsNotRejected() {
        let msg = ToolCallValidation.lowContextMissingToolCallMessage(
            assistantText: "Here are your calendars: Home, Work.",
            messages: [ChatMessage(role: .user, content: "use macuse mcp-server and list the calendars on this mac")],
            discovery: lowContextDiscovery()
        )
        XCTAssertNil(msg)
    }
}
