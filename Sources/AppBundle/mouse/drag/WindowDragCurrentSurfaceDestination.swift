import AppKit

@MainActor
func currentWindowSurfaceDestination(
    sourceWindow: Window,
    mouseLocation: CGPoint,
    subject: WindowDragSubject,
    detachOrigin: TabDetachOrigin,
) -> WindowDragIntentDestination? {
    // The workspace under the pointer decides how a drop on its surface resolves.
    windowDragArrangement(for: mouseLocation.monitorApproximation.activeWorkspace)
        .surfaceDestination(sourceWindow: sourceWindow, mouseLocation: mouseLocation, subject: subject,
                            detachOrigin: detachOrigin)
}
