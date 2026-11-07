import AppKit

enum MouseManipulationKind: Equatable {
    case none
    case move
    case resize
}

/// What the pointer is doing to a window: nothing, moving it (what it carries, and where the
/// drag began), or resizing it. One value, so the window, the kind and a move's details can never
/// disagree, and ending a manipulation is one assignment.
enum MouseManipulation: Equatable {
    case none
    case move(WindowMouseInteractionDriver.MoveSession)
    case resize(windowId: UInt32)

    var windowId: UInt32? {
        switch self {
            case .none: nil
            case .move(let session): session.windowId
            case .resize(let windowId): windowId
        }
    }

    var kind: MouseManipulationKind {
        switch self {
            case .none: .none
            case .move: .move
            case .resize: .resize
        }
    }

    var moveSession: WindowMouseInteractionDriver.MoveSession? {
        if case .move(let session) = self { session } else { nil }
    }
}

private let postDragAxObserverSuppressionDuration: Duration = .seconds(2)

struct MousePointerSample: Equatable {
    let point: CGPoint
    let timestamp: TimeInterval
}

@MainActor
final class MousePointerTracker {
    static let shared = MousePointerTracker()

    private var latestSample: MousePointerSample?

    private init() {}

    var currentSample: MousePointerSample {
        latestSample ?? MousePointerSample(point: mouseLocation, timestamp: ProcessInfo.processInfo.systemUptime)
    }

    func note(event: NSEvent) {
        latestSample = MousePointerSample(
            point: normalizedScreenPoint(for: event),
            timestamp: event.timestamp,
        )
    }

    func note(point: CGPoint, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        latestSample = MousePointerSample(point: point, timestamp: timestamp)
    }

    func reset() {
        latestSample = nil
    }

    private func normalizedScreenPoint(for event: NSEvent) -> CGPoint {
        let screenPoint = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? NSEvent.mouseLocation
        return normalizeAppKitScreenPoint(screenPoint)
    }
}

@MainActor var currentMouseManipulation: MouseManipulation = .none
@MainActor var currentlyManipulatedWithMouseWindowId: UInt32? { currentMouseManipulation.windowId }
@MainActor private var pinnedDraggedWindowId: UInt32? = nil
@MainActor var isMouseManipulationActive: Bool { currentMouseManipulation != .none }
@MainActor private var draggedWindowAnchorRectById: [UInt32: Rect] = [:]
@MainActor private var suppressedPostDragAxObserverEventsUntil: ContinuousClock.Instant? = nil
@MainActor private var suppressedPostDragAxObserverEventsByWindowId: [UInt32: ContinuousClock.Instant] = [:]

func isLeftMouseButtonPressed(mask: Int) -> Bool {
    (mask & 0x1) != 0
}

var isLeftMouseButtonDown: Bool { isLeftMouseButtonPressed(mask: NSEvent.pressedMouseButtons) }

@MainActor
func setPinnedDraggedWindowId(_ windowId: UInt32?) {
    pinnedDraggedWindowId = windowId
}

@MainActor
func isPinnedDraggedWindow(_ windowId: UInt32) -> Bool {
    pinnedDraggedWindowId == windowId
}

@MainActor
func hasPinnedDraggedWindow() -> Bool {
    pinnedDraggedWindowId != nil
}

@MainActor
func getCurrentMouseDragSubject() -> WindowDragSubject {
    currentMouseManipulation.moveSession?.subject ?? .window
}

@MainActor
func getCurrentMouseTabDetachOrigin() -> TabDetachOrigin {
    currentMouseManipulation.moveSession?.detachOrigin ?? .window
}

@MainActor
func getCurrentMouseDragStartedInSidebar() -> Bool {
    currentMouseManipulation.moveSession?.startedInSidebar ?? false
}

@MainActor
func getCurrentMouseManipulationKind() -> MouseManipulationKind {
    currentMouseManipulation.kind
}

/// The pointer is resizing `windowId`, whatever it was doing before.
@MainActor
func beginMouseResizeManipulation(windowId: UInt32) {
    currentMouseManipulation = .resize(windowId: windowId)
}

@MainActor
func setDraggedWindowAnchorRect(_ rect: Rect?, for windowId: UInt32) {
    if let rect {
        draggedWindowAnchorRectById[windowId] = rect
    } else {
        draggedWindowAnchorRectById.removeValue(forKey: windowId)
    }
}

@MainActor
func draggedWindowAnchorRect(for windowId: UInt32) -> Rect? {
    draggedWindowAnchorRectById[windowId]
}

@MainActor
func clearDraggedWindowAnchorRect(for windowId: UInt32?) {
    guard let windowId else { return }
    draggedWindowAnchorRectById.removeValue(forKey: windowId)
}

