import AppKit

/// Reads the current frame first and returns before the AXEnhancedUserInterface round-trip when
/// the frame already matches: layout re-asserts frames constantly and the vast majority of these
/// calls are no-ops, so the no-op path must not pay the disableAnimations read.
func setFrame(_ window: any AxUiElementMock, app: any AxUiElementMock, _ topLeft: CGPoint?, _ size: CGSize?, _ job: RunLoopJob, positionFirst: Bool = false, traceWindowId: UInt32? = nil) throws {
    let topLeft = topLeft.map { CGPoint(x: $0.x.rounded(), y: $0.y.rounded()) }
    let size = size.map { CGSize(width: $0.width.rounded(), height: $0.height.rounded()) }
    func trace(_ stage: String, accepted: Bool? = nil) {
        guard WorkspaceFrameWriteDiagnostics.enabled, let id = traceWindowId else { return }
        WorkspaceFrameWriteDiagnostics.record(stage, id: id, window: window.cast, positionFirst: positionFirst,
            requestedPosition: topLeft, requestedSize: size, accepted: accepted)
    }
    func write<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T, stage: String) {
        trace("\(stage)-begin")
        let accepted = window.set(attr, value)
        trace("\(stage)-end", accepted: accepted)
    }
    trace("frame-begin")
    defer { trace("frame-end") }
    let currentTopLeft: CGPoint? = topLeft == nil ? nil : window.get(Ax.topLeftCornerAttr)
    let currentSize: CGSize? = size == nil ? nil : window.get(Ax.sizeAttr)
    let positionMatches = topLeft == nil || currentTopLeft == topLeft
    let sizeMatches = size == nil || currentSize == size
    if positionMatches && sizeMatches {
        return
    }
    try disableAnimations(app: app, job) {
        // A restored workspace window is still parked in a screen corner. Resizing
        // there can make the app clamp it onscreen before the destination move.
        if positionFirst, let topLeft, let size {
            if !positionMatches { write(Ax.topLeftCornerAttr, topLeft, stage: "position") }
            try job.checkCancellation()
            // Moving can change the size, so use a fresh observation. Rewriting an
            // unchanged size still asks the app to lay out while its native move
            // may be pending in WindowServer.
            if window.get(Ax.sizeAttr) != size {
                write(Ax.sizeAttr, size, stage: "size")
            }
            try job.checkCancellation()
            // Resizing can clamp position too; confirm and reassert the destination.
            if window.get(Ax.topLeftCornerAttr) != topLeft {
                write(Ax.topLeftCornerAttr, topLeft, stage: "position-reassert")
            }
            return
        }
        if let size { write(Ax.sizeAttr, size, stage: "size") }
        try job.checkCancellation()
        if let topLeft { write(Ax.topLeftCornerAttr, topLeft, stage: "position") } else { return }
        try job.checkCancellation()
        // Moving a window can make macOS clamp its size (e.g. crossing monitors), so the size may
        // need re-asserting. Only re-set when it actually changed: an AX read is much cheaper than
        // an unconditional write, which forces a second layout pass in the target app every time.
        if let size, window.get(Ax.sizeAttr) != size { write(Ax.sizeAttr, size, stage: "size-reassert") }
    }
}

func disableAnimations<T>(app: any AxUiElementMock, _ job: RunLoopJob, _ body: () throws -> T) throws -> T {
    let wasEnabled = app.get(Ax.enhancedUserInterfaceAttr) == true
    if wasEnabled {
        app.set(Ax.enhancedUserInterfaceAttr, false)
    }
    defer {
        if wasEnabled {
            app.set(Ax.enhancedUserInterfaceAttr, true)
        }
    }
    try job.checkCancellation()
    return try body()
}
