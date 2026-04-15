import XCTest
import GrizzyClawCore

final class MCPEnablementFromStoredPairsTests: XCTestCase {
    private func tool(_ name: String, _ description: String = "") -> MCPToolDescriptor {
        MCPToolDescriptor(name: name, description: description)
    }

    func testNilStoredMeansAllEnabled() {
        let merged = MCPToolsDiscoveryResult(
            servers: ["ddg-search": [tool("search")]],
            errorMessage: nil
        ).mergingPythonInternalTools()
        XCTAssertTrue(
            MCPEnablementFromStoredPairs.isDiscoveredToolEnabled(
                storedPairs: nil,
                discoveredServer: "ddg-search",
                discoveredTool: "search",
                merged: merged
            )
        )
    }

    func testStaleToolNameSingleToolServerInheritsEnabled() {
        let merged = MCPToolsDiscoveryResult(
            servers: ["ddg-search": [tool("ddg_web_search")]],
            errorMessage: nil
        ).mergingPythonInternalTools()
        let stored: [[String]] = [["ddg-search", "search"]]
        XCTAssertTrue(
            MCPEnablementFromStoredPairs.isDiscoveredToolEnabled(
                storedPairs: stored,
                discoveredServer: "ddg-search",
                discoveredTool: "ddg_web_search",
                merged: merged
            )
        )
    }

    func testExactMatchStillWorks() {
        let merged = MCPToolsDiscoveryResult(
            servers: ["ddg-search": [tool("search")]],
            errorMessage: nil
        ).mergingPythonInternalTools()
        let stored: [[String]] = [["ddg-search", "search"]]
        XCTAssertTrue(
            MCPEnablementFromStoredPairs.isDiscoveredToolEnabled(
                storedPairs: stored,
                discoveredServer: "ddg-search",
                discoveredTool: "search",
                merged: merged
            )
        )
    }
}
