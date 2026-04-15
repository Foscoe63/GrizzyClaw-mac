import XCTest
@testable import GrizzyClawCore

final class WorkspaceTransferIOTests: XCTestCase {
    func testDecodeWorkspacePayloadSupportsWrapperExport() throws {
        let json = """
        {
          "version": 1,
          "workspace": {
            "name": "Imported Workspace",
            "description": "desc",
            "icon": "🤖",
            "color": "#007AFF",
            "config": {
              "system_prompt": "hello"
            }
          }
        }
        """.data(using: .utf8)!

        let payload = try WorkspaceTransferIO.decodeWorkspacePayload(from: json)
        XCTAssertEqual(payload["name"] as? String, "Imported Workspace")
        let config = payload["config"] as? [String: Any]
        XCTAssertEqual(config?["system_prompt"] as? String, "hello")
    }

    func testDecodeWorkspacePayloadMapsOsaurusPersona() throws {
        let json = """
        {
          "version": 1,
          "persona": {
            "name": "Osaurus Agent",
            "description": "Imported from Osaurus",
            "systemPrompt": "Be helpful",
            "defaultModel": "claude",
            "temperature": 0.2,
            "maxTokens": 2048,
            "riskMode": "read_only"
          }
        }
        """.data(using: .utf8)!

        let payload = try WorkspaceTransferIO.decodeWorkspacePayload(from: json)
        XCTAssertEqual(payload["name"] as? String, "Osaurus Agent")
        let config = payload["config"] as? [String: Any]
        XCTAssertEqual(config?["system_prompt"] as? String, "Be helpful")
        XCTAssertEqual(config?["llm_model"] as? String, "claude")
        XCTAssertEqual(config?["max_tokens"] as? Int, 2048)
        XCTAssertEqual(config?["autonomy_level"] as? String, "read_only")
    }
}
