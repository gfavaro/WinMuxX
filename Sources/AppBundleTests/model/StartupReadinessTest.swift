@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class StartupReadinessTest: WorkspaceTestCase {
    func testAnAppThatDoesNotAnswerDuringStartupStillLeavesWinMuxReady() async throws {
        let previouslyReady = isWinMuxRuntimeReady
        let previouslyEnabled = TrayMenuModel.shared.isEnabled
        defer { isWinMuxRuntimeReady = previouslyReady; TrayMenuModel.shared.isEnabled = previouslyEnabled }
        isWinMuxRuntimeReady = false
        TrayMenuModel.shared.isEnabled = true
        let window = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)

        var discoveries = 0
        setBlockingRefreshOverridesForTests(refresh: {
            discoveries += 1
            throw AXReadFailure(code: .cannotComplete)
        })
        var followUps: [RefreshSessionEvent] = []
        setScheduledRefreshOverrideForTests { event, _ in followUps.append(event) }
        await runStartupSessions(restoredWorld: false)
        try await waitForScheduledRefreshForTests()

        XCTAssertEqual(discoveries, 1)
        XCTAssertTrue(isWinMuxRuntimeReady)
        // The windows already known are laid out, and discovery is asked for again.
        XCTAssertNotNil(window.lastAppliedLayoutPhysicalRect)
        XCTAssertTrue(followUps.contains { if case .workspaceRestoration = $0 { true } else { false } })
    }
}
