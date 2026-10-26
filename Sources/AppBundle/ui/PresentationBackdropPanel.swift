import AppKit

@MainActor
final class PresentationBackdropPanel: NSPanelHud {
    var onBackdropClick: (() -> Void)?

    override init() {
        super.init()
        level = .normal
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
    }

    func orderBehindTarget(windowId: UInt32) {
        order(.below, relativeTo: Int(windowId))
    }

    override func mouseDown(with event: NSEvent) {
        onBackdropClick?()
    }
}
