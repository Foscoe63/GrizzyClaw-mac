import GrizzyClawCore
import XCTest

final class OsaurusBundledPluginManifestTests: XCTestCase {
    func testLoadsManifestToolsFromBundle() {
        let tools = OsaurusBundledPluginToolRegistry.internalTools
        XCTAssertGreaterThanOrEqual(tools.count, 100, "Expected full osaurus-tools plugins/ surface")
        XCTAssertTrue(OsaurusBundledPluginToolRegistry.isBundledPluginServer("osaurus.time"))
        XCTAssertTrue(tools.contains { $0.server == "osaurus.time" && $0.name == "current_time" })
        XCTAssertTrue(tools.contains { $0.server == "osaurus.fetch" && $0.name == "fetch" })
    }

    func testMergedDiscoveryIncludesBundledServers() {
        let empty = MCPToolsDiscoveryResult(servers: [:], errorMessage: nil)
        let merged = empty.mergingPythonInternalTools()
        XCTAssertNotNil(merged.servers["osaurus.time"])
        XCTAssertTrue(merged.servers["grizzyclaw"]?.contains(where: { $0.name == "get_status" }) == true)
    }
}
