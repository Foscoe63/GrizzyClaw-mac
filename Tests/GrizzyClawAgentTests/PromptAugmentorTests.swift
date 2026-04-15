import XCTest
import GrizzyClawCore
@testable import GrizzyClawAgent

final class PromptAugmentorTests: XCTestCase {
    private func tool(_ name: String, _ description: String, schema: JSONValue? = nil) -> MCPToolDescriptor {
        MCPToolDescriptor(name: name, description: description, inputSchema: schema)
    }

    func testInternalSchedulerToolHasDescriptionInDiscovery() {
        let merged = MCPToolsDiscoveryResult(servers: [:], errorMessage: nil).mergingPythonInternalTools()
        let createTool = merged.servers["grizzyclaw"]?.first(where: { $0.name == "create_scheduled_task" })
        XCTAssertEqual(createTool?.description, "Create a scheduled task in the scheduler using a cron expression and task message.")
    }

    func testMcpSuffixIncludesAllEnabledToolsWithoutCap() {
        let tools = (1...60).map { i in
            tool("tool_\(i)", "Description \(i)")
        }
        let discovery = MCPToolsDiscoveryResult(
            servers: ["demo": tools],
            errorMessage: nil
        )

        let suffix = MCPSystemPromptAugmentor.mcpSuffix(discovery: discovery) { _, _ in true }

        XCTAssertTrue(suffix.contains("demo.tool_1"))
        XCTAssertTrue(suffix.contains("demo.tool_48"))
        XCTAssertTrue(suffix.contains("demo.tool_60"))
    }

    func testSkillsSuffixIncludesBuiltinAndCustomSkills() {
        let suffix = SkillPromptAugmentor.skillsSuffix(enabledSkillIDs: [
            "scheduler",
            "github",
            "my_custom_skill",
        ])

        XCTAssertTrue(suffix.contains("Enabled ClawHub skills"))
        XCTAssertTrue(suffix.contains("scheduler"))
        XCTAssertTrue(suffix.contains("Scheduler"))
        XCTAssertTrue(suffix.contains("github"))
        XCTAssertTrue(suffix.contains("GitHub"))
        XCTAssertTrue(suffix.contains("my_custom_skill"))
        XCTAssertTrue(suffix.contains("Custom installed skill enabled for this workspace"))
    }

    func testSchedulerSkillSuffixPrefersBuiltInSchedulingTool() {
        let suffix = SkillPromptAugmentor.skillsSuffix(enabledSkillIDs: ["scheduler"])
        XCTAssertTrue(suffix.contains("prefer grizzyclaw.create_scheduled_task"))
        XCTAssertTrue(suffix.contains("instead of generating standalone code"))
    }

    func testSchedulerAndCalendarSkillsExplainDifference() {
        let suffix = SkillPromptAugmentor.skillsSuffix(enabledSkillIDs: ["scheduler", "calendar"])
        XCTAssertTrue(suffix.contains("scheduler"))
        XCTAssertTrue(suffix.contains("calendar"))
        XCTAssertTrue(suffix.contains("not calendar events"))
        XCTAssertTrue(suffix.contains("not background scheduler jobs"))
    }

    func testMcpSuffixWarnsAgainstInventedEventsToolNames() {
        let discovery = MCPToolsDiscoveryResult(
            servers: ["grizzyclaw": [tool("create_scheduled_task", "Create task")]],
            errorMessage: nil
        )
        let suffix = MCPSystemPromptAugmentor.mcpSuffix(discovery: discovery) { _, _ in true }
        XCTAssertTrue(suffix.contains("Do not invent server names like `mcp.events`"))
        XCTAssertTrue(suffix.contains("tool names like `events`"))
    }

    func testMcpSuffixAddsLowContextWorkflowGuidance() {
        let discovery = MCPToolsDiscoveryResult(
            servers: [
                "macuse": [
                    tool("get_tool_definitions", "Discover tools"),
                    tool("call_tool_by_name", "Call discovered tool"),
                ],
            ],
            errorMessage: nil
        )

        let suffix = MCPSystemPromptAugmentor.mcpSuffix(discovery: discovery) { _, _ in true }

        XCTAssertTrue(suffix.contains("Low Context Mode"))
        XCTAssertTrue(suffix.contains("get_tool_definitions"))
        XCTAssertTrue(suffix.contains("call_tool_by_name"))
        XCTAssertTrue(suffix.contains("\"names\": [\"calendar_*\"]"))
        XCTAssertTrue(suffix.contains("Use a relevant wildcard"))
        XCTAssertTrue(suffix.contains("[\"*\"]"))
        XCTAssertTrue(suffix.contains("must start with the `TOOL_CALL`"))
        XCTAssertTrue(suffix.contains("not a description of what you plan to do"))
    }

    func testMcpSuffixIncludesSchemaHintsWhenEnabled() {
        let discovery = MCPToolsDiscoveryResult(
            servers: [
                "macuse": [
                    tool(
                        "call_tool_by_name",
                        "Execute by exact tool name",
                        schema: .object([
                            "type": .string("object"),
                            "properties": .object([
                                "name": .object([
                                    "type": .string("string"),
                                ]),
                                "arguments": .object([
                                    "type": .string("object"),
                                ]),
                            ]),
                            "required": .array([.string("name"), .string("arguments")]),
                        ])
                    ),
                ],
            ],
            errorMessage: nil
        )

        let suffix = MCPSystemPromptAugmentor.mcpSuffix(discovery: discovery, includeSchemas: true) { _, _ in true }

        XCTAssertTrue(suffix.contains("Arguments shape:"))
        XCTAssertTrue(suffix.contains("Required keys: name, arguments"))
        XCTAssertTrue(suffix.contains("Example arguments:"))
    }

    func testCanvasSuffixGuidesA2UIAndAvoidsFakeImages() {
        let suffix = CanvasPromptAugmentor.suffix()

        XCTAssertTrue(suffix.contains("Visual Canvas"))
        XCTAssertTrue(suffix.contains("```a2ui"))
        XCTAssertTrue(suffix.contains("no prose before or after"))
        XCTAssertTrue(suffix.contains("Do not invent screenshot file paths"))
        XCTAssertTrue(suffix.contains("prefer a single ```a2ui block"))
    }
}
