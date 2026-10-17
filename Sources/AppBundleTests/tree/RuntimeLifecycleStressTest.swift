@testable import AppBundle
import Common
import XCTest

/// Exercises model transitions only: no desktop windows, AX traffic, or gestures.
@MainActor
final class RuntimeLifecycleStressTest: WorkspaceTestCase {
    func testFixtureResetReleasesDetachedMinimizedAndPopupWindows() {
        weak var minimized: TestWindow?
        weak var popup: TestWindow?
        minimized = TestWindow.new(id: 90001, parent: macosMinimizedWindowsContainer)
        popup = TestWindow.new(id: 90002, parent: macosPopupWindowsContainer)
        XCTAssertNotNil(minimized)
        XCTAssertNotNil(popup)

        setUpWorkspacesForTests()

        XCTAssertTrue(macosMinimizedWindowsContainer.children.isEmpty)
        XCTAssertTrue(macosPopupWindowsContainer.children.isEmpty)
        XCTAssertNil(minimized)
        XCTAssertNil(popup)
    }

    func testRepeatedFullscreenMinimizeMoveAndClosePreserveUniqueLiveWindows() async throws {
        let workspaces = (0..<4).map { Workspace.get(byName: "lifecycle-stress-\($0)") }
        config.persistentWorkspaces = workspaces.map(\.name).toOrderedSet()
        var windows = (0..<32).map { index in
            TestWindow.new(id: UInt32(index + 1), parent: workspaces[index % 4].rootTilingContainer)
        }
        var nextId: UInt32 = 33

        for cycle in 0..<40 {
            let beforeFullscreen = windows.map { $0.nodeWorkspace }
            for window in windows { window.nativeIsMacosFullscreen = true }
            try await normalizeLayoutReason()
            for window in windows {
                XCTAssertTrue(window.parent is MacosFullscreenWindowsContainer)
            }
            assertUniqueLiveWindows(windows)

            for window in windows { window.nativeIsMacosFullscreen = false }
            try await normalizeLayoutReason()
            for (window, original) in zip(windows, beforeFullscreen) {
                XCTAssertTrue(window.nodeWorkspace === original)
                XCTAssertTrue(window.parent is TilingContainer)
            }

            for window in windows { window.nativeIsMacosMinimized = true }
            try await normalizeLayoutReason()
            XCTAssertEqual(macosMinimizedWindowsContainer.children.count, windows.count)
            assertUniqueLiveWindows(windows)

            let destination = workspaces[cycle % workspaces.count]
            XCTAssertTrue(destination.focusWorkspace())
            for window in windows { window.nativeIsMacosMinimized = false }
            try await normalizeLayoutReason()
            XCTAssertTrue(macosMinimizedWindowsContainer.children.isEmpty)
            // Minimized windows detach from their old workspace and restore into the selected one.
            for window in windows { XCTAssertTrue(window.nodeWorkspace === destination) }

            for window in windows.prefix(4) {
                let id = window.windowId
                window.closeAxWindow()
                XCTAssertNil(Window.get(byId: id))
            }
            windows.removeFirst(4)
            TestApp.shared.focusedWindow = nil
            TestApp.shared._windows.removeAll { !$0.isBound }
            for _ in 0..<4 {
                windows.append(TestWindow.new(id: nextId, parent: destination.rootTilingContainer))
                nextId += 1
            }
            XCTAssertTrue(windows[cycle % windows.count].focusWindow())
            refreshModel()
            assertUniqueLiveWindows(windows)
        }
        XCTAssertEqual(TestApp.shared.windows.count, 32)
    }

    private func assertUniqueLiveWindows(_ expected: [TestWindow], file: StaticString = #filePath, line: UInt = #line) {
        let bound = Workspace.all.flatMap(\.allLeafWindowsRecursive) +
            macosMinimizedWindowsContainer.children.compactMap { $0 as? Window }
        XCTAssertEqual(bound.count, expected.count, file: file, line: line)
        XCTAssertEqual(Set(bound.map(\.windowId)), Set(expected.map(\.windowId)), file: file, line: line)
        XCTAssertEqual(Set(bound.map(ObjectIdentifier.init)).count, expected.count, file: file, line: line)
    }
}
