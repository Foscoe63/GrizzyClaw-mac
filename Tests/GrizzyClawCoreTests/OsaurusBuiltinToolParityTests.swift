import XCTest
@testable import GrizzyClawCore

final class OsaurusBuiltinToolParityTests: XCTestCase {
    func testRenderChartCSVLineSeries() {
        let csv = "a,b\n1,10\n2,20\n3,30"
        let args: [String: Any] = [
            "data": csv,
            "format": "csv",
            "chartType": "line",
            "series": ["b"],
            "xColumn": "a",
            "title": "Demo",
        ]
        let out = OsaurusRenderChartParity.execute(tool: "grizzyclaw.render_chart", arguments: args)
        XCTAssertTrue(ToolEnvelope.isSuccess(out), out)
        let text = ToolEnvelope.successText(out) ?? ""
        XCTAssertTrue(text.contains("---CHART_START---"), text)
        XCTAssertTrue(text.contains("---CHART_END---"), text)
        XCTAssertTrue(text.contains("\"chartType\":\"line\""), text)
        XCTAssertTrue(text.contains("\"name\":\"b\""), text)
    }

    func testRenderChartRejectsUnknownChartType() {
        let csv = "a,b\n1,2"
        let args: [String: Any] = ["data": csv, "chartType": "not_a_real_type", "series": ["b"]]
        let out = OsaurusRenderChartParity.execute(tool: "grizzyclaw.render_chart", arguments: args)
        XCTAssertTrue(ToolEnvelope.isFailure(out), out)
        XCTAssertNotNil(ToolEnvelope.failureMessage(out))
    }

    func testCompleteSummaryValidatorRejectsShort() {
        XCTAssertNotNil(OsaurusCompleteSummaryValidator.validationMessage(for: "too short"))
    }

    func testCompleteSummaryValidatorRejectsPlaceholder() {
        XCTAssertNotNil(OsaurusCompleteSummaryValidator.validationMessage(for: "done"))
    }

    func testCompleteSummaryValidatorAcceptsRealSummary() {
        let s =
            "Added the health route in server.ts and verified with curl http://127.0.0.1:8080/health returning HTTP 200."
        XCTAssertNil(OsaurusCompleteSummaryValidator.validationMessage(for: s))
    }

    func testClarifyOptionsNormalizeDedupes() {
        let raw = [" Yes ", "yes", "No", "", "  Maybe "]
        let n = OsaurusClarifyOptionsRules.normalizeOptions(raw)
        XCTAssertEqual(n, ["Yes", "No", "Maybe"])
    }

    func testChartParserSegmentsFromEnvelope() {
        let csv = "a,b\n1,2"
        let chartOut = OsaurusRenderChartParity.execute(tool: "t", arguments: [
            "data": csv,
            "chartType": "column",
            "series": ["b"],
            "xColumn": "a",
        ])
        XCTAssertTrue(ToolEnvelope.isSuccess(chartOut))
        guard let markerBlock = ToolEnvelope.successText(chartOut) else {
            XCTFail("expected text")
            return
        }
        let envelope = ToolEnvelope.success(tool: "grizzyclaw.render_chart", text: markerBlock)
        let segs = GrizzyChartTranscriptParser.segments(from: envelope)
        XCTAssertEqual(segs.count, 1)
        guard case .chart(let spec) = segs[0] else {
            XCTFail("expected chart segment")
            return
        }
        XCTAssertEqual(spec.chartType, "column")
        XCTAssertEqual(spec.series.count, 1)
    }
}
