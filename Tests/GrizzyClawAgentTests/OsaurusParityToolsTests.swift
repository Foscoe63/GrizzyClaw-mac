import XCTest
import GrizzyClawCore
@testable import GrizzyClawAgent

final class OsaurusParityToolsTests: XCTestCase {
    func testAllBundledInternalToolsIncludesOsaurusParityNames() {
        let names = Set(MCPToolsDiscoveryResult.allBundledInternalTools.map(\.name))
        XCTAssertTrue(names.contains("todo"))
        XCTAssertTrue(names.contains("complete"))
        XCTAssertTrue(names.contains("clarify"))
        XCTAssertTrue(names.contains("methods_save"))
        XCTAssertTrue(names.contains("methods_report"))
        XCTAssertTrue(names.contains("memory_search_working"))
        XCTAssertTrue(names.contains("memory_search_graph"))
        XCTAssertTrue(names.contains("spawn_subagent"))
    }

    func testTodoToolReturnsFailureWhenMarkdownMissing() {
        let config = UserConfigSnapshot(parsing: [:], configPath: URL(fileURLWithPath: "/tmp/grizzy-test-config.yaml"))
        let out = GrizzyClawInternalToolStubs.result(
            tool: "todo",
            arguments: [:],
            workspaceId: "ws-test",
            config: config
        )
        XCTAssertTrue(ToolEnvelope.isFailure(out), out)
        XCTAssertTrue(out.contains("invalid_args"), out)
        XCTAssertTrue(out.contains("markdown"), out)
    }

    func testTodoToolReturnsSuccessWhenMarkdownPresent() {
        let config = UserConfigSnapshot(parsing: [:], configPath: URL(fileURLWithPath: "/tmp/grizzy-test-config.yaml"))
        let out = GrizzyClawInternalToolStubs.result(
            tool: "todo",
            arguments: ["markdown": "- [ ] One thing"],
            workspaceId: "ws-test",
            config: config
        )
        XCTAssertTrue(ToolEnvelope.isSuccess(out), out)
    }
}
