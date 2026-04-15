import XCTest
import GrizzyClawCore

final class WorkspaceAllowlistFilterTests: XCTestCase {
    private func tool(_ name: String, _ description: String) -> MCPToolDescriptor {
        MCPToolDescriptor(name: name, description: description)
    }

    func testAllowlistNormalizesUserPrefixedServer() {
        let disc = MCPToolsDiscoveryResult(
            servers: [
                "ddg-search": [tool("search", "Web search")],
            ],
            errorMessage: nil
        )
        let filtered = disc.filteredByWorkspaceAllowlist([("user-ddg-search", "search")])
        XCTAssertEqual(filtered.servers["ddg-search"]?.map(\.name), ["search"])
    }

    func testAllowlistFallsBackWhenNothingMatches() {
        let disc = MCPToolsDiscoveryResult(
            servers: [
                "ddg-search": [tool("ddg_web_search", "x")],
            ],
            errorMessage: nil
        )
        let filtered = disc.filteredByWorkspaceAllowlist([("ddg-search", "search")])
        XCTAssertEqual(filtered.servers["ddg-search"]?.map(\.name), ["ddg_web_search"])
    }
}
