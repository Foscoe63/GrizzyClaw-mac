import XCTest
import GrizzyClawCore

final class GuiChatPreferencesCodableTests: XCTestCase {
    func testRoundTripMcpTranscriptMode() throws {
        var prefs = GuiChatPreferences()
        prefs.mcpTranscriptMode = .both
        prefs.mcpAutoFollowActions = false
        prefs.llm = GuiChatPreferences.LLM(provider: "openai", model: "gpt-4")

        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(GuiChatPreferences.self, from: data)

        XCTAssertEqual(decoded.mcpTranscriptMode, .both)
        XCTAssertEqual(decoded.mcpAutoFollowActions, false)
        XCTAssertEqual(decoded.llm?.provider, "openai")
        XCTAssertEqual(decoded.llm?.model, "gpt-4")
    }

    func testInvalidMcpTranscriptModeStringDecodesToNil() throws {
        let json = """
        {"mcpTranscriptMode":"not-a-valid-case","llm":null,"mcpEnabledPairs":null}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(GuiChatPreferences.self, from: json)
        XCTAssertNil(decoded.mcpTranscriptMode)
    }

    func testValidMcpTranscriptModeStringDecodes() throws {
        let json = """
        {"mcpTranscriptMode":"tool","llm":null,"mcpEnabledPairs":null}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(GuiChatPreferences.self, from: json)
        XCTAssertEqual(decoded.mcpTranscriptMode, .tool)
    }
}
