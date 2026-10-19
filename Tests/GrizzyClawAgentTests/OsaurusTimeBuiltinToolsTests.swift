@testable import GrizzyClawAgent
import GrizzyClawCore
import XCTest

final class OsaurusTimeBuiltinToolsTests: XCTestCase {
    func testCurrentTimeUTC() {
        let r = OsaurusTimeBuiltinTools.result(tool: "current_time", arguments: ["timezone": "UTC"])
        XCTAssertTrue(ToolEnvelope.isSuccess(r), r)
    }

    func testListTimezonesPrefix() {
        let r = OsaurusTimeBuiltinTools.result(tool: "list_timezones", arguments: ["prefix": "America/New"])
        XCTAssertTrue(ToolEnvelope.isSuccess(r), r)
        XCTAssertTrue(r.contains("New_York"), r)
    }

    func testDiffDates() {
        let r = OsaurusBundledPluginToolHandlers.result(
            server: "osaurus.time",
            tool: "diff_dates",
            arguments: ["a": 0, "b": 3600]
        )
        XCTAssertTrue(ToolEnvelope.isSuccess(r), r)
    }

    func testNonTimeBundledPluginSyncPathMentionsAsync() {
        let r = OsaurusBundledPluginToolHandlers.result(
            server: "osaurus.fetch",
            tool: "fetch",
            arguments: [:]
        )
        XCTAssertTrue(ToolEnvelope.isFailure(r), r)
        XCTAssertTrue(r.contains("async_tool"), r)
    }

    func testFetchBuiltinBlocksPrivateURL() async {
        let r = await OsaurusBundledPluginToolHandlers.bundledResultIfApplicable(
            server: "osaurus.fetch",
            tool: "fetch",
            arguments: ["url": "http://127.0.0.1/"]
        )
        XCTAssertNotNil(r)
        XCTAssertTrue(ToolEnvelope.isFailure(r!), r!)
        XCTAssertTrue(r!.contains("invalid_url"), r!)
    }
}
