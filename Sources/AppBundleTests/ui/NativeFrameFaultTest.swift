@testable import AppBundle
import AppKit
import XCTest

private final class FrameAX: AxUiElementMock {
    enum PositionWrites { case accept, ignore, clamp, fail }
    var positionWrites = PositionWrites.accept
    var attributes: [String: AnyObject] = [:]
    var writes: [String] = []
    var reads: [String] = []
    func seed<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) { attributes[attr.key] = attr.setter(value) }
    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T? { reads.append(attr.key); return attributes[attr.key].flatMap(attr.getter) }
    func containingWindowId() -> CGWindowID? { nil }
    func set<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) -> Bool {
        writes.append(attr.key)
        if attr.key == Ax.topLeftCornerAttr.key {
            switch positionWrites {
                case .ignore: return true
                case .fail: return false
                case .clamp: attributes[attr.key] = Ax.topLeftCornerAttr.setter(CGPoint(x: 5, y: 5)); return true
                case .accept: break
            }
        }
        attributes[attr.key] = attr.setter(value)
        return true
    }
}

final class NativeFrameFaultTest: XCTestCase {
    func testRevokedPermitPreventsAnyFrameOrAnimationSettingWrite() {
        let window = FrameAX(), app = FrameAX()
        window.seed(Ax.topLeftCornerAttr, .zero)
        window.seed(Ax.sizeAttr, CGSize(width: 400, height: 300))
        XCTAssertThrowsError(try setFrame(window, app: app, CGPoint(x: 100, y: 100),
            CGSize(width: 800, height: 600), RunLoopJob(), validateWrite: { throw CancellationError() }))
        XCTAssertTrue(window.writes.isEmpty)
        XCTAssertTrue(app.writes.isEmpty)
    }

    func testPermitIsRecheckedBetweenSizeAndPositionWrites() {
        let window = FrameAX(), app = FrameAX()
        window.seed(Ax.topLeftCornerAttr, .zero)
        window.seed(Ax.sizeAttr, CGSize(width: 400, height: 300))
        var checks = 0
        XCTAssertThrowsError(try setFrame(window, app: app, CGPoint(x: 100, y: 100),
            CGSize(width: 800, height: 600), RunLoopJob(), validateWrite: {
                checks += 1
                if checks == 3 { throw CancellationError() }
            }))
        XCTAssertEqual(window.writes, [Ax.sizeAttr.key])
        XCTAssertEqual(window.get(Ax.topLeftCornerAttr), .zero)
    }

    func testPermitIsRecheckedBeforeParkingStylePositionReassertion() {
        let window = FrameAX(), app = FrameAX()
        window.positionWrites = .ignore
        window.seed(Ax.topLeftCornerAttr, .zero)
        window.seed(Ax.sizeAttr, CGSize(width: 400, height: 300))
        var checks = 0
        XCTAssertThrowsError(try setFrame(window, app: app, CGPoint(x: 100, y: 100),
            CGSize(width: 800, height: 600), RunLoopJob(), positionFirst: true, validateWrite: {
                checks += 1
                if checks == 4 { throw CancellationError() }
            }))
        XCTAssertEqual(window.writes, [Ax.topLeftCornerAttr.key, Ax.sizeAttr.key])
    }

    func testSatisfiedFrameAvoidsAllWritesAndAnimationReads() throws {
        let window = FrameAX(), app = FrameAX()
        let origin = CGPoint(x: 10, y: 20), size = CGSize(width: 800, height: 600)
        window.seed(Ax.topLeftCornerAttr, origin); window.seed(Ax.sizeAttr, size)
        try setFrame(window, app: app, origin, size, RunLoopJob())
        XCTAssertTrue(window.writes.isEmpty)
        XCTAssertTrue(app.reads.isEmpty)
        XCTAssertTrue(app.writes.isEmpty)
    }

    func testAcceptedIgnoredClampedAndFailedMovesRemainBounded() throws {
        for mode in [FrameAX.PositionWrites.accept, .ignore, .clamp, .fail] {
            let window = FrameAX(), app = FrameAX()
            window.positionWrites = mode
            window.seed(Ax.topLeftCornerAttr, CGPoint.zero)
            window.seed(Ax.sizeAttr, CGSize(width: 400, height: 300))
            let target = CGPoint(x: 100, y: 120)
            try setFrame(window, app: app, target, CGSize(width: 800, height: 600), RunLoopJob(), positionFirst: true)
            let observed = window.get(Ax.topLeftCornerAttr)
            if mode == .accept { XCTAssertEqual(observed, target) }
            else { XCTAssertNotEqual(observed, target, "Success from AX is not proof of movement") }
            XCTAssertLessThanOrEqual(window.writes.filter { $0 == Ax.topLeftCornerAttr.key }.count, 2)
            XCTAssertEqual(window.get(Ax.sizeAttr), CGSize(width: 800, height: 600))
        }
    }
}
