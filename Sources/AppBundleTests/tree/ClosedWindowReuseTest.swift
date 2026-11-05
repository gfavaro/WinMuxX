@testable import AppBundle
import XCTest

@MainActor
final class ClosedWindowReuseTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        resetClosedWindowsCache()
    }

    override func tearDown() async throws { resetClosedWindowsCache() }

    func testEmptyCacheDoesNotSkipNewWindowRules() async throws {
        let window = TestWindow.new(id: 901, parent: focus.workspace.rootTilingContainer)
        let restored = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window)
        XCTAssertFalse(restored)
    }

    func testNativeClosePreventsReusedIdInheritingOldWorkspaceAndFullscreen() async throws {
        let oldWorkspace = Workspace.get(byName: "old")
        let old = TestWindow.new(id: 902, parent: oldWorkspace.rootTilingContainer)
        old.isFullscreen = true
        replaceClosedWindowsCache(snapshotCurrentFrozenWorld())
        old.unbindFromParent()
        invalidateClosedWindowsCacheForNativeClosure(old.windowId)
        let newWorkspace = Workspace.get(byName: "new")
        let new = TestWindow.new(id: 902, parent: newWorkspace.rootTilingContainer)
        let restored = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: new)
        XCTAssertFalse(restored)
        XCTAssertEqual(new.nodeWorkspace, newWorkspace)
        XCTAssertFalse(new.isFullscreen)
    }

    func testNativeCloseOfOneMissingWindowStillReturnsTheOthers() async throws {
        let home = Workspace.get(byName: "home")
        let other = Workspace.get(byName: "other")
        let missing = TestWindow.new(id: 904, parent: home.rootTilingContainer)
        let closed = TestWindow.new(id: 905, parent: other.rootTilingContainer)
        replaceClosedWindowsCache(snapshotCurrentFrozenWorld())
        missing.unbindFromParent()
        closed.unbindFromParent()
        invalidateClosedWindowsCacheForNativeClosure(closed.windowId)

        let reused = TestWindow.new(id: 905, parent: focus.workspace.rootTilingContainer)
        let reusedRestored = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: reused)
        XCTAssertFalse(reusedRestored)
        XCTAssertTrue(reused.nodeWorkspace === focus.workspace)

        let returned = TestWindow.new(id: 904, parent: focus.workspace.rootTilingContainer)
        let restored = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: returned)
        XCTAssertTrue(restored)
        XCTAssertEqual(returned.nodeWorkspace?.name, home.name)
        XCTAssertTrue(reused.nodeWorkspace === focus.workspace, "Restoring the others leaves the reused ID where it is")
    }

    func testUnrelatedNativeCloseDoesNotDiscardRecoverableAxSnapshot() async throws {
        let window = TestWindow.new(id: 903, parent: focus.workspace.rootTilingContainer)
        replaceClosedWindowsCache(snapshotCurrentFrozenWorld())
        invalidateClosedWindowsCacheForNativeClosure(999)
        let restored = try await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window)
        XCTAssertTrue(restored)
    }
}
