import AppKit

func workspaceSidebarAutomaticColorSwatchImage(isSelected: Bool, appearance: WorkspaceSidebarAppearance = .custom) -> NSImage {
    let foreground: NSColor = appearance == .system ? .labelColor : .white
    return workspaceSidebarSwatchImage {
        drawWorkspaceSidebarSwatchCircle(
            fill: foreground.withAlphaComponent(isSelected ? 0.20 : 0.10),
            stroke: foreground.withAlphaComponent(isSelected ? 0.75 : 0.35),
            lineWidth: isSelected ? 1.4 : 1,
        )
        drawWorkspaceSidebarAutomaticSwatchSlash(color: foreground)
    }
}

func drawWorkspaceSidebarAutomaticSwatchSlash(color: NSColor = .white) {
    let slashPath = NSBezierPath()
    slashPath.move(to: NSPoint(x: 4.3, y: 4.4))
    slashPath.line(to: NSPoint(x: 11.7, y: 11.6))
    slashPath.lineCapStyle = .round
    slashPath.lineWidth = 1.2
    color.withAlphaComponent(0.72).setStroke()
    slashPath.stroke()
}
