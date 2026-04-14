import XCTest
import GrizzyClawCore
@testable import GrizzyClawAgent

final class ToolCallValidationTests: XCTestCase {
    func testKnownToolPassesValidation() {
        let discovery = MCPToolsDiscoveryResult(
            servers: ["ddg-search": [(name: "search", description: "Web search")]],
            errorMessage: nil
        )
        XCTAssertTrue(ToolCallValidation.isKnownTool(server: "ddg-search", tool: "search", discovery: discovery))
    }

    func testInventedEventsToolFailsValidation() {
        let discovery = MCPToolsDiscoveryResult(
            servers: ["grizzyclaw": [(name: "create_scheduled_task", description: "Create task")]],
            errorMessage: nil
        )
        XCTAssertFalse(ToolCallValidation.isKnownTool(server: "mcp.events", tool: "events", discovery: discovery))
    }

    func testInvalidToolMessageGuidesSchedulerPath() {
        let discovery = MCPToolsDiscoveryResult(
            servers: ["grizzyclaw": [(name: "create_scheduled_task", description: "Create task")]],
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
}
