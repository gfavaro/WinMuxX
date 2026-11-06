@testable import AppBundle
import AppKit
import Common
import XCTest
import SwiftUI

@MainActor private final class OverviewPanelSpy: WorkspaceOverviewPresenting {
    var shown = false
    var focused = 0
    func present(key: Bool) { shown = true }
    func dismissOverview() { shown = false }
    func focusOverview() { focused += 1 }
}

/// Holds overview activations at their native await until the test releases them, in order.
@MainActor private final class SelectionGate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    var started: XCTestExpectation?
    func wait() async {
        await withCheckedContinuation { waiting.append($0); started?.fulfill(); started = nil }
    }
    func releaseFirst() { if !waiting.isEmpty { waiting.removeFirst().resume() } }
    func releaseAll() { while !waiting.isEmpty { waiting.removeFirst().resume() } }
}

@MainActor private final class InteractiveOverviewPanelSpy: WorkspaceOverviewPresenting {
    var initialProgress: Double?
    var updates: [Double] = []
    var settles: [Double] = []
    var dismissed = false
    func present(key: Bool) {}
    func present(key: Bool, gestureProgress: Double?) { initialProgress = gestureProgress }
    func updateGesture(progress: Double) { updates.append(progress) }
    func settleGesture(velocity: Double) { settles.append(velocity) }
    func dismissOverview() { dismissed = true }
}

@MainActor
private final class WeakOverviewModel {
    weak var value: WorkspaceOverviewDisplayModel?
    init(_ value: WorkspaceOverviewDisplayModel) { self.value = value }
}

@MainActor
private final class DeferredOverviewPanel: WorkspaceOverviewPresenting {
    var completion: (@MainActor () -> Void)?
    var closed = false
    func present(key: Bool) { closed = false }
    func dismissOverview() { closed = true }
    func dismissOverview(animated: Bool, completion: @escaping @MainActor () -> Void) {
        if animated { self.completion = completion }
        else { dismissOverview(); completion() }
    }
    func complete() { let callback = completion; completion = nil; callback?() }
}

private actor OverviewCaptureGate {
    var continuation: CheckedContinuation<CGImage, any Error>?
    var started: XCTestExpectation?
    var requests = 0
    func prepare(_ expectation: XCTestExpectation) { started = expectation }
    func render(_ request: WorkspaceSwipeSnapshotRequest) async throws -> CGImage {
        requests += 1
        return try await withCheckedThrowingContinuation {
            continuation = $0; started?.fulfill(); started = nil
        }
    }
    func finish(_ image: CGImage) { continuation?.resume(returning: image); continuation = nil }
    func cancel() { continuation?.resume(throwing: CancellationError()); continuation = nil }
}

@MainActor
final class WorkspaceOverviewTest: XCTestCase {
    func testAccessibilitySelectionAlwaysTargetsAnAvailableWorkspaceOrWindow() {
        let model = WorkspaceOverviewDisplayModel()
        model.cards = [card(1, windows: [window(1), window(2, frame: nil)]), card(2)]
        XCTAssertEqual(model.accessibilitySelection, .workspace(model.cards[0].id))
        model.cycleWindow(backward: false)
        XCTAssertEqual(model.selectedWindow, 2)
        XCTAssertEqual(model.accessibilitySelection, .workspace(model.cards[0].id))
        model.cycleWindow(backward: false)
        XCTAssertEqual(model.accessibilitySelection, .window(1))
        model.moveSelection(1)
        XCTAssertEqual(model.accessibilitySelection, .workspace(model.cards[1].id))
        model.cards = []
        XCTAssertNil(model.accessibilitySelection)
    }

    func testInteractiveOpeningReusesOneModelAndCancelledOpeningReleasesImages() async throws {
        let panel = InteractiveOverviewPanelSpy()
        var deps = dependencies(cards: [card()], image: try image())
        deps.makePanel = { _, _ in panel }
        let controller = WorkspaceOverviewController(dependencies: deps)
        XCTAssertTrue(controller.beginGesture(opening: true, progress: 0.2))
        XCTAssertEqual(panel.initialProgress, 0.2)
        await drain(controller)
        let model = try XCTUnwrap(controller.models.first)
        let bytes = controller.retainedImageBytes
        for step in 0..<1000 { controller.updateGesture(progress: Double(step % 100) / 100) }
        XCTAssertTrue(controller.models.first === model)
        XCTAssertEqual(controller.retainedImageBytes, bytes)
        XCTAssertGreaterThan(bytes, 0)
        controller.endGesture(commit: false, velocity: -1)
        XCTAssertEqual(controller.phase, .closed)
        XCTAssertTrue(panel.dismissed)
        XCTAssertTrue(model.images.isEmpty)
        XCTAssertTrue(controller.models.isEmpty)
    }

