@testable import AppBundle
import Observation
import XCTest

/// Counts change notifications, which Observation may deliver off the main thread.
final class ObservationCounter: @unchecked Sendable {
    var value = 0
}

/// The tray model is republished wholesale on every refresh session. Observation must notify
/// only for real changes, and only views that read the changed property, or every refresh
/// would redraw the menu bar label, sidebar panels and tab strips.
@MainActor
final class TrayMenuModelObservationTest: XCTestCase {
    /// How many times `read`'s properties were reported changed while `write` ran.
    private func notifications(reading read: @escaping () -> Void, during write: () -> Void) -> Int {
        let count = ObservationCounter()
        withObservationTracking(read) { count.value += 1 }
        write()
        return count.value
    }

    func testOnlyRealChangesNotify() {
        let model = TrayMenuModel()
        model.menuBarWorkspaceIndicator = "A"
        XCTAssertEqual(notifications(reading: { _ = model.menuBarWorkspaceIndicator }) { model.menuBarWorkspaceIndicator = "A" }, 0,
                       "The same value again: no redraw")
        XCTAssertEqual(notifications(reading: { _ = model.menuBarWorkspaceIndicator }) { model.menuBarWorkspaceIndicator = "B" }, 1)
        XCTAssertEqual(notifications(reading: { _ = model.workspaceSidebarHoveredWorkspaceName }) {
            model.workspaceSidebarHoveredWorkspaceName = nil
        }, 0, "Writing the default value must not notify")
    }

    func testOnlyReadersOfTheChangedPropertyAreNotified() {
        let model = TrayMenuModel()
        XCTAssertEqual(notifications(reading: { _ = model.workspaceSidebarWorkspaces }) { model.menuBarWorkspaceIndicator = "Z" }, 0)
    }
}
