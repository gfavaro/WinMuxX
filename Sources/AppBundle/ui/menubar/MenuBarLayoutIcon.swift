import AppKit
import Common

/// Draws the workspace arrangements at menu-bar scale, independent of the
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
                case .tabbed:
                    drawOuter()
                    drawTabbed()
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
        // Split in sequence: full-height left pane, then two progressively
        // smaller panes in the right side. This reads differently from Master.
        path.move(to: NSPoint(x: 8.9, y: 16.4)); path.line(to: NSPoint(x: 8.9, y: 1.6))
        path.move(to: NSPoint(x: 16.4, y: 8.7)); path.line(to: NSPoint(x: 8.9, y: 8.7))
        path.move(to: NSPoint(x: 12.7, y: 8.7)); path.line(to: NSPoint(x: 12.7, y: 1.6))
        path.lineWidth = 1.15
        path.lineJoinStyle = .round
        path.stroke()
    }

    /// A row of tabs across the top above one window.
    private static func drawTabbed() {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 1.6, y: 12.6)); path.line(to: NSPoint(x: 16.4, y: 12.6))
        path.move(to: NSPoint(x: 6.6, y: 16.4)); path.line(to: NSPoint(x: 6.6, y: 12.6))
        path.move(to: NSPoint(x: 11.4, y: 16.4)); path.line(to: NSPoint(x: 11.4, y: 12.6))
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
