import Foundation
import XCTest
@testable import GrizzyClawAgent

final class ModelListFetchTests: XCTestCase {
    func testLmStudioV1DocsShape() {
        let json = """
        {
          "models": [
            {
              "type": "llm",
              "publisher": "lmstudio-community",
              "key": "gemma-3-270m-it-qat",
              "display_name": "Gemma 3 270m Instruct Qat"
            },
            {
              "type": "embedding",
              "key": "text-embedding-nomic-embed-text-v1.5",
              "display_name": "Nomic Embed"
            }
          ]
        }
        """
        let data = json.data(using: .utf8)!
        let ids = ModelListFetch.parseLmStudioNativeModelsJSON(data)
        XCTAssertEqual(ids, ["gemma-3-270m-it-qat"])
    }

    func testOpenAIStyleDataArray() {
        let json = """
        { "data": [ { "id": "qwen2-vl-7b-instruct", "object": "model" } ] }
        """
        let data = json.data(using: .utf8)!
        let ids = ModelListFetch.parseLmStudioNativeModelsJSON(data)
        XCTAssertEqual(ids, ["qwen2-vl-7b-instruct"])
    }

    func testStringModelIds() {
        let json = "{ \"models\": [\"alpha\", \"beta\"] }"
        let data = json.data(using: .utf8)!
        let ids = ModelListFetch.parseLmStudioNativeModelsJSON(data)
        XCTAssertEqual(ids, ["alpha", "beta"])
    }

    func testMixedStringAndObjectEntries() {
        let json = """
        {
          "models": [
            "plain-id",
            { "type": "llm", "key": "from-object" }
          ]
        }
        """
        let data = json.data(using: .utf8)!
        let ids = ModelListFetch.parseLmStudioNativeModelsJSON(data)
        XCTAssertEqual(ids, ["from-object", "plain-id"])
    }

    func testLoopbackBaseCandidatesTryLocalhostAndIPv4() {
        let c = ModelListFetch.lmStudioNativeModelListBaseCandidates("http://localhost:1234")
        XCTAssertTrue(c.contains("http://localhost:1234"))
        XCTAssertTrue(c.contains("http://127.0.0.1:1234"))
    }

    func testLanBaseSingleCandidate() {
        let c = ModelListFetch.lmStudioNativeModelListBaseCandidates("http://192.168.1.10:1234")
        XCTAssertEqual(c, ["http://192.168.1.10:1234"])
    }

    func testNormalizeLmStudioOpenAICompatBaseForModelsList() {
        XCTAssertEqual(
            ModelListFetch.normalizeLmStudioOpenAICompatBaseForModelsList("http://localhost:1234"),
            "http://localhost:1234/v1"
        )
        XCTAssertEqual(
            ModelListFetch.normalizeLmStudioOpenAICompatBaseForModelsList("http://192.168.1.10:8000/v1/"),
            "http://192.168.1.10:8000/v1"
        )
        XCTAssertEqual(
            ModelListFetch.normalizeLmStudioOpenAICompatBaseForModelsList("192.168.1.10:8000/v1"),
            "http://192.168.1.10:8000/v1"
        )
        XCTAssertNil(ModelListFetch.normalizeLmStudioOpenAICompatBaseForModelsList("   "))
    }

    func testCollapseDuplicateLmStudioPort() {
        XCTAssertEqual(
            ModelListFetch.collapseDuplicateLmStudioAuthorityPort("http://localhost:1234:1234"),
            "http://localhost:1234"
        )
        XCTAssertEqual(
            ModelListFetch.collapseDuplicateLmStudioAuthorityPort("http://192.168.1.10:8000:8000/v1"),
            "http://192.168.1.10:8000/v1"
        )
    }
}
