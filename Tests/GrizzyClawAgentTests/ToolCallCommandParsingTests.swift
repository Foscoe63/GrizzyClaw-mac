import XCTest
@testable import GrizzyClawAgent

final class ToolCallCommandParsingTests: XCTestCase {
    func testLooseMcpJsonWithoutToolCallPrefix() {
        let raw = #"commentary to=fast-filesystem[id=4XR564]json{"mcp":"ddg-search[id=8F800K]","tool":"search","arguments":{}}"#
        let objs = ToolCallCommandParsing.findToolCallJsonObjects(in: raw)
        XCTAssertEqual(objs.count, 1)
        let data = objs[0].data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(ToolCallCommandParsing.normalizeMcpIdentifier((obj["mcp"] as? String)!), "ddg-search")
        XCTAssertEqual(ToolCallCommandParsing.normalizeMcpIdentifier((obj["tool"] as? String)!), "search")
    }

    func testStripRemovesLooseJsonAndPreamble() {
        let raw = #"commentary to=fast-filesystem[id=4XR564]json{"mcp":"ddg-search","tool":"search","arguments":{}}"#
        let stripped = ToolCallCommandParsing.stripToolCallBlocks(raw)
        XCTAssertTrue(stripped.isEmpty || stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testExplicitToolCallStillWorks() {
        let raw = #"I'll search. TOOL_CALL = {"mcp":"ddg-search","tool":"search","arguments":{"query":"iran"}}"#
        let objs = ToolCallCommandParsing.findToolCallJsonObjects(in: raw)
        XCTAssertEqual(objs.count, 1)
    }

    /// Built-in MLX (and similar local models) often emit only args JSON after `commentary to=server[id].tool json`.
    func testCommentaryRoutedArgsOnlyJson() {
        let raw = #"commentary to=ddg-search[id=8F800K].search json{"query":"latest news Iran conflict"}"#
        let objs = ToolCallCommandParsing.findToolCallJsonObjects(in: raw)
        XCTAssertEqual(objs.count, 1)
        let data = objs[0].data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["mcp"] as? String, "ddg-search")
        XCTAssertEqual(obj["tool"] as? String, "search")
        let args = obj["arguments"] as! [String: Any]
        XCTAssertEqual(args["query"] as? String, "latest news Iran conflict")
        let stripped = ToolCallCommandParsing.stripToolCallBlocks(raw)
        XCTAssertTrue(stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Some models use ` tool=search ` instead of `.search` before the args JSON.
    func testCommentaryRoutedToolEqualsBeforeJson() {
        let raw = #"commentary to=ddg-search[id=8F800K] tool=search json{"query":"latest news Iran conflict"}"#
        let objs = ToolCallCommandParsing.findToolCallJsonObjects(in: raw)
        XCTAssertEqual(objs.count, 1)
        let data = objs[0].data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["mcp"] as? String, "ddg-search")
        XCTAssertEqual(obj["tool"] as? String, "search")
        let args = obj["arguments"] as! [String: Any]
        XCTAssertEqual(args["query"] as? String, "latest news Iran conflict")
        let stripped = ToolCallCommandParsing.stripToolCallBlocks(raw)
        XCTAssertTrue(stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testCommentaryRoutedArgumentsKeyword() {
        let raw = #"commentary to=ddg-search[id=8F800K].search arguments{"query":"latest news Iran conflict"}"#
        let objs = ToolCallCommandParsing.findToolCallJsonObjects(in: raw)
        XCTAssertEqual(objs.count, 1)
        let data = objs[0].data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["mcp"] as? String, "ddg-search")
        XCTAssertEqual(obj["tool"] as? String, "search")
        let args = obj["arguments"] as! [String: Any]
        XCTAssertEqual(args["query"] as? String, "latest news Iran conflict")
        let stripped = ToolCallCommandParsing.stripToolCallBlocks(raw)
        XCTAssertTrue(stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testCommentaryRoutedServerOnlyJson() {
        let raw = #"commentary to=ddg-search json{"query":"latest news Iran conflict 2026","topn":10}"#
        let objs = ToolCallCommandParsing.findToolCallJsonObjects(in: raw)
        XCTAssertEqual(objs.count, 1)
        let data = objs[0].data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["mcp"] as? String, "ddg-search")
        XCTAssertNil(obj["tool"])
        let args = obj["arguments"] as! [String: Any]
        XCTAssertEqual(args["query"] as? String, "latest news Iran conflict 2026")
        XCTAssertEqual(args["topn"] as? Int, 10)
        let stripped = ToolCallCommandParsing.stripToolCallBlocks(raw)
        XCTAssertTrue(stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
