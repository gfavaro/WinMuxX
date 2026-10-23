@testable import AppBundle
import CoreGraphics
import XCTest

final class PrivateCapabilityDiagnosticsTest: XCTestCase {
    func testPrivateFrameNeedsAnIndependentPublicWitness() {
        let frame = CGRect(x: 10, y: 20, width: 800, height: 600)
        XCTAssertEqual(comparePrivateWindowFrame(frame, publicFrame: nil), .inconclusive("no public window-list witness"))
        XCTAssertEqual(comparePrivateWindowFrame(nil, publicFrame: frame), .failed("private frame query returned no frame"))
    }

    func testPrivateFrameMustMatchPublicBoundsWithinOnePoint() {
        let frame = CGRect(x: 10, y: 20, width: 800, height: 600)
        XCTAssertEqual(comparePrivateWindowFrame(frame, publicFrame: frame), .verified)
        XCTAssertEqual(comparePrivateWindowFrame(CGRect(x: 12, y: 20, width: 800, height: 600), publicFrame: frame),
                       .failed("private frame disagrees with public bounds"))
    }
}
