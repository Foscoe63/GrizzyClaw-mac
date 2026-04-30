import XCTest
import GrizzyClawCore
import GrizzyClawAgent

final class ChatTranscriptFilterTests: XCTestCase {
    func testAssistantModeHidesTool() {
        let u = ChatMessage(role: .user, content: "hi")
        let a = ChatMessage(role: .assistant, content: "yo")
        let t = ChatMessage(role: .tool, content: "tool out")
        let v = ChatTranscriptFilter.visibleMessages([u, a, t], mode: .assistant, isStreaming: false)
        XCTAssertEqual(v.map(\.role), [.user, .assistant])
    }

    func testAssistantModeKeepsToolWhenNoAssistantSummaryExists() {
        let u = ChatMessage(role: .user, content: "search")
        let a = ChatMessage(role: .assistant, content: "commentary to=ddg-search.searchjson{\"query\":\"iran\"}")
        let t = ChatMessage(role: .tool, content: "[Tool output]\n- result 1\n- result 2")
        let v = ChatTranscriptFilter.visibleMessages([u, a, t], mode: .assistant, isStreaming: false)
        XCTAssertEqual(v.map(\.role), [.user, .assistant, .tool])
    }

    func testToolModeShowsUserAndToolHidesAssistantWhenBlockHasTool() {
        let u = ChatMessage(role: .user, content: "search")
        let a1 = ChatMessage(role: .assistant, content: "")
        let t = ChatMessage(role: .tool, content: "[Tool result s.t]\nresults")
        let a2 = ChatMessage(role: .assistant, content: "summary")
        let v = ChatTranscriptFilter.visibleMessages([u, a1, t, a2], mode: .tool, isStreaming: false)
        XCTAssertEqual(v.map(\.role), [.user, .tool])
    }

    func testToolModeShowsAssistantWhenNoToolInBlock() {
        let u = ChatMessage(role: .user, content: "hello")
        let a = ChatMessage(role: .assistant, content: "reply")
        let v = ChatTranscriptFilter.visibleMessages([u, a], mode: .tool, isStreaming: false)
        XCTAssertEqual(v.map(\.role), [.user, .assistant])
    }

    func testBothModeIncludesTool() {
        let u = ChatMessage(role: .user, content: "q")
        let a = ChatMessage(role: .assistant, content: "a")
        let t = ChatMessage(role: .tool, content: "t")
        let v = ChatTranscriptFilter.visibleMessages([u, a, t], mode: .both, isStreaming: false)
        XCTAssertEqual(v.map(\.role), [.user, .assistant, .tool])
    }

    func testReplyBlockHasTool() {
        let u = ChatMessage(role: .user, content: "u")
        let a = ChatMessage(role: .assistant, content: "call")
        let t = ChatMessage(role: .tool, content: "x")
        let all = [u, a, t]
        XCTAssertTrue(ChatTranscriptFilter.replyBlockHasTool(forAssistantIndex: 1, in: all))
    }

    func testBlankAssistantHiddenUnlessStreaming() {
        let empty = ChatMessage(role: .assistant, content: "   ")
        let v = ChatTranscriptFilter.visibleMessages([empty], mode: .assistant, isStreaming: false)
        XCTAssertTrue(v.isEmpty)
    }

    /// `replyBlockHasTool` scans until the next user — system lines in between do not split the block.
    func testReplyBlockHasToolWithSystemBetweenUserAndTool() {
        let u = ChatMessage(role: .user, content: "q")
        let sys = ChatMessage(role: .system, content: "ctx")
        let a = ChatMessage(role: .assistant, content: "thinking")
        let t = ChatMessage(role: .tool, content: "out")
        let all = [u, sys, a, t]
        XCTAssertTrue(ChatTranscriptFilter.replyBlockHasTool(forAssistantIndex: 2, in: all))
    }
}
