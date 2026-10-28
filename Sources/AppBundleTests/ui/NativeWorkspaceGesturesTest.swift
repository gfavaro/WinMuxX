@testable import AppBundle
import XCTest

@MainActor
final class NativeWorkspaceGesturesTest: WorkspaceTestCase {
    func testNativeSpacesLeaveWorkspaceGesturesToMacOS() {
        config.workspaceSwipe.enabled = true
        config.workspaceOverview.threeFingerUp = true
        XCTAssertTrue(workspaceSwipeGestureEnabled)
        XCTAssertTrue(workspaceOverviewGestureEnabled)

        runtime.workspaceBackend.selectForStartup(.native, nativeTilingEnabled: true)
        XCTAssertFalse(workspaceSwipeGestureEnabled)
        XCTAssertFalse(workspaceOverviewGestureEnabled)
        XCTAssertFalse(WorkspaceGestureRouterDependencies.live.horizontalEnabled())
        XCTAssertFalse(WorkspaceGestureRouterDependencies.live.overviewEnabled())
        XCTAssertFalse(WorkspaceSwipeDependencies.live.canNavigate())
    }
}
