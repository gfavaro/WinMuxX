/// The drop a drag would make now: the destination under the pointer, for this dragged window.
struct PendingWindowDragIntent {
    let sourceWindowId: UInt32
    let sourceSubject: WindowDragSubject
    let destination: WindowDragIntentDestination
    let isPointerSettled: Bool

    var kind: WindowDragIntentKind { destination.kind }
    var previewRect: Rect { destination.previewRect }
    var interactionRect: Rect { destination.interactionRect }
    var title: String { destination.title }
    var subtitle: String { destination.subtitle }
    var previewStyle: WindowTabDropPreviewStyle { destination.previewStyle }
    var previewGeometry: WindowTabDropPreviewGeometry { destination.previewGeometry }
    var isGroup: Bool { destination.isGroup }
}

extension WindowDragIntentDestination {
    /// The same drop, shown the same way; its overlay does not count, as it follows the pointer.
    func isSameIntent(as other: WindowDragIntentDestination) -> Bool {
        kind == other.kind && title == other.title && subtitle == other.subtitle &&
            previewStyle == other.previewStyle && previewGeometry == other.previewGeometry && isGroup == other.isGroup &&
            previewRect.isEqual(to: other.previewRect) && interactionRect.isEqual(to: other.interactionRect)
    }
}
