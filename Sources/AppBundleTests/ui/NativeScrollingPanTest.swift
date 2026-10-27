@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class NativeScrollingPanTest: WorkspaceTestCase {
    private func fixture() -> Workspace {
        let workspace = focus.workspace
        workspace.rootTilingContainer.layout = .tiles
        let windows = (0..<4).map { TestWindow.new(id: UInt32(97000 + $0), parent: workspace.rootTilingContainer) }
        windows.forEach { $0.scrollingColumnWidth = 0.7 }
        workspace.transitionArrangement(to: .scrolling)
        _ = windows[0].focusWindow()
        runtime.workspaceBackend.selectForStartup(.native, nativeTilingEnabled: true)
        WorkspaceScrollingGestureController.shared.reset()
        return workspace
    }

    private func router(option: Bool, over workspace: Workspace) -> NativeScrollingTouchRouter {
        let router = NativeScrollingTouchRouter()
        router.optionOnly = { option }
        router.pointer = { workspace.workspaceMonitor.rect.center }
        router.controller = WorkspaceScrollingGestureController(dependencies: .init(eligible: { true }, reduceMotion: { true }))
        return router
    }

    private func frame(_ x: Double, y: Double = 0.5, time: Double, fingers: Int = 2) -> WorkspaceTouchFrame {
        .init(device: 1, fingers: fingers, x: x, y: y, timestamp: time, contacts: 77)
    }

    func testOptionTwoFingerSwipeUsesTheVirtualGestureController() {
        let workspace = fixture()
        let router = router(option: true, over: workspace)
        let before = workspace.scrollingOffset
        for (index, x) in [0.60, 0.56, 0.50, 0.44].enumerated() { router.handle(frame(x, time: Double(index) * 0.01)) }
        XCTAssertTrue(router.ownsGesture)
        XCTAssertGreaterThan(workspace.scrollingOffset, before, "Fingers moving left reveal columns to the right")
        XCTAssertTrue(workspace.scrollingGestureMotionActive)
        router.handle(frame(0, time: 0.05, fingers: 0))
        XCTAssertFalse(router.ownsGesture)
    }

    func testThreeFingersPlainScrollsAndVerticalMovesStayWithMacOS() {
        let workspace = fixture()
        let before = workspace.scrollingOffset
        let three = router(option: true, over: workspace)
        for (index, x) in [0.6, 0.5, 0.4].enumerated() { three.handle(frame(x, time: Double(index) * 0.01, fingers: 3)) }
        XCTAssertFalse(three.ownsGesture, "Three fingers switch Spaces in macOS")
        let plain = router(option: false, over: workspace)
        for (index, x) in [0.6, 0.5, 0.4].enumerated() { plain.handle(frame(x, time: Double(index) * 0.01)) }
        XCTAssertFalse(plain.ownsGesture)
        let vertical = router(option: true, over: workspace)
        for (index, y) in [0.6, 0.5, 0.4].enumerated() { vertical.handle(frame(0.5, y: y, time: Double(index) * 0.01)) }
        XCTAssertFalse(vertical.ownsGesture, "A vertical two-finger move is an ordinary scroll")
        XCTAssertEqual(workspace.scrollingOffset, before)
    }

    func testConsumedPanKeepsItsMomentumAndReleasesTheNextScroll() {
        let pan = NativeScrollingPan()
        XCTAssertFalse(pan.consumes(phase: 2, momentumPhase: 0, panning: false))
        XCTAssertTrue(pan.consumes(phase: 2, momentumPhase: 0, panning: true))
        XCTAssertTrue(pan.consumes(phase: 4, momentumPhase: 0, panning: false), "The end of the pan")
        XCTAssertTrue(pan.consumes(phase: 0, momentumPhase: 2, panning: false), "Momentum after lifting")
        XCTAssertTrue(pan.consumes(phase: 0, momentumPhase: 3, panning: false))
        XCTAssertFalse(pan.consumes(phase: 1, momentumPhase: 0, panning: false), "The next scroll reaches the app")
    }
}
