import XCTest
@testable import GrizzyClawCore

final class MCPToolsDiscoveryTests: XCTestCase {
    func testProbeRowsSkipsDisabledServers() {
        let rows = [
            MCPServerRow(name: "enabled-1", enabled: true, dictionary: ["command": "one"]),
            MCPServerRow(name: "disabled-1", enabled: false, dictionary: ["command": "two"]),
            MCPServerRow(name: "enabled-2", enabled: true, dictionary: ["command": "three"]),
        ]

        let probed = MCPToolsDiscovery.probeRows(rows: rows)
        XCTAssertEqual(probed.map(\.name), ["enabled-1", "enabled-2"])
    }

    func testProbeRowsWithFilterStillSkipsDisabledServers() {
        let rows = [
            MCPServerRow(name: "enabled-1", enabled: true, dictionary: ["command": "one"]),
            MCPServerRow(name: "disabled-1", enabled: false, dictionary: ["command": "two"]),
        ]

        let probed = MCPToolsDiscovery.probeRows(rows: rows, onlyServerNames: ["enabled-1", "disabled-1"])
        XCTAssertEqual(probed.map(\.name), ["enabled-1"])
        XCTAssertTrue(probed.allSatisfy(\.enabled))
    }
}
