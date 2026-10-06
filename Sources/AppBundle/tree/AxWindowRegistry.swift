import AppKit

extension [UInt32: AxWindow] {
    mutating func getOrRegisterAxWindow(
        windowId id: UInt32, from app: AXUIElement,
        _ nsApp: NSRunningApplication, _ job: RunLoopJob,
    ) throws -> AxWindow? {
        if let existing = self[id] { return existing }
        try job.checkCancellation()
        guard let window = app.findAxWindow(windowId: id) else { return nil }
        return try getOrRegisterAxWindow(windowId: id, window.ax.cast, nsApp, job)
    }

    @discardableResult
    mutating func getOrRegisterAxWindow(
        windowId id: UInt32,
        _ axWindow: AXUIElement,
        _ nsApp: NSRunningApplication,
        _ job: RunLoopJob,
    ) throws -> AxWindow? {
        if let existing = self[id] { return existing }
        if isLeftMouseButtonDown { return nil }

        if let window = try AxWindow.new(windowId: id, axWindow, nsApp, job) {
            self[id] = window
            return window
        } else {
            return nil
        }
    }
}
