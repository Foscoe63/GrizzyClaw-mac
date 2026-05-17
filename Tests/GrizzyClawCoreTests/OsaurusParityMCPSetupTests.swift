import GrizzyClawCore
import XCTest

final class OsaurusParityMCPSetupTests: XCTestCase {
    func testMacuseRowShape() {
        let row = OsaurusParityMCPSetup.macuseServerRow()
        XCTAssertEqual(row.name, "macuse")
        XCTAssertTrue(row.enabled)
        XCTAssertEqual(row.dictionary["command"] as? String, OsaurusParityMCPSetup.macuseAppBundleExecutable)
        XCTAssertEqual(row.dictionary["args"] as? [String], ["mcp"])
    }

    func testAppendMacuseIdempotent() {
        var servers: [MCPServerRow] = []
        XCTAssertTrue(OsaurusParityMCPSetup.appendMacuseIfMissing(servers: &servers))
        XCTAssertEqual(servers.count, 1)
        XCTAssertFalse(OsaurusParityMCPSetup.appendMacuseIfMissing(servers: &servers))
        XCTAssertEqual(servers.count, 1)
    }

    func testAppendSkipsCaseInsensitiveDuplicate() {
        var servers = [MCPServerRow(name: "MacUse", enabled: true, dictionary: ["command": "x", "args": []])]
        XCTAssertFalse(OsaurusParityMCPSetup.appendMacuseIfMissing(servers: &servers))
        XCTAssertEqual(servers.count, 1)
    }
}
