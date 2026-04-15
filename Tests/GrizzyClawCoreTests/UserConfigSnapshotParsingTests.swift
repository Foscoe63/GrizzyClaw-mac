import GrizzyClawCore
import XCTest

final class UserConfigSnapshotParsingTests: XCTestCase {
    func testEnabledSkillsAcceptsSingleString() {
        let snap = UserConfigSnapshot(
            parsing: ["enabled_skills": "scheduler"],
            configPath: URL(fileURLWithPath: "/tmp/config.yaml")
        )
        XCTAssertEqual(snap.enabledSkills, ["scheduler"])
    }

    func testNSNumberCoercionsWork() {
        let snap = UserConfigSnapshot(
            parsing: [
                "font_size": NSNumber(value: 42),
                "debug": NSNumber(value: true),
            ],
            configPath: URL(fileURLWithPath: "/tmp/config.yaml")
        )
        XCTAssertEqual(snap.fontSize, 42)
        XCTAssertTrue(snap.debug)
    }
}
