@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class WindowDiagnosticRecordingTest: WorkspaceTestCase {
    override func tearDown() async throws {
        _ = finishWindowDebugRecording()
        try await super.tearDown()
    }

    func testFailedSnapshotDoesNotBlockWorkspaceCommandsOrRepeatOnEveryRefresh() async throws {
        TrayMenuModel.shared.isEnabled = true
        _ = TestWindow.new(id: 99101, parent: focus.workspace.rootTilingContainer).focusWindow()
        let started = try await DebugWindowsCommand(args: DebugWindowsCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(started.exitCode, 0)
        let problematic = TestWindow.new(id: 99102, parent: focus.workspace.rootTilingContainer)
        var reads = 0
        try await debugWindowsIfRecording(problematic) { _ in
            reads += 1
            throw AXReadFailure(code: .invalidUIElement)
        }
        try await debugWindowsIfRecording(problematic) { _ in
            reads += 1
            throw AXReadFailure(code: .cannotComplete)
        }
        XCTAssertEqual(reads, 1)
        let destination = Workspace.get(byName: "2")
        _ = TestWindow.new(id: 99105, parent: destination.rootTilingContainer)
        let moved = try await runLightSession(.hotkeyBinding, .forceRun, shouldSchedulePostRefresh: false) {
            activateWorkspaceForUser(destination, on: mainMonitor)
        }
        XCTAssertTrue(moved)
        XCTAssertTrue(focus.workspace === destination)
        let result = finishWindowDebugRecording()
        XCTAssertTrue(result.contains("Window 99102: diagnostic capture failed"))
        XCTAssertTrue(result.contains(String(AXError.invalidUIElement.rawValue)))
        XCTAssertTrue(result.contains("Debug session finished"))
    }

    func testCancelledSnapshotDoesNotBecomeARecordedFailure() async throws {
        TrayMenuModel.shared.isEnabled = true
        _ = TestWindow.new(id: 99103, parent: focus.workspace.rootTilingContainer).focusWindow()
        _ = try await DebugWindowsCommand(args: DebugWindowsCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)
        let target = TestWindow.new(id: 99104, parent: focus.workspace.rootTilingContainer)
        do {
            try await debugWindowsIfRecording(target) { _ in throw CancellationError() }
            XCTFail("Cancellation must propagate")
        } catch is CancellationError { }
        try await debugWindowsIfRecording(target) { _ in "second capture succeeded" }
        XCTAssertTrue(finishWindowDebugRecording().contains("second capture succeeded"))
    }
}
