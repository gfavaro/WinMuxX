import AppKit

extension AxUiElementMock {
    /// Electron can omit a live window from AXWindows while still exposing it here.
    /// Prefer the list's element and deduplicate by window ID, not AX object identity.
    func discoverAxWindows() -> [WindowIdAndAxUiElementMock]? {
        let listed = get(Ax.windowsAttr)
        var result: [WindowIdAndAxUiElementMock] = []
        var ids = Set<UInt32>()
        for window in listed ?? [] where window.windowId != 0 && ids.insert(window.windowId).inserted {
            result.append(window)
        }
        for attribute in [Ax.mainWindowAttr, Ax.focusedWindowAttr] {
            if let window = get(attribute), window.windowId != 0, ids.insert(window.windowId).inserted {
                result.append(window)
            }
        }
        // An unanswered list with no fallback is unknown, not proof of zero live windows.
        return listed != nil || !result.isEmpty ? result : nil
    }

    func findAxWindow(windowId: UInt32) -> WindowIdAndAxUiElementMock? {
        guard windowId != 0 else { return nil }
        if let window = get(Ax.windowsAttr)?.first(where: { $0.windowId == windowId }) { return window }
        for attribute in [Ax.mainWindowAttr, Ax.focusedWindowAttr] {
            if let window = get(attribute), window.windowId == windowId { return window }
        }
        return nil
    }
}
