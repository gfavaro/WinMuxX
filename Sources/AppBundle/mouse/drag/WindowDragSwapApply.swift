@MainActor
func applyWindowSwapDragIntent(
    sourceWindow: Window,
    sourceSubject: WindowDragSubject,
    targetWindow: Window,
) -> Bool {
    if shouldSuppressSameTabGroupSwapDestination(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: sourceSubject,
        detachOrigin: getCurrentMouseTabDetachOrigin()
    ) {
        return false
    }
    guard case let (sourceNode, targetNode)? = validatedDragNodePair(
        sourceWindow: sourceWindow,
        targetWindow: targetWindow,
        subject: sourceSubject,
        detachOrigin: getCurrentMouseTabDetachOrigin(),
    ) else { return false }
    swapNodes(sourceNode, targetNode)
    return sourceWindow.focusWindow()
}
