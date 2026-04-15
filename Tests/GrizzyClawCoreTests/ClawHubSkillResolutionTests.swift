import XCTest
@testable import GrizzyClawCore

final class ClawHubSkillResolutionTests: XCTestCase {
    func testResolvedSkillIDsFallsBackToGlobalDefaultsWhenWorkspaceHasNoOverride() {
        var user = UserConfigSnapshot.empty
        user.enabledSkills = ["scheduler", "github"]

        let workspace = WorkspaceRecord.makeNew(
            id: "ws1",
            name: "Workspace",
            description: nil,
            icon: "🤖",
            color: "#007AFF",
            order: 0,
            config: .object(["llm_provider": .string("ollama")])
        )

        XCTAssertFalse(ClawHubSkillResolver.usesWorkspaceOverride(workspace: workspace))
        XCTAssertEqual(
            ClawHubSkillResolver.resolvedSkillIDs(user: user, workspace: workspace),
            ["scheduler", "github"]
        )
    }

    func testResolvedSkillIDsPrefersExplicitWorkspaceOverride() {
        var user = UserConfigSnapshot.empty
        user.enabledSkills = ["scheduler", "github"]

        let workspace = WorkspaceRecord.makeNew(
            id: "ws2",
            name: "Research",
            description: nil,
            icon: "🤖",
            color: "#007AFF",
            order: 0,
            config: .object([
                "enabled_skills": .array([
                    .string("web_search"),
                    .string("scheduler"),
                ])
            ])
        )

        XCTAssertTrue(ClawHubSkillResolver.usesWorkspaceOverride(workspace: workspace))
        XCTAssertEqual(
            ClawHubSkillResolver.resolvedSkillIDs(user: user, workspace: workspace),
            ["web_search", "scheduler"]
        )
    }

    func testResolvedSkillIDsSupportsExplicitEmptyWorkspaceOverride() {
        var user = UserConfigSnapshot.empty
        user.enabledSkills = ["scheduler", "github"]

        let workspace = WorkspaceRecord.makeNew(
            id: "ws3",
            name: "Minimal",
            description: nil,
            icon: "🤖",
            color: "#007AFF",
            order: 0,
            config: .object(["enabled_skills": .array([])])
        )

        XCTAssertTrue(ClawHubSkillResolver.usesWorkspaceOverride(workspace: workspace))
        XCTAssertEqual(ClawHubSkillResolver.resolvedSkillIDs(user: user, workspace: workspace), [])
    }
}
