import GrizzyClawCore
import XCTest

final class GrizzyClawDoctorServiceTests: XCTestCase {
    func testDoctorReportEncodesRoundTrip() throws {
        let r = GrizzyClawDoctorService.buildReport()
        XCTAssertEqual(r.app.name, "GrizzyClaw")
        XCTAssertTrue(r.controlPlane.embeddedHTTPServer)
        if r.localInference.appleSilicon {
            XCTAssertEqual(r.localInference.bundledEngine, "mlx-swift-lm")
        } else {
            XCTAssertEqual(r.localInference.bundledEngine, "none")
        }
        XCTAssertFalse(r.sandbox.linuxVMExecutionAvailable)

        let data = try JSONEncoder().encode(r)
        XCTAssertFalse(data.isEmpty)
        let copy = try JSONDecoder().decode(GrizzyClawDoctorReport.self, from: data)
        XCTAssertEqual(copy.status, r.status)
        XCTAssertEqual(copy.timestamp, r.timestamp)
    }
}
