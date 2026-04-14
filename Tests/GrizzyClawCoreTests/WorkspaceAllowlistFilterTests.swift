import XCTest
import GrizzyClawCore

final class WorkspaceAllowlistFilterTests: XCTestCase {
    func testAllowlistNormalizesUserPrefixedServer() {
        let disc = MCPToolsDiscoveryResult(
            servers: [
                "ddg-search": [(name: "search", description: "Web search")],
            ],
            errorMessage: nil
        )
        let filtered = disc.filteredByWorkspaceAllowlist([("user-ddg-search", "search")])
        XCTAssertEqual(filtered.servers["ddg-search"]?.map(\.name), ["search"])
    }

    func testAllowlistFallsBackWhenNothingMatches() {
        let disc = MCPToolsDiscoveryResult(
            servers: [
                "ddg-search": [(name: "ddg_web_search", description: "x")],
            ],
            errorMessage: nil
        )
        let filtered = disc.filteredByWorkspaceAllowlist([("ddg-search", "search")])
        XCTAssertEqual(filtered.servers["ddg-search"]?.map(\.name), ["ddg_web_search"])
    }
}