@MainActor
func resolvedDraggedWindowAnchorRect(for window: Window, subject: WindowDragSubject) -> Rect? {
    switch subject {
        case .window:
            window.lastAppliedLayoutPhysicalRect ?? window.moveNode.lastAppliedLayoutPhysicalRect
        case .group:
            window.moveNode.lastAppliedLayoutPhysicalRect ?? window.lastAppliedLayoutPhysicalRect
    }
}

func currentSessionModifierFlags() -> CGEventFlags {
    CGEventSource.flagsState(.combinedSessionState)
}

func shouldPromoteWindowDragToTabGroupDrag(isOptionPressed: Bool, isTabbedWindow: Bool) -> Bool {
    isOptionPressed && isTabbedWindow
}

func shouldAllowSameWorkspaceWindowSurfaceIntent(
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    isOptionPressed _: Bool,
) -> Bool {
    if detachOrigin == .tabStrip {
        return true
    }
    return true
}

@MainActor
func isWindowInDraggableTabGroup(_ window: Window) -> Bool {
    guard let parent = window.parent as? TilingContainer else { return false }
    return parent.layout == .tabGroup && parent.children.count > 1
}

@MainActor
func shouldContinueCurrentGroupDrag(windowId: UInt32) -> Bool {
    getCurrentMouseManipulationKind() == .move &&
        currentlyManipulatedWithMouseWindowId == windowId &&
        getCurrentMouseDragSubject() == .group
}

@MainActor
func resolvedMouseDragSubject(for window: Window) -> WindowDragSubject {
    if shouldContinueCurrentGroupDrag(windowId: window.windowId) {
        return .group
    }
    let isOptionPressed = currentSessionModifierFlags().contains(.maskAlternate)
    return shouldPromoteWindowDragToTabGroupDrag(
        isOptionPressed: isOptionPressed,
        isTabbedWindow: isWindowInDraggableTabGroup(window),
    ) ? .group : .window
}

@MainActor
@discardableResult
func beginWindowMoveWithMouseSessionIfNeeded(
    windowId: UInt32,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    startedInSidebar: Bool,
    anchorRect: Rect?,
    refreshActualRects: Bool = true,
) -> Bool {
    let previousWindowId = currentlyManipulatedWithMouseWindowId
    let move = MouseManipulation.move(WindowMouseInteractionDriver.MoveSession(
        windowId: windowId, subject: subject, detachOrigin: detachOrigin, startedInSidebar: startedInSidebar))

    if currentMouseManipulation == move {
        return false
    }

    if previousWindowId != windowId {
        clearDraggedWindowAnchorRect(for: previousWindowId)
        if let previousWindowId {
            WindowDragFrameGate.shared.reset(windowId: previousWindowId)
        }
    }

    currentMouseManipulation = move
    setDraggedWindowAnchorRect(anchorRect, for: windowId)
    if refreshActualRects {
        refreshVisibleWindowActualRectsForCurrentDrag(sourceWindowId: windowId)
    } else {
        cancelWindowDragActualRectRefresh()
    }
    return true
}

@MainActor
func cancelManipulatedWithMouseState() {
    WindowMouseInteractionDriver.shared.stop()
    cancelWindowDragActualRectRefresh()
    clearDraggedWindowAnchorRect(for: currentlyManipulatedWithMouseWindowId)
    WindowDragFrameGate.shared.resetAll()
    currentMouseManipulation = .none
    for workspace in Workspace.all {
        workspace.resetResizeWeightBeforeResizeRecursive()
    }
}

@MainActor
func suppressPostDragAxObserverEvents(for windowIds: some Sequence<UInt32>) {
    let suppressionDeadline = ContinuousClock.now + postDragAxObserverSuppressionDuration
    for windowId in windowIds {
        suppressedPostDragAxObserverEventsByWindowId[windowId] = suppressionDeadline
    }
}

@MainActor
func armGlobalPostDragAxObserverSuppression() {
    suppressedPostDragAxObserverEventsUntil = ContinuousClock.now + postDragAxObserverSuppressionDuration
}

@MainActor
private func hasActiveGlobalPostDragAxObserverSuppression() -> Bool {
    guard let suppressionDeadline = suppressedPostDragAxObserverEventsUntil else { return false }
    if suppressionDeadline > ContinuousClock.now {
        return true
    }
    suppressedPostDragAxObserverEventsUntil = nil
    return false
}

@MainActor
private func hasActivePostDragAxObserverSuppression(for windowId: UInt32) -> Bool {
    guard let suppressionDeadline = suppressedPostDragAxObserverEventsByWindowId[windowId] else { return false }
    if suppressionDeadline > ContinuousClock.now {
        return true
    }
    suppressedPostDragAxObserverEventsByWindowId.removeValue(forKey: windowId)
    return false
}