    func testCancelledDownwardGestureKeepsSessionAndCommittedDownwardGestureCloses() async throws {
        let panel = InteractiveOverviewPanelSpy()
        var deps = dependencies(cards: [card()], image: try image())
        deps.makePanel = { _, _ in panel }
        let controller = WorkspaceOverviewController(dependencies: deps)
        XCTAssertTrue(controller.show()); await drain(controller)
        let model = try XCTUnwrap(controller.models.first)
        XCTAssertTrue(controller.beginGesture(opening: false, progress: 0.2))
        XCTAssertEqual(panel.updates.last, 0.8)
        controller.updateGesture(progress: 0.1)
        XCTAssertEqual(panel.updates.last, 0.9)
        controller.endGesture(commit: false, velocity: -2)
        XCTAssertEqual(panel.settles, [2])
        XCTAssertTrue(controller.isOpen)
        XCTAssertTrue(controller.models.first === model)
        XCTAssertTrue(controller.beginGesture(opening: false, progress: 0.7))
        controller.endGesture(commit: true, velocity: 2)
        XCTAssertEqual(controller.phase, .closed)
        controller.endGesture(commit: false, velocity: 0)
        XCTAssertEqual(controller.phase, .closed)
    }
    private let identity = NSObject()
    private let monitor = MonitorViewportId(topLeftCorner: .zero)
    private func image(_ width: Int = 64, _ height: Int = 36) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
    private func window(_ id: UInt32 = 1, frame: CGRect? = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6)) -> WorkspaceOverviewWindow {
        .init(id: id, identity: ObjectIdentifier(identity), pid: 123, title: "Fixture", appName: "Test", icon: nil, frame: frame)
    }
    private func card(_ id: Int = 1, monitor: MonitorViewportId? = nil, windows: [WorkspaceOverviewWindow]? = nil) -> WorkspaceOverviewCard {
        .init(id: WorkspaceId("fixture-\(id)"), name: "fixture-\(id)", title: "Workspace \(id)", monitor: monitor ?? self.monitor,
              desktopSize: CGSize(width: 1920, height: 1080), windows: windows ?? [window(UInt32(id))])
    }
    private func dependencies(cards: [WorkspaceOverviewCard], image: CGImage) -> WorkspaceOverviewDependencies {
        let monitors = Array(Set(cards.map(\.monitor)))
        return .init(project: { .defaultProject }, displays: { monitors.map {
            .init(id: $0, name: "Test display", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        } }, cards: { _ in cards }, canShow: { true }, ranks: { _ in [:] }, render: { _ in image },
            makePanel: { _, _ in OverviewPanelSpy() }, activate: { _, _, _ in true })
    }
    private func drain(_ controller: WorkspaceOverviewController) async {
        guard let task = controller.task else { return }
        let complete = expectation(description: "Capture loop completes")
        Task { await task.value; complete.fulfill() }
        await fulfillment(of: [complete], timeout: 3)
    }

    func testNoDisplaysCannotOpenOrRetainPresentation() throws {
        var deps = dependencies(cards: [card()], image: try image())
        deps.displays = { [] }
        deps.makePanel = { _, _ in XCTFail("No display should create a panel"); return OverviewPanelSpy() }
        let controller = WorkspaceOverviewController(dependencies: deps)
        XCTAssertFalse(controller.show())
        XCTAssertTrue(controller.models.isEmpty)
        XCTAssertTrue(controller.panels.isEmpty)
        XCTAssertEqual(controller.phase, .closed)
    }

    func testDisconnectedDisplayIsRemovedOnReopening() async throws {
        var deps = dependencies(cards: [card()], image: try image())
        let first = deps.displays()[0]
        let other = WorkspaceOverviewDisplay(id: MonitorViewportId(topLeftCorner: CGPoint(x: 1920, y: 0)),
            name: "Other", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        var displays = [first, other]
        deps.displays = { displays }
        let controller = WorkspaceOverviewController(dependencies: deps)
        XCTAssertTrue(controller.show())
        await drain(controller)
        XCTAssertEqual(controller.models.compactMap(\.monitor), [first.id, other.id])
        controller.dismiss(animated: false)
        displays = [other]
        XCTAssertTrue(controller.show())
        await drain(controller)
        XCTAssertEqual(controller.models.compactMap(\.monitor), [other.id])
        XCTAssertEqual(controller.panels.count, 1)
        controller.dismiss(animated: false)
        XCTAssertTrue(controller.models.isEmpty)
        XCTAssertTrue(controller.panels.isEmpty)
    }

    func testReopeningCancelsRetiringPresentationAndIgnoresItsCompletion() async throws {
        var panels: [DeferredOverviewPanel] = []
        var deps = dependencies(cards: [card()], image: try image())
        deps.makePanel = { _, _ in let panel = DeferredOverviewPanel(); panels.append(panel); return panel }
        let controller = WorkspaceOverviewController(dependencies: deps)
        XCTAssertTrue(controller.show())
        await drain(controller)
        let retired = try XCTUnwrap(controller.models.first)
        controller.dismiss()
        XCTAssertEqual(controller.phase, .closing)
        XCTAssertFalse(retired.images.isEmpty)
        XCTAssertTrue(controller.show())
        XCTAssertTrue(retired.images.isEmpty)
        XCTAssertTrue(retired.cards.isEmpty)
        XCTAssertTrue(panels[0].closed)
        panels[0].complete()
        XCTAssertTrue(controller.isOpen)
        controller.dismiss(animated: false)
        XCTAssertEqual(controller.phase, .closed)
        XCTAssertTrue(controller.models.isEmpty)
    }
    func testRapidReopenKeepsOnlyOneRetiringModelAndReleasesAllOnImmediateClose() async throws {
        var panels: [DeferredOverviewPanel] = []
        var models: [WeakOverviewModel] = []
        var deps = dependencies(cards: [card()], image: try image())
        deps.makePanel = { _, _ in let panel = DeferredOverviewPanel(); panels.append(panel); return panel }
        let controller = WorkspaceOverviewController(dependencies: deps)
        for _ in 0..<30 {
            XCTAssertTrue(controller.show()); await drain(controller)
            models.append(WeakOverviewModel(try XCTUnwrap(controller.models.first)))
            controller.dismiss()
            XCTAssertEqual(models.filter { $0.value != nil }.count, 1)
            XCTAssertLessThanOrEqual(controller.retainedImageBytes, WorkspaceOverviewController.imageBudget)
        }
        controller.dismiss(animated: false)
        XCTAssertTrue(models.allSatisfy { $0.value == nil })
        for panel in panels { panel.complete() }
        XCTAssertEqual(controller.phase, .closed)
    }

    func testAnimatedCloseReleasesModelsOnCompletion() async throws {
        let panel = DeferredOverviewPanel()
        var deps = dependencies(cards: [card()], image: try image())
        deps.makePanel = { _, _ in panel }
        let controller = WorkspaceOverviewController(dependencies: deps)
        _ = controller.show(); await drain(controller)
        weak var model = controller.models.first
        controller.dismiss()
        XCTAssertNotNil(model)
        panel.complete()
        XCTAssertEqual(controller.phase, .closed)
        XCTAssertNil(model)
        XCTAssertEqual(controller.retainedImageBytes, 0)
    }

    func testCommandAndConfigParsing() {
        for (suffix, action) in [("", WorkspaceOverviewCmdArgs.Action.toggle), (" show", .show), (" hide", .hide), (" toggle", .toggle)] {
            let command = parseCommand("workspace-overview" + suffix).cmdOrDie
            XCTAssertTrue(command.isPresentation)
            XCTAssertFalse(command.shouldResetClosedWindowsCache)
            XCTAssertEqual((command as? WorkspaceOverviewCommand)?.args.action, action)
        }
        XCTAssertNotNil(parseCommand("workspace-overview invalid").errorOrNil)
        XCTAssertNotNil(parseCommand("workspace-overview show hide").errorOrNil)
        XCTAssertFalse(Config().workspaceOverview.threeFingerUp)
        let parsed = parseConfig("config-version = 2\n[workspace-overview]\nthree-finger-up = true")
        XCTAssertTrue(parsed.errors.isEmpty)
        XCTAssertTrue(parsed.config.workspaceOverview.threeFingerUp)
        XCTAssertFalse(parseConfig("[workspace-overview]\nthree-finger-up = 1").errors.isEmpty)
        XCTAssertFalse(parseConfig("[workspace-overview]\nunknown = true").errors.isEmpty)
    }

    func testEligibilityExcludesEveryUnwantedNativeState() {
        XCTAssertTrue(workspaceOverviewIncludesWindow(standard: true, minimized: false, hiddenApp: false, fullscreen: false, popup: false, ownWindow: false, activeTab: true))
        for index in 0..<7 {
            XCTAssertFalse(workspaceOverviewIncludesWindow(standard: index != 0, minimized: index == 1,
                hiddenApp: index == 2, fullscreen: index == 3, popup: index == 4, ownWindow: index == 5, activeTab: index != 6))
        }
    }

    func testGeometryRetainsNegativeOriginsAndClipsHitTesting() {
        let frame = normalizedWorkspacePreviewFrame(CGRect(x: -1820, y: -300, width: 960, height: 540),
            origin: CGPoint(x: -1920, y: -400), desktopSize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(frame?.minX ?? -1, 100.0 / 1920, accuracy: 0.00001)
        XCTAssertEqual(frame?.minY ?? -1, 100.0 / 1080, accuracy: 0.00001)
        XCTAssertEqual(frame?.width, 0.5)
        XCTAssertNil(normalizedWorkspacePreviewFrame(CGRect(x: CGFloat.nan, y: 0, width: 20, height: 20), origin: .zero, desktopSize: CGSize(width: 100, height: 100)))
        XCTAssertNil(normalizedWorkspacePreviewFrame(.zero, origin: .zero, desktopSize: .zero))
        let back = window(1, frame: CGRect(x: -0.1, y: 0, width: 0.8, height: 0.8))
        let front = window(2, frame: CGRect(x: 0.2, y: 0.2, width: 0.8, height: 0.8))
    }

    func testPaginationAndKeyboardNavigation() {
        let model = WorkspaceOverviewDisplayModel()
        model.cards = (1...25).map { card($0) }
        XCTAssertEqual(model.visibleCards.count, 12)
        model.moveSelection(13)
        XCTAssertEqual(model.page, 1)
        XCTAssertEqual(model.selectedCard?.id, WorkspaceId("fixture-14"))
        model.changePage(1)
        XCTAssertEqual(model.visibleCards.count, 1)
        model.changePage(1)
        XCTAssertEqual(model.page, 2)
        model.cards = [card(windows: [window(1), window(2)])]; model.selection = 0
        model.cycleWindow(backward: false); XCTAssertEqual(model.selectedWindow, 2)
        model.cycleWindow(backward: false); XCTAssertEqual(model.selectedWindow, 1)
        model.cycleWindow(backward: true); XCTAssertEqual(model.selectedWindow, 2)
        var result: UInt32?
        model.activate = { _, window in result = window }
        model.activateSelection(); XCTAssertEqual(result, 2)
    }

    func testOneCapturePerVisibleCardAndNoRecaptureWhileStationary() async throws {
        let picture = try image()
        var deps = dependencies(cards: (1...20).map { card($0) }, image: picture)
        let requests = OverviewRequestRecorder()
        deps.render = { request in await requests.record(request); return picture }
        let controller = WorkspaceOverviewController(dependencies: deps)
        defer { controller.dismiss() }
        XCTAssertTrue(controller.show()); XCTAssertTrue(controller.show())
        await drain(controller)
        let count12 = await requests.count(); XCTAssertEqual(count12, 12)
        controller.modelDidChange(); await drain(controller)
        let countStill12 = await requests.count(); XCTAssertEqual(countStill12, 12)
        controller.models[0].changePage(1); await drain(controller)
        let count20 = await requests.count(); XCTAssertEqual(count20, 20)
        controller.models[0].changePage(-1); await drain(controller)
        let countStill20 = await requests.count(); XCTAssertEqual(countStill20, 20)
        XCTAssertTrue(controller.models[0].images.isEmpty, "Evicted first-page images use placeholders on revisit")
        controller.dismiss(); XCTAssertEqual(controller.retainedImageBytes, 0)
        XCTAssertTrue(controller.models.isEmpty)
    }

    func testCancelledNativeCaptureCannotPublishIntoReopenedSession() async throws {
        let picture = try image()
        let gate = OverviewCaptureGate()
        addTeardownBlock { await gate.cancel() }
        var deps = dependencies(cards: [card()], image: picture)
        deps.render = { try await gate.render($0) }
        let first = expectation(description: "First capture")
        await gate.prepare(first)
        let controller = WorkspaceOverviewController(dependencies: deps)
        defer { controller.dismiss() }
        XCTAssertTrue(controller.show())
        await fulfillment(of: [first], timeout: 2)
        let oldTask = controller.task
        controller.dismiss(); XCTAssertTrue(controller.show())
        let heldCount = await gate.requests
        XCTAssertEqual(heldCount, 1, "Reopening cannot start another capture while native work is held")
        let second = expectation(description: "Replacement capture")
        await gate.prepare(second); await gate.finish(picture)
        await oldTask?.value
        await fulfillment(of: [second], timeout: 2)
        XCTAssertEqual(controller.retainedImageBytes, 0)
        await gate.finish(picture); await drain(controller)
        XCTAssertGreaterThan(controller.retainedImageBytes, 0)
    }

    func testInvalidationDropsPixelsAndRejectsInFlightResult() async throws {
        let picture = try image()
        let gate = OverviewCaptureGate()
        addTeardownBlock { await gate.cancel() }
        var cards = [card()]
        var deps = dependencies(cards: cards, image: picture)
        deps.cards = { _ in cards }; deps.render = { try await gate.render($0) }
        let started = expectation(description: "Held capture")
        await gate.prepare(started)
        let controller = WorkspaceOverviewController(dependencies: deps)
        defer { controller.dismiss() }
        XCTAssertTrue(controller.show()); await fulfillment(of: [started], timeout: 2)
        controller.nativeWindowChanged(1)
        cards[0].windows = []
        controller.modelDidChange()
        await gate.finish(picture); await drain(controller)
        XCTAssertEqual(controller.retainedImageBytes, 0)
        XCTAssertTrue(controller.models[0].cards[0].windows.isEmpty)
    }

    func testModelReorderingPreservesSelectionAndReusedIDsClearWindowSelection() async throws {
        let picture = try image()
        var cards = [card(1), card(2), card(3), card(4)]
        var deps = dependencies(cards: cards, image: picture)
        deps.cards = { _ in cards }
        let controller = WorkspaceOverviewController(dependencies: deps)
        defer { controller.dismiss() }
        XCTAssertTrue(controller.show()); await drain(controller)
        let model = try XCTUnwrap(controller.models.first)
        model.moveSelection(1); model.cycleWindow(backward: false)
        XCTAssertEqual(model.selectedWindow, 2)
        cards.reverse(); controller.modelDidChange()
        XCTAssertEqual(model.selectedCard?.id, WorkspaceId("fixture-2"))
        XCTAssertEqual(model.selectedWindow, 2)
        XCTAssertEqual(model.selection, 2)
        let other = NSObject()
        let prior = cards[2].windows[0]
        cards[2].windows[0] = .init(id: prior.id, identity: ObjectIdentifier(other), pid: prior.pid,
            title: prior.title, appName: prior.appName, icon: nil, frame: prior.frame)
        controller.modelDidChange()
        XCTAssertNil(model.selectedWindow)
        XCTAssertNil(model.images[cards[2].id])
    }

    func testAllDisplaysShareOneImageBudget() async throws {
        let picture = try image(640, 360)
        let cards = (0..<84).map { i in card(i + 1, monitor: MonitorViewportId(topLeftCorner: CGPoint(x: (i / 12) * 1920, y: 0))) }
        let controller = WorkspaceOverviewController(dependencies: dependencies(cards: cards, image: picture))
        defer { controller.dismiss() }
        XCTAssertTrue(controller.show()); await drain(controller)
        XCTAssertEqual(controller.models.count, 7)
        XCTAssertGreaterThan(controller.retainedImageBytes, 31 * 1024 * 1024)
        XCTAssertLessThanOrEqual(controller.retainedImageBytes, WorkspaceOverviewController.imageBudget)
    }

    func testThousandSessionsReleasePanelsAndModels() async throws {
        let picture = try image()
        var deps = dependencies(cards: [card(windows: [])], image: picture)
        weak var panel: OverviewPanelSpy?
        deps.makePanel = { _, _ in let next = OverviewPanelSpy(); panel = next; return next }
        let controller = WorkspaceOverviewController(dependencies: deps)
        for _ in 0..<1000 {
            XCTAssertTrue(controller.show())
            weak var model = controller.models.first
            await drain(controller)
            controller.dismiss()
            XCTAssertNil(panel); XCTAssertNil(model)
            XCTAssertEqual(controller.retainedImageBytes, 0)
        }
    }

    func testProjectChangeAndIneligibleEnvironmentDismiss() async throws {
        let picture = try image()
        var project: WorkspaceProjectId = .defaultProject
        var eligible = true
        var deps = dependencies(cards: [card()], image: picture)
        deps.project = { project }; deps.canShow = { eligible }
        let controller = WorkspaceOverviewController(dependencies: deps)
        defer { controller.dismiss() }
        XCTAssertTrue(controller.show()); await drain(controller)
        project = "other"; controller.modelDidChange(); XCTAssertFalse(controller.isOpen)
        eligible = false; XCTAssertFalse(controller.show())
    }


    func testControllerReusesHostingSurfaceAndClearsSessionState() async throws {
        let picture = try image()
        var deps = dependencies(cards: [card()], image: picture)
        var creations = 0
        deps.makePanel = { model, display in
            creations += 1
            return WorkspaceOverviewPanel(model: model, monitorName: display.name,
                frame: CGRect(x: -20000, y: -20000, width: 800, height: 600))
        }
        let controller = WorkspaceOverviewController(dependencies: deps)
        defer { controller.invalidate() }
        XCTAssertTrue(controller.show())
        await drain(controller)
        let panel = try XCTUnwrap(controller.panels.first as? WorkspaceOverviewPanel)
        let hosting = try XCTUnwrap(panel.contentView)
        let model = panel.model
        XCTAssertFalse(model.images.isEmpty)
        model.selectedWindow = 1
        controller.dismiss(animated: false)
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(model.images.isEmpty)
        XCTAssertFalse(model.cards.isEmpty, "The reused panel keeps its card views for the next opening")
        XCTAssertNil(model.selectedWindow)
        XCTAssertNil(model.activate)
        XCTAssertTrue(controller.show(gestureProgress: 0.3))
        XCTAssertEqual(creations, 1)
        XCTAssertTrue(controller.panels.first === panel)
        XCTAssertTrue(panel.contentView === hosting)
        XCTAssertNotNil(model.activate)
        controller.invalidate()
        XCTAssertNil(panel.contentView)
        XCTAssertFalse(panel.isVisible)
        XCTAssertTrue(controller.show())
        XCTAssertEqual(creations, 2)
    }

    func testSyntheticOverviewRendersAndNativePanelsRelease() throws {
        let picture = try image(640, 360)
        let model = WorkspaceOverviewDisplayModel()
        model.cards = (1...6).map { i in
            card(i, windows: [window(UInt32(i * 10), frame: CGRect(x: 0.03, y: 0.05, width: 0.6, height: 0.9)),
                              window(UInt32(i * 10 + 1), frame: CGRect(x: 0.55, y: 0.15, width: 0.42, height: 0.7))])
        }
        let renderer = ImageRenderer(content: WorkspaceOverviewView(model: model, monitorName: "Synthetic display")
            // ImageRenderer cannot draw native visual-effect views. Exercise the
            // real opaque accessibility fallback instead of rendering an unsupported-view glyph.
            .environment(\.workspaceSidebarPreviewAccessibility, .init(reduceTransparency: true))
            .frame(width: 1280, height: 850))
        renderer.proposedSize = .init(width: 1280, height: 850)
        let rendered = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(rendered.width, 1280)
        let output = projectRoot.appending(path: ".build/workspace-overview-fixture.png")
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]))
        try data.write(to: output)
        for _ in 0..<20 {
            weak var released: WorkspaceOverviewPanel?
            autoreleasepool {
                let panel = WorkspaceOverviewPanel(model: model, monitorName: "Synthetic display",
                    frame: CGRect(x: -20000, y: -20000, width: 1280, height: 850))
                released = panel
                model.images[model.cards[0].id] = picture
                panel.dismissOverview()
                model.images.removeAll()
                XCTAssertNil(panel.contentView)
                XCTAssertFalse(panel.isVisible)
            }
            XCTAssertNil(released)
        }
    }

    func testPendingSelectionCannotActivateAfterLifecycleInvalidation() async throws {
        let gate = SelectionGate()
        addTeardownBlock { await gate.releaseAll() }
        var results: [Bool] = []
        var finished: XCTestExpectation?
        var deps = dependencies(cards: [card(1), card(2)], image: try image())
        deps.activate = { _, _, isCurrent in
            await gate.wait()
            results.append(isCurrent())
            finished?.fulfill(); finished = nil
            return results.last!
        }
        let controller = WorkspaceOverviewController(dependencies: deps)
        // Waits until the released activation has recorded its result, however busy the runner is.
        func releaseAndFinish() async {
            let done = expectation(description: "Activation finishes")
            finished = done
            gate.releaseFirst()
            await fulfillment(of: [done], timeout: 2)
        }
        func selectAndHold() async {
            XCTAssertTrue(controller.show()); await drain(controller)
            let started = expectation(description: "Activation awaits native work")
            gate.started = started
            controller.models[0].activateSelection()
            await fulfillment(of: [started], timeout: 2)
        }

        // Another app, Space or display change arrives while native work is pending.
        await selectAndHold()
        XCTAssertFalse(controller.show(), "A pending selection keeps the overview closed")
        controller.cancelPendingSelection()
        await releaseAndFinish()
        XCTAssertEqual(results, [false], "The invalidated selection must not activate")

        // A stale completion must neither activate nor clear a newer selection.
        await selectAndHold()
        controller.cancelPendingSelection()
        await selectAndHold()
        await releaseAndFinish()
        XCTAssertEqual(results, [false, false])
        XCTAssertFalse(controller.show(), "The replacement selection is still pending")
        await releaseAndFinish()
        XCTAssertEqual(results, [false, false, true])

        // An explicit hide (command, gesture, Mission Control, palette) after selecting supersedes it.
        await selectAndHold()
        controller.dismiss()
        await releaseAndFinish()
        XCTAssertEqual(results, [false, false, true, false])
        XCTAssertTrue(controller.show())
        controller.dismiss()
    }

    func testReopenBeforeCaptureTaskRunsStillCapturesTheNewSession() async throws {
        let controller = WorkspaceOverviewController(dependencies: dependencies(cards: [card(1), card(2)], image: try image()))
        defer { controller.dismiss() }
        // No suspension between these calls: the first capture task has not started yet.
        XCTAssertTrue(controller.show())
        controller.dismiss()
        XCTAssertTrue(controller.show())
        await controller.task?.value
        await drain(controller)
        XCTAssertEqual(controller.models[0].images.count, 2)
    }

    func testModelChangeAcrossAPageCapturesTheNewPageAndEvictsTheOld() async throws {
        let picture = try image()
        var cards = (1...14).map { card($0) }
        var deps = dependencies(cards: cards, image: picture)
        deps.cards = { _ in cards }
        deps.displays = { [.init(id: self.monitor, name: "Test display", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                activeWorkspace: WorkspaceId("fixture-13"))] }
        let controller = WorkspaceOverviewController(dependencies: deps)
        defer { controller.dismiss() }
        XCTAssertTrue(controller.show()); await drain(controller)
        let model = try XCTUnwrap(controller.models.first)
        XCTAssertEqual(model.page, 1)

        cards.removeFirst(); controller.modelDidChange(); await drain(controller)
        XCTAssertEqual(model.page, 0)
        XCTAssertEqual(model.selectedCard?.id, WorkspaceId("fixture-13"))
        XCTAssertEqual(Set(model.images.keys), Set(model.visibleCards.map(\.id)))
        XCTAssertNil(model.images[WorkspaceId("fixture-14")], "Off-page pixels are evicted")
    }

    func testBracketsMoveKeyboardAndAccessibilityFocusBetweenDisplays() async throws {
        XCTAssertEqual(workspaceOverviewKeyAction(keyCode: 33, modifiers: [], hasMarkedText: false, characters: "["), .display(-1))
        XCTAssertEqual(workspaceOverviewKeyAction(keyCode: 30, modifiers: [], hasMarkedText: false, characters: "]"), .display(1))
        // Layout-independent: the character decides, not the physical key.
        XCTAssertEqual(workspaceOverviewKeyAction(keyCode: 0, modifiers: [], hasMarkedText: false, characters: "]"), .display(1))
        for modifiers: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
            XCTAssertNil(workspaceOverviewKeyAction(keyCode: 30, modifiers: modifiers, hasMarkedText: false, characters: "]"))
        }
        XCTAssertNil(workspaceOverviewKeyAction(keyCode: 30, modifiers: [], hasMarkedText: true, characters: "]"))

        let second = MonitorViewportId(topLeftCorner: CGPoint(x: 1920, y: 0))
        var panels: [OverviewPanelSpy] = []
        var deps = dependencies(cards: [card(1), card(2, monitor: second)], image: try image())
        deps.displays = { [self.monitor, second].map { .init(id: $0, name: "Display", frame: .zero) } }
        deps.makePanel = { _, _ in let panel = OverviewPanelSpy(); panels.append(panel); return panel }
        let controller = WorkspaceOverviewController(dependencies: deps)
        defer { controller.dismiss() }
        XCTAssertTrue(controller.show())
        XCTAssertTrue(controller.models.allSatisfy(\.canSwitchDisplay))
        controller.models[0].switchDisplay?(1)
        XCTAssertEqual(panels.map(\.focused), [0, 1])
        XCTAssertEqual(controller.models.map(\.focusRequest), [0, 1])
        controller.models[0].switchDisplay?(-1) // Wraps to the other display.
        XCTAssertEqual(panels.map(\.focused), [0, 2])
        controller.dismiss()
        XCTAssertTrue(controller.show(), "Reopening after a two-display session works")
        controller.dismiss()

        let single = WorkspaceOverviewController(dependencies: dependencies(cards: [card()], image: try image()))
        XCTAssertTrue(single.show())
        XCTAssertFalse(single.models[0].canSwitchDisplay)
        single.dismiss()
    }

    func testAccessibilityFocusDrivesTheSelectionThatReturnActivates() {
        let model = WorkspaceOverviewDisplayModel()
        model.cards = [card(1, windows: [window(1)]), card(2, windows: [window(2)])]
        var activated: (WorkspaceId, UInt32?)?
        model.activate = { activated = ($0, $1) }

        model.syncAccessibilityFocus(.window(2))
        XCTAssertEqual(model.selection, 1); XCTAssertEqual(model.selectedWindow, 2)
        model.activateSelection()
        XCTAssertEqual(activated?.0, WorkspaceId("fixture-2")); XCTAssertEqual(activated?.1, 2)

        model.syncAccessibilityFocus(.workspace(WorkspaceId("fixture-1")))
        XCTAssertEqual(model.selection, 0); XCTAssertNil(model.selectedWindow)
        model.syncAccessibilityFocus(nil) // Focus left the overview: keep the selection.
        XCTAssertEqual(model.selection, 0)

        model.cards = (1...13).map { card($0) }
        model.syncAccessibilityFocus(.window(13)) // Not on the visible page, so not focusable.
        XCTAssertEqual(model.selection, 0); XCTAssertNil(model.selectedWindow)
    }

    func testGridScrollsWhenThreeRowsCannotFit() {
        let small = WorkspaceOverviewGridMetrics(availableHeight: 450)
        XCTAssertTrue(small.scrolls)
        XCTAssertEqual(small.cardHeight, WorkspaceOverviewGridMetrics.minimumCardHeight)
        let regular = WorkspaceOverviewGridMetrics(availableHeight: 850)
        XCTAssertFalse(regular.scrolls)
        XCTAssertEqual(regular.cardHeight, (850 - 200) / 3 - 48, accuracy: 0.001)
        // Three rows plus captions and spacing stay inside the space left for the grid.
        XCTAssertLessThanOrEqual(3 * (regular.cardHeight + 48) + 2 * 18, 850 - 164)
    }

    func testRendererDownsamplesWithoutScreenCapture() async throws {
        let key = WorkspaceSwipeSnapshotKey(workspace: WorkspaceId("synthetic"), display: "test", rect: CGRect(x: 0, y: 0, width: 5120, height: 2880))
        var request = WorkspaceSwipeSnapshotRequest(key: key, windows: [.init(id: 0, frame: CGRect(x: 0, y: 0, width: 5120, height: 2880))])
        request.maximumPixelSize = CGSize(width: 640, height: 360)
        request.windowsAreBackToFront = true; request.allowCapture = false
        let result = try await WorkspaceSwipeSnapshotRenderer.shared.render(request)
        XCTAssertEqual(result.image.width, 640); XCTAssertEqual(result.image.height, 360)
        XCTAssertFalse(result.renderedOnMainThread)
    }
}

private actor OverviewRequestRecorder {
    private var requests: [WorkspaceSwipeSnapshotRequest] = []
    func record(_ request: WorkspaceSwipeSnapshotRequest) { requests.append(request) }
    func count() -> Int { requests.count }
}
