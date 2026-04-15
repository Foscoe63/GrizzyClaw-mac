import XCTest
@testable import GrizzyClawCore

final class MCPToolCallerTests: XCTestCase {
    func testEmptyGetToolDefinitionsNamesPatchedToGlobalWildcard() {
        let args: [String: Any] = ["names": []]

        let normalized = MCPToolCaller.normalizedArgumentsForLowContextMetaTool(
            server: "macuse",
            tool: "get_tool_definitions",
            arguments: args
        )

        XCTAssertEqual(normalized["names"] as? [String], ["*"])
    }

    func testMacuseNonEmptyGetToolDefinitionsNamesLeftAlone() {
        let args: [String: Any] = ["names": ["calendar_list_calendars"]]

        let normalized = MCPToolCaller.normalizedArgumentsForLowContextMetaTool(
            server: "macuse",
            tool: "get_tool_definitions",
            arguments: args
        )

        XCTAssertEqual(normalized["names"] as? [String], ["calendar_list_calendars"])
    }

    func testOtherServersEmptyNamesAlsoPatched() {
        let args: [String: Any] = ["names": []]

        let normalized = MCPToolCaller.normalizedArgumentsForLowContextMetaTool(
            server: "other-server",
            tool: "get_tool_definitions",
            arguments: args
        )

        XCTAssertEqual(normalized["names"] as? [String], ["*"])
    }

    func testPlaceholderNameItemIsPatchedToGlobalWildcard() {
        let args: [String: Any] = ["names": ["item"]]

        let normalized = MCPToolCaller.normalizedArgumentsForLowContextMetaTool(
            server: "macuse",
            tool: "get_tool_definitions",
            arguments: args
        )

        XCTAssertEqual(normalized["names"] as? [String], ["*"])
    }

    func testNonPlaceholderNameIsLeftAlone() {
        let args: [String: Any] = ["names": ["calendar_*"]]

        let normalized = MCPToolCaller.normalizedArgumentsForLowContextMetaTool(
            server: "macuse",
            tool: "get_tool_definitions",
            arguments: args
        )

        XCTAssertEqual(normalized["names"] as? [String], ["calendar_*"])
    }

    func testOtherToolsAreNotPatched() {
        let args: [String: Any] = ["names": []]

        let normalized = MCPToolCaller.normalizedArgumentsForLowContextMetaTool(
            server: "macuse",
            tool: "call_tool_by_name",
            arguments: args
        )

        XCTAssertEqual(normalized["names"] as? [AnyHashable], [])
    }
}
