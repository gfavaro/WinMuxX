import AppKit
import Common

/// A brief notice near the top of the main display that dismisses itself.
@MainActor
final class NoticePanel {
    static let shared = NoticePanel()
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

    func showMinimumSize(appName: String, dimension: String, minimum: CGSize) {
        show(title: "Minimum size reached", body: "\(appName) cannot be resized further in \(dimension). Learned minimum: \(minimum.width > 0 ? String(Int(minimum.width.rounded())) : "unknown") × \(minimum.height > 0 ? String(Int(minimum.height.rounded())) : "unknown").")
    }

    /// The last notice asked for, kept for tests, which never put a panel on screen.
    private(set) var lastNotice: (title: String, body: String)?

    func show(title: String, body: String, seconds: Double = 3) {
        lastNotice = (title, body)
        if isUnitTest { return }
        generation &+= 1
        let current = generation
        dismissal?.cancel()
        let title = NSTextField(labelWithString: title)
        title.font = .boldSystemFont(ofSize: 13)
        let body = NSTextField(wrappingLabelWithString: body)
        body.font = .systemFont(ofSize: 12)
        body.maximumNumberOfLines = 3
        let stack = NSStackView(views: [title, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 13, left: 15, bottom: 13, right: 15)
        panel.contentView = stack
        body.preferredMaxLayoutWidth = 330
        let height = stack.fittingSize.height
        panel.setContentSize(NSSize(width: 360, height: height))
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        panel.setFrameOrigin(CGPoint(x: screen.midX - 180, y: screen.maxY - 20 - height))
        panel.orderFrontRegardless()
        dismissal = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.generation == current else { return }
            self.panel.orderOut(nil)
        }
    }
}
