@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class PalettePresentationLifetimeTest: XCTestCase {
    func testOlderOpeningCannotReplaceNewerOpeningInEitherCompletionOrder() async {
        for oldFirst in [true, false] {
            let model = SwitcherPaletteModel()
            var pending: [CheckedContinuation<[SwitcherPaletteItem], Never>] = []
            let firstStarted = expectation(description: "first loader")
            let secondStarted = expectation(description: "second loader")
            let panel = SwitcherPalettePanel(model: model, loadItems: {
                await withCheckedContinuation { continuation in
                    pending.append(continuation)
                    (pending.count == 1 ? firstStarted : secondStarted).fulfill()
                }
            }, nativePresentation: false)
            let first = Task { await panel.show() }
            await fulfillment(of: [firstStarted], timeout: 2)
            panel.dismiss()
            let second = Task { await panel.show(groupByWorkspace: true) }
            await fulfillment(of: [secondStarted], timeout: 2)
            let item = SwitcherPaletteItem(id: 2, title: "New", appName: "Fixture", icon: nil, workspaceName: "1", isFocused: false)
            if oldFirst {
                pending[0].resume(returning: [])
                await first.value
                XCTAssertTrue(model.items.isEmpty)
                pending[1].resume(returning: [item])
            } else {
                pending[1].resume(returning: [item])
                await second.value
                pending[0].resume(returning: [])
            }
            await first.value
            await second.value
            XCTAssertEqual(model.items.map(\.id), [2])
            XCTAssertTrue(model.groupByWorkspace)
            XCTAssertTrue(panel.isPaletteActive)
            panel.dismiss()
        }
    }

    func testDismissedOpeningCannotPresentAndOldClickCannotDismissNewOpening() async {
        var callbacks: [@MainActor () -> Void] = []
        var removed = 0
        let panel = SwitcherPalettePanel(loadItems: { [] }, nativePresentation: false,
            observeOutsideClicks: { callback in callbacks.append(callback); return [NSObject(), NSObject()] },
            removeMonitor: { _ in removed += 1 })
        for _ in 0..<100 {
            await panel.show()
            XCTAssertEqual(panel.ownedMonitorCount, 2)
            if callbacks.count > 1 { callbacks[callbacks.count - 2]() }
            XCTAssertTrue(panel.isPaletteActive)
            callbacks.last?()
            XCTAssertFalse(panel.isPaletteActive)
            XCTAssertEqual(panel.ownedMonitorCount, 0)
            panel.dismiss()
        }
        XCTAssertEqual(removed, 200)
    }

    func testDismissDuringLoadingRejectsCompletion() async {
        var pending: CheckedContinuation<[SwitcherPaletteItem], Never>?
        let started = expectation(description: "loader")
        let panel = SwitcherPalettePanel(loadItems: {
            await withCheckedContinuation { pending = $0; started.fulfill() }
        }, nativePresentation: false)
        let opening = Task { await panel.show() }
        await fulfillment(of: [started], timeout: 2)
        panel.dismiss()
        pending?.resume(returning: [])
        await opening.value
        XCTAssertFalse(panel.isPaletteActive)
        XCTAssertEqual(panel.ownedMonitorCount, 0)
    }
}