@MainActor
func shouldIgnoreAxObserverEventForPostDragSuppression(windowId: UInt32?, notif: String) -> Bool {
    guard notif == kAXMovedNotification as String || notif == kAXResizedNotification as String else { return false }
    guard !isLeftMouseButtonDown else { return false }
    if hasActiveGlobalPostDragAxObserverSuppression() {
        debugLog(.focus, "axObserver.suppressed.global notif=\(notif) window=\(String(describing: windowId))")
        return true
    }
    guard let windowId else { return false }
    let shouldSuppress = hasActivePostDragAxObserverSuppression(for: windowId)
    if shouldSuppress {
        debugLog(.focus, "axObserver.suppressed window=\(windowId) notif=\(notif)")
    }
    return shouldSuppress
}

@MainActor
func isManipulatedWithMouse(_ window: Window) async throws -> Bool {
    try await (!window.isHiddenInCorner && // Don't allow to resize/move windows of hidden workspaces
        isLeftMouseButtonDown &&
        (currentlyManipulatedWithMouseWindowId == nil || window.windowId == currentlyManipulatedWithMouseWindowId))
        .andAsync { @Sendable @MainActor in try await getNativeFocusedWindow() == window }
}

func shouldIgnoreMovedObsForManagedWindowDragSession(
    observedWindowId: UInt32?,
    currentWindowId: UInt32?,
    kind: MouseManipulationKind,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
    startedInSidebar: Bool,
) -> Bool {
    guard kind == .move,
          observedWindowId != nil,
          observedWindowId == currentWindowId
    else { return false }
    return startedInSidebar || detachOrigin == .tabStrip || subject == .group
}

func shouldIgnoreWindowTabStripMouseEventsDuringDrag(detachOrigin: TabDetachOrigin) -> Bool {
    detachOrigin != .tabStrip
}

@MainActor
func shouldIgnoreMovedObsForCurrentDragSession(windowId: UInt32?) -> Bool {
    shouldIgnoreMovedObsForManagedWindowDragSession(
        observedWindowId: windowId,
        currentWindowId: currentlyManipulatedWithMouseWindowId,
        kind: getCurrentMouseManipulationKind(),
        subject: getCurrentMouseDragSubject(),
        detachOrigin: getCurrentMouseTabDetachOrigin(),
        startedInSidebar: getCurrentMouseDragStartedInSidebar(),
    )
}

/// A kAXMoved for the window that a driver session already owns adds no information:
/// - During a move session the display loop renders every frame; re-entering moveWithMouse per
///   event just queues redundant light sessions (each with an AX focused-window round-trip).
///   The only per-event effect worth keeping is drag-subject promotion (Option pressed
///   mid-drag turns a window drag into a group drag), so the event is NOT skipped when the
///   resolved subject differs from the session's.
/// - During a resize session, kAXMoved is a byproduct of resizing from the left/top edge.
///   Re-entering moveWithMouse from it would flip the resize into a move session mid-gesture
///   (hiding the resize preview and starting drag-intent tracking).
@MainActor
func isContinuingManagedDragSessionForMovedEvent(_ window: Window) -> Bool {
    guard isLeftMouseButtonDown, currentlyManipulatedWithMouseWindowId == window.windowId else { return false }
    switch getCurrentMouseManipulationKind() {
        case .resize:
            return WindowMouseInteractionDriver.shared.resizeSession?.windowId == window.windowId
        case .move:
            guard WindowMouseInteractionDriver.shared.moveSession?.windowId == window.windowId else { return false }
            return resolvedMouseDragSubject(for: window) == getCurrentMouseDragSubject()
        case .none:
            return false
    }
}

/// Symmetric to isContinuingManagedDragSessionForMovedEvent: a kAXResized for the window a
/// driver session already owns is either the resize itself (the display loop samples it at
/// display rate) or a byproduct of a move session and must not restart startResize per event.
@MainActor
func isContinuingManagedDragSessionForResizedEvent(_ windowId: UInt32) -> Bool {
    guard isLeftMouseButtonDown, currentlyManipulatedWithMouseWindowId == windowId else { return false }
    switch getCurrentMouseManipulationKind() {
        case .resize:
            return WindowMouseInteractionDriver.shared.resizeSession?.windowId == windowId
        case .move:
            return WindowMouseInteractionDriver.shared.moveSession?.windowId == windowId
        case .none:
            return false
    }
}

/// Same motivation as in monitorFrameNormalized
var mouseLocation: CGPoint {
    normalizeAppKitScreenPoint(NSEvent.mouseLocation)
}

@MainActor
func noteCurrentMousePointerSample(timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    MousePointerTracker.shared.note(point: mouseLocation, timestamp: timestamp)
}

func normalizeAppKitScreenPoint(_ point: CGPoint) -> CGPoint {
    point.copy(\.y, mainMonitor.height - point.y)
}
