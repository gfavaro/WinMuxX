@testable import AppBundle
import AppKit
import Combine
import Common
import XCTest

@MainActor
final class MenuBarLayoutIconTest: WorkspaceTestCase {
    func testFocusedArrangementUpdatesForSameWorkspaceAndWorkspaceSwitch() {
        let first = Workspace.get(byName: "menu-layout-first")
        let second = Workspace.get(byName: "menu-layout-second")
        TestWindow.new(id: 18101, parent: first.rootTilingContainer)
        TestWindow.new(id: 18102, parent: second.rootTilingContainer)
        XCTAssertTrue(first.focusWorkspace())
        updateTrayText()

        let shared = TrayMenuModel.shared
        shared.setIfChanged(\.menuBarWorkspaceArrangement, first.arrangement)
        var publishCount = 0
        let subscription = shared.objectWillChange.sink { publishCount += 1 }
        defer { subscription.cancel() }

        first.arrangement = .master
        updateTrayText()
        XCTAssertEqual(shared.menuBarWorkspaceArrangement, .master)
        XCTAssertGreaterThan(publishCount, 0)
        let afterChange = publishCount

        updateTrayText()
        XCTAssertEqual(publishCount, afterChange, "refreshing an unchanged arrangement must not publish")

        second.arrangement = .scrolling
        XCTAssertTrue(second.focusWorkspace())
        updateTrayText()
        XCTAssertEqual(shared.menuBarWorkspaceArrangement, .scrolling)
        let afterSwitch = publishCount
        updateTrayText()
        XCTAssertEqual(publishCount, afterSwitch, "a settled workspace switch must not republish")
    }

    func testRendererMapsEachLayoutAndAppliesKeyboardTint() throws {
        let images = WorkspaceLayoutName.allCases.map {
            MenuBarLayoutIcon.image(for: $0, monochrome: true)
        }
        XCTAssertEqual(images.map(\.isTemplate), [true, true, true])
        XCTAssertEqual(Set(images.map(renderedPixelSignature)).count, 3, "each arrangement needs a distinct symbol")

        let tint = NSColor(deviceRed: 0.93, green: 0.21, blue: 0.37, alpha: 1)
        let tinted = try XCTUnwrap(menuBarIconImage(enabled: true, arrangement: .scrolling, appearance: .monochrome, keyboardTint: tint))
        XCTAssertFalse(tinted.isTemplate, "keyboard tint must be baked into the selected layout symbol")
        let untinted = MenuBarLayoutIcon.image(for: .scrolling, monochrome: true)
        XCTAssertNotEqual(renderedPixelSignature(tinted), renderedPixelSignature(untinted), "keyboard tint must change the rendered layout icon")

        let disabled = try XCTUnwrap(menuBarIconImage(enabled: false, arrangement: .master, appearance: .color, keyboardTint: tint))
        XCTAssertTrue(disabled.isTemplate, "disabled state retains the pause system symbol")
        let pauseSymbol = try XCTUnwrap(NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "WinMuxX disabled"))
        XCTAssertEqual(renderedPixelSignature(disabled), renderedPixelSignature(pauseSymbol))

        let colorIcon = try XCTUnwrap(menuBarIconImage(enabled: true, arrangement: .master, appearance: .color))
        XCTAssertFalse(colorIcon.isTemplate, "color appearance uses the accent-colored renderer")
    }

    func testMonochromePreviewsAtOneAndTwoTimesForLightAndDark() throws {
        let directory = projectRoot.appending(path: ".build/native-overlay-fixtures")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for layout in WorkspaceLayoutName.allCases {
            for (scheme, tint, background) in [
                ("light", NSColor.black, NSColor.white),
                ("dark", NSColor.white, NSColor(calibratedWhite: 0.12, alpha: 1)),
            ] {
                let icon = MenuBarLayoutIcon.image(for: layout, monochrome: true, tint: tint)
                for scale in [1, 2] {
                    let bitmap = try XCTUnwrap(render(icon, scale: scale, background: background))
                    let name = "menu-bar-\(layout.rawValue)-\(scheme)-\(scale)x.png"
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        .write(to: directory.appending(path: name))
                }
            }
        }
    }

    private func renderedPixelSignature(_ image: NSImage) -> Data {
        render(image, scale: 2)?.representation(using: .png, properties: [:]) ?? Data()
    }

    private func render(_ image: NSImage, scale: Int, background: NSColor = .clear) -> NSBitmapImageRep? {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 18 * scale, pixelsHigh: 18 * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let bitmap else { return nil }
        bitmap.size = NSSize(width: 18, height: 18)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current = context
        background.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: bitmap.size)).fill()
        image.draw(in: NSRect(origin: .zero, size: bitmap.size))
        context?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
