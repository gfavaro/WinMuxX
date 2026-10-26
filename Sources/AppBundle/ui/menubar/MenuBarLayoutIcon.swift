import AppKit
import Common

/// Draws the three workspace arrangements at menu-bar scale, independent of the
/// workspace's current window count, nested groups, or master orientation.
enum MenuBarLayoutIcon {
    static let size = NSSize(width: 18, height: 18)

    static func image(
        for arrangement: WorkspaceLayoutName,
        monochrome: Bool,
        tint: NSColor? = nil,
    ) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let color = tint ?? (monochrome ? NSColor.black : NSColor.controlAccentColor)
            color.setStroke()

            switch arrangement {
                case .dwindle:
                    drawOuter()
                    drawDwindle()
                case .master:
                    drawOuter()
                    drawMaster()
                case .scrolling:
                    drawScrolling(in: rect)
            }
            return true
        }
        image.isTemplate = monochrome && tint == nil
        return image
    }

    private static func drawOuter() {
        let outer = NSBezierPath(roundedRect: NSRect(x: 1.6, y: 1.6, width: 14.8, height: 14.8), xRadius: 2.2, yRadius: 2.2)
        outer.lineWidth = 1.35
        outer.lineJoinStyle = .round
        outer.stroke()
    }

    private static func drawDwindle() {
        let path = NSBezierPath()
        // Split in sequence: full-height right pane, then two progressively
        // smaller panes in the left side. This reads differently from Master.
        path.move(to: NSPoint(x: 9.1, y: 1.6)); path.line(to: NSPoint(x: 9.1, y: 16.4))
        path.move(to: NSPoint(x: 1.6, y: 9.3)); path.line(to: NSPoint(x: 9.1, y: 9.3))
        path.move(to: NSPoint(x: 5.3, y: 9.3)); path.line(to: NSPoint(x: 5.3, y: 16.4))
        path.lineWidth = 1.15
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func drawMaster() {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 10.0, y: 16.4)); path.line(to: NSPoint(x: 10.0, y: 1.6))
        path.move(to: NSPoint(x: 10.0, y: 9.0)); path.line(to: NSPoint(x: 16.4, y: 9.0))
        path.lineWidth = 1.15
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func drawScrolling(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(rect: rect.insetBy(dx: 0.2, dy: 0.2))
        clip.addClip()

        let neighbor = NSBezierPath(roundedRect: NSRect(x: -4.8, y: 3.0, width: 8.0, height: 12.0), xRadius: 1.8, yRadius: 1.8)
        let center = NSBezierPath(roundedRect: NSRect(x: 5.4, y: 1.6, width: 7.2, height: 14.8), xRadius: 2.0, yRadius: 2.0)
        let next = NSBezierPath(roundedRect: NSRect(x: 14.8, y: 3.0, width: 8.0, height: 12.0), xRadius: 1.8, yRadius: 1.8)
        neighbor.lineWidth = 1.1
        neighbor.lineJoinStyle = .round
        neighbor.stroke()
        center.lineWidth = 1.4
        center.lineJoinStyle = .round
        center.stroke()
        next.lineWidth = 1.1
        next.lineJoinStyle = .round
        next.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

func menuBarIconImage(
    enabled: Bool,
    arrangement: WorkspaceLayoutName,
    appearance: MenuBarIconAppearance,
    keyboardTint: NSColor? = nil,
) -> NSImage? {
    guard enabled else {
        return NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "WinMuxX disabled")
    }
    return MenuBarLayoutIcon.image(for: arrangement, monochrome: appearance != .color, tint: keyboardTint)
}
