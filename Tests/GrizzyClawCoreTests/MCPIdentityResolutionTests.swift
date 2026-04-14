import XCTest
import GrizzyClawCore

final class MCPIdentityResolutionTests: XCTestCase {
    func testServerExactAndCase() {
        let known = ["ddg-search", "filesystem"]
        XCTAssertEqual(
            MCPIdentityResolution.canonicalServerName(modelOutput: "ddg-search", knownServers: known),
            "ddg-search"
        )
        XCTAssertEqual(
            MCPIdentityResolution.canonicalServerName(modelOutput: "DDG-SEARCH", knownServers: known),
            "ddg-search"
        )
    }

    func testServerUserPrefixCursorStyle() {
        let known = ["ddg-search"]
        XCTAssertEqual(
            MCPIdentityResolution.canonicalServerName(modelOutput: "user-ddg-search", knownServers: known),
            "ddg-search"
        )
    }

    func testServerBracketSuffixIsRemoved() {
        let known = ["ddg-search"]
        XCTAssertEqual(
            MCPIdentityResolution.canonicalServerName(modelOutput: "ddg-search[id=8F800K]", knownServers: known),
            "ddg-search"
        )
    }

    func testServerUnderscoreToHyphen() {
        let known = ["ddg-search"]
        XCTAssertEqual(
            MCPIdentityResolution.canonicalServerName(modelOutput: "ddg_search", knownServers: known),
            "ddg-search"
        )
    }

    func testSearchAliases() {
        let known = ["ddg-search"]
        XCTAssertEqual(
            MCPIdentityResolution.canonicalServerName(modelOutput: "web-search", knownServers: known),
            "ddg-search"
        )
        XCTAssertEqual(
            MCPIdentityResolution.canonicalServerName(modelOutput: "google-search", knownServers: known),
            "ddg-search"
        )
        XCTAssertEqual(
            MCPIdentityResolution.canonicalServerName(modelOutput: "search", knownServers: known),
            "ddg-search"
        )
    }

    func testServerUnknownReturnsOriginal() {
        let known = ["a"]
        XCTAssertEqual(
            MCPIdentityResolution.canonicalServerName(modelOutput: "nonexistent", knownServers: known),
            "nonexistent"
        )
    }

    func testToolCaseInsensitive() {
        let tools = ["search", "fetch"]
        XCTAssertEqual(
            MCPIdentityResolution.canonicalToolName(modelOutput: "Search", knownTools: tools),
            "search"
        )
    }

    func testToolBracketSuffixIsRemoved() {
        let tools = ["search"]
        XCTAssertEqual(
            MCPIdentityResolution.canonicalToolName(modelOutput: "search[id=abc123]", knownTools: tools),
            "search"
        )
    }

    func testToolSingleKnownIdModelsOftenSaySearch() {
        let tools = ["ddg_web_search"]
        XCTAssertEqual(
            MCPIdentityResolution.canonicalToolName(modelOutput: "search", knownTools: tools),
            "ddg_web_search"
        )
    }
}
