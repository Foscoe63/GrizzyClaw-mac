import XCTest
@testable import GrizzyClawCore

final class InstalledSkillStoreTests: XCTestCase {
    func testSuggestedSkillIDPrefersFrontMatterName() {
        let markdown = """
        ---
        name: My Fancy Skill
        description: test
        ---

        # Heading
        """

        XCTAssertEqual(InstalledSkillStore.suggestedSkillID(markdown: markdown, fallback: "fallback"), "my_fancy_skill")
    }

    func testSuggestedSkillIDFallsBackToHeadingThenFallback() {
        XCTAssertEqual(
            InstalledSkillStore.suggestedSkillID(markdown: "# Local Files\n\nDetails", fallback: nil),
            "local_files"
        )
        XCTAssertEqual(
            InstalledSkillStore.suggestedSkillID(markdown: "no markers", fallback: "Folder Name"),
            "folder_name"
        )
    }
}
