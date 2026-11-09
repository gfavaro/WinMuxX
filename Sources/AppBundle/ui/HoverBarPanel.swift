import AppKit
import Common

/// The hover bar's panel: a dark HUD, as macOS draws its own overlays, with a row of tabs for a
/// tabbed window above the window's actions, each with its configured shortcut beneath.
@MainActor
final class HoverBarPanel: NSPanelHud {
    private let stack = NSStackView()
    private let effectView = NSVisualEffectView()
    /// Deepens the material so the bar stays dark over light windows.
    private let tint = NSView()
    private var run: ((String) -> Void)?
    static let maximumTabRowWidth: CGFloat = 520
    static let cornerRadius: CGFloat = 12

    override init() {
        super.init()
        level = .floating
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        // Dark in either appearance, so the bar reads the same over any window.
        effectView.appearance = NSAppearance(named: .vibrantDark)
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        // A mask image, unlike a layer corner radius, shapes the window itself, so its corners
        // and shadow are rounded too rather than leaving square blanks behind the curve.
        effectView.maskImage = Self.roundedMask(radius: Self.cornerRadius)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        tint.wantsLayer = true
        tint.layer?.cornerRadius = Self.cornerRadius
        tint.layer?.cornerCurve = .continuous
        tint.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(tint)
        effectView.addSubview(stack)
        NSLayoutConstraint.activate([
            tint.leadingAnchor.constraint(equalTo: effectView.leadingAnchor), tint.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            tint.topAnchor.constraint(equalTo: effectView.topAnchor), tint.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor), stack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effectView.topAnchor), stack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
        contentView = effectView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Lays out the tab row (for a tabbed window) above one button per action, each with its
    /// configured shortcut beneath, and returns the bar's size.
    func configure(_ actions: [HoverBarAction], hints: [String?] = [], tabs: [HoverBarTab] = [],
                   run: @escaping (String) -> Void) -> CGSize {
        self.run = run
        let increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        // Dark, with a touch of the accent in the wash and the border.
        let accent = Self.accentColor
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(increasedContrast ? 0.6 : 0.45)
            .blended(withFraction: 0.18, of: accent)?.cgColor
        tint.layer?.borderWidth = 1
        tint.layer?.borderColor = accent.withAlphaComponent(increasedContrast ? 1 : 0.6).cgColor
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let actionRow = Self.row()
        for (index, action) in actions.enumerated() {
            let symbol = NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
            let button = HoverBarButton.make(title: action.title, image: symbol, command: action.command, target: self, action: #selector(pressed(_:)))
            button.font = .systemFont(ofSize: 13, weight: .medium)
            let column = NSStackView(views: [button])
            column.orientation = .vertical
            column.alignment = .centerX
            column.spacing = 0
            if let hint = hints.indices.contains(index) ? hints[index] : nil {
                let label = NSTextField(labelWithString: hint)
                label.font = .systemFont(ofSize: 10, weight: .medium)
                label.textColor = increasedContrast ? .secondaryLabelColor : .tertiaryLabelColor
                column.addArrangedSubview(label)
                button.setAccessibilityHelp("Shortcut \(hint)")
            }
            actionRow.addArrangedSubview(column)
        }
        actionRow.layoutSubtreeIfNeeded()

        if !tabs.isEmpty {
            let tabRow = Self.row()
            for tab in tabs {
                let icon = tab.appBundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
                icon?.size = NSSize(width: 16, height: 16)
                let button = HoverBarButton.make(title: tab.title, image: icon, command: "focus --window-id \(tab.windowId)",
                    target: self, action: #selector(pressed(_:)))
                button.font = .systemFont(ofSize: 12, weight: tab.isActive ? .semibold : .regular)
                button.isCurrent = tab.isActive
                button.widthAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
                button.setAccessibilityLabel(tab.isActive ? "\(tab.title), current tab" : tab.title)
                tabRow.addArrangedSubview(button)
            }
            tabRow.layoutSubtreeIfNeeded()
            let width = min(tabRow.fittingSize.width, max(Self.maximumTabRowWidth, actionRow.fittingSize.width))
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.hasHorizontalScroller = false
            scroll.horizontalScrollElasticity = .allowed
            scroll.documentView = tabRow
            tabRow.frame = NSRect(origin: .zero, size: tabRow.fittingSize)
            scroll.translatesAutoresizingMaskIntoConstraints = false
            scroll.widthAnchor.constraint(equalToConstant: width).isActive = true
            scroll.heightAnchor.constraint(equalToConstant: tabRow.fittingSize.height).isActive = true
            stack.addArrangedSubview(scroll)
            // Keep the current tab in view when the row scrolls.
            if let active = tabs.firstIndex(where: \.isActive), tabRow.arrangedSubviews.indices.contains(active) {
                tabRow.arrangedSubviews[active].scrollToVisible(tabRow.arrangedSubviews[active].bounds)
            }
            let divider = NSView()
            divider.wantsLayer = true
            divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(increasedContrast ? 0.35 : 0.12).cgColor
            divider.translatesAutoresizingMaskIntoConstraints = false
            divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
            divider.widthAnchor.constraint(equalToConstant: max(width, actionRow.fittingSize.width) - 8).isActive = true
            stack.addArrangedSubview(divider)
        }
        stack.addArrangedSubview(actionRow)
        stack.layoutSubtreeIfNeeded()
        return stack.fittingSize
    }

    /// The window's shadow is computed from its shape; recompute it once the bar has its size.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        invalidateShadow()
    }

    static var accentColor: NSColor { winMuxAccentColor }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private static func row() -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 2
        return row
    }

    @objc private func pressed(_ sender: NSButton) {
        guard let command = sender.identifier?.rawValue else { return }
        run?(command)
    }
}

struct HoverBarAction: Equatable {
    let title: String
    let symbol: String
    let command: String
    /// The command a key binding would run for this action, without a window id.
    let shortcut: String
}

struct HoverBarTab: Equatable {
    let windowId: UInt32
    let title: String
    let appBundlePath: String?
    let isActive: Bool
}

/// A borderless item with a rounded highlight under the pointer; the current tab keeps it.
private final class HoverBarButton: NSButton {
    static let height: CGFloat = 26

    var isCurrent = false { didSet { updateHighlight() } }
    private var isHovered = false { didSet { updateHighlight() } }

    static func make(title: String, image: NSImage?, command: String, target: AnyObject, action: Selector) -> HoverBarButton {
        let button = HoverBarButton(title: title, target: target, action: action)
        button.image = image
        button.imagePosition = image == nil ? .noImage : .imageLeading
        button.imageHugsTitle = true
        button.isBordered = false
        button.contentTintColor = .labelColor
        button.lineBreakMode = .byTruncatingTail
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.cornerCurve = .continuous
        button.identifier = NSUserInterfaceItemIdentifier(command)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    /// Room around the title so the highlight reads as a pill rather than a tight box.
    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 18, height: Self.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    /// The current tab is marked in the accent colour; others light up under the pointer.
    private func updateHighlight() {
        layer?.backgroundColor = isCurrent
            ? HoverBarPanel.accentColor.withAlphaComponent(isHovered ? 0.6 : 0.45).cgColor
            : NSColor.white.withAlphaComponent(isHovered ? 0.12 : 0).cgColor
    }
}
