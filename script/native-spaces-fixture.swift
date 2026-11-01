// Interactive native validation fixture. Compile into a temporary .app bundle;
// run on an empty native desktop with competing window managers paused.
import AppKit

@MainActor
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let app = NSMenuItem()
        menu.addItem(app)
        app.submenu = NSMenu()
        app.submenu?.addItem(withTitle: "Quit Native Fixture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let windowItem = NSMenuItem()
        menu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        for index in 0..<2 {
            let window = NSWindow(contentRect: NSRect(x: area.minX + 100 + CGFloat(index * 200),
                y: area.minY + 100, width: 700, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Native Fixture \(index + 1)"
            window.minSize = NSSize(width: 240, height: 180)
            window.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: "Disposable native Spaces validation window \(index + 1)")
            label.frame = NSRect(x: 30, y: 40, width: 500, height: 30)
            window.contentView?.addSubview(label)
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = FixtureDelegate()
    application.delegate = delegate
    withExtendedLifetime(delegate) { application.run() }
}
