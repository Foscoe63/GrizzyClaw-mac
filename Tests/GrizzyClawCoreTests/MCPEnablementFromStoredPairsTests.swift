import XCTest
import GrizzyClawCore

final class MCPEnablementFromStoredPairsTests: XCTestCase {
    func testNilStoredMeansAllEnabled() {
        let merged = MCPToolsDiscoveryResult(
            servers: ["ddg-search": [(name: "search", description: "")]],
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
            servers: ["ddg-search": [(name: "ddg_web_search", description: "")]],
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
            servers: ["ddg-search": [(name: "search", description: "")]],
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
