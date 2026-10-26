import AppKit

@MainActor
final class MinimumSizeNoticePanel {
    static let shared = MinimumSizeNoticePanel()
    private let panel = NSPanelHud()
    private var dismissal: Task<Void, Never>?
    private var generation: UInt64 = 0

    private init() {
        panel.isOpaque = true
        panel.backgroundColor = .windowBackgroundColor
        panel.level = .floating
        panel.hasShadow = true
        panel.contentView = NSView()
    }

    func show(appName: String, dimension: String, minimum: CGSize) {
        generation &+= 1
        let current = generation
        dismissal?.cancel()
        let title = NSTextField(labelWithString: "Minimum size reached")
        title.font = .boldSystemFont(ofSize: 13)
        let body = NSTextField(wrappingLabelWithString: "\(appName) cannot be resized further in \(dimension). Learned minimum: \(minimum.width > 0 ? String(Int(minimum.width.rounded())) : "unknown") × \(minimum.height > 0 ? String(Int(minimum.height.rounded())) : "unknown").")
        body.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [title, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 13, left: 15, bottom: 13, right: 15)
        panel.contentView = stack
        panel.setContentSize(NSSize(width: 360, height: 72))
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        panel.setFrameOrigin(CGPoint(x: screen.midX - 180, y: screen.maxY - 92))
        panel.orderFrontRegardless()
        dismissal = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, self.generation == current else { return }
            self.panel.orderOut(nil)
        }
    }
}
