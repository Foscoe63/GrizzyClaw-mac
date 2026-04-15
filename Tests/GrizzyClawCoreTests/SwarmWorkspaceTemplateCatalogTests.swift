import GrizzyClawCore
import XCTest

final class SwarmWorkspaceTemplateCatalogTests: XCTestCase {
    func testDefaultTemplateLoads() throws {
        let config = try SwarmWorkspaceTemplateCatalog.configObject(forTemplateKey: "default")
        XCTAssertFalse(config.isEmpty)
        XCTAssertEqual(config["llm_provider"], .string("ollama"))
    }

    func testMissingTemplateKeyThrowsExpectedError() throws {
        XCTAssertThrowsError(
            try SwarmWorkspaceTemplateCatalog.configObject(forTemplateKey: "__missing_template__")
        ) { error in
            guard case SwarmTemplateError.missingTemplateKey(let key) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(key, "__missing_template__")
        }
    }
}
