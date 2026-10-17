@testable import AppBundle
import AppKit
import XCTest

final class AXWindowOperationTest: XCTestCase {
    func testStaleOptionalReadOrWriteRetriesOnceAgainstNewElement() throws {
        var loads: [Bool] = []
        var attempts = 0
        let result: Int? = try withRecoverableWindow(load: { replacing in
            loads.append(replacing)
            return replacing ? 2 : 1
        }, body: { element in
            attempts += 1
            if element == 1 { AXWindowOperation.current?.record(.invalidUIElement); return nil }
            return element * 10
        })
        XCTAssertEqual(result, 20)
        XCTAssertEqual(loads, [false, true])
        XCTAssertEqual(attempts, 2)
        XCTAssertNil(AXWindowOperation.current)
    }

    func testSecondInvalidElementFailsWithoutLooping() {
        var loads = 0
        XCTAssertThrowsError(try withRecoverableWindow(load: { _ in loads += 1; return 1 }, body: { _ -> Int? in
            throw AXReadFailure(code: .invalidUIElement)
        }))
        XCTAssertEqual(loads, 2)
    }

    func testTimeoutCancellationUnsupportedAndMissingWindowsDoNotRetry() throws {
        for error in [AXError.cannotComplete, .attributeUnsupported] {
            var loads = 0
            let result: Int? = try withRecoverableWindow(load: { _ in loads += 1; return 1 }, body: { _ in
                AXWindowOperation.current?.record(error)
                return nil
            })
            XCTAssertNil(result)
            XCTAssertEqual(loads, 1)
        }
        var loads = 0
        XCTAssertThrowsError(try withRecoverableWindow(load: { _ in loads += 1; return 1 }, body: { _ -> Int? in throw CancellationError() }))
        XCTAssertEqual(loads, 1)
        var calls = 0
        let missing: Int? = try withRecoverableWindow(load: { _ -> Int? in nil }, body: { _ in calls += 1; return 2 })
        XCTAssertNil(missing)
        XCTAssertEqual(calls, 0)
    }
    func testStaleChildControlAndAppReadsDoNotInvalidateTheWindow() throws {
        let window = NSObject(), button = NSObject(), app = NSObject()
        var loads = 0
        let result: Int? = try withRecoverableWindow(load: { _ in loads += 1; return window }, identify: ObjectIdentifier.init, body: { _ in
            AXWindowOperation.current?.record(.invalidUIElement, from: ObjectIdentifier(button))
            AXWindowOperation.current?.record(.invalidUIElement, from: ObjectIdentifier(app))
            return 42
        })
        XCTAssertEqual(result, 42)
        XCTAssertEqual(loads, 1)
    }

    func testOnlyTheTargetWindowErrorTriggersReplacement() throws {
        let original = NSObject(), replacement = NSObject()
        var loads: [Bool] = []
        let result: Bool? = try withRecoverableWindow(load: { replacing in
            loads.append(replacing)
            return replacing ? replacement : original
        }, identify: ObjectIdentifier.init, body: { window in
            if window === original {
                AXWindowOperation.current?.record(.invalidUIElement, from: ObjectIdentifier(window))
                return nil
            }
            return window === replacement
        })
        XCTAssertEqual(result, true)
        XCTAssertEqual(loads, [false, true])
    }

}
