import AppKit
import ScreenCaptureKit
import SwiftUI
@testable import AppBundle

/// Exports one marketing scene. Scenes draw WinMuxX's production sidebar and tab views around
/// windows drawn in code: nothing is captured from other apps, the desktop or the user's data.
@MainActor
func renderMarketingScene(_ scene: MarketingScene, to outputURL: URL) async throws {
    try await renderMarketingView(scene.view, to: outputURL, size: scene.size)
}


@MainActor
func renderWinMuxSidebarAppearanceProofs(to directory: URL) async throws {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let variants: [(String, ColorScheme, Bool, Bool, Bool, WorkspaceSidebarAppearance, ChromeStyle, WorkspaceSidebarBackground)] = [
        ("light-expanded", .light, false, false, false, .system, .liquidGlass, .menuBar),
        ("dark-expanded", .dark, false, false, false, .system, .liquidGlass, .menuBar),
        ("light-collapsed", .light, true, false, false, .system, .liquidGlass, .menuBar),
        ("dark-collapsed", .dark, true, false, false, .system, .liquidGlass, .menuBar),
        ("reduced-transparency", .light, false, true, false, .system, .liquidGlass, .menuBar),
        ("increased-contrast", .light, false, false, true, .system, .liquidGlass, .menuBar),
        ("custom-liquid", .light, false, false, false, .custom, .liquidGlass, .sidebar),
        ("custom-solid", .light, false, false, false, .custom, .solid, .sidebar),
        ("no-background-light", .light, false, false, false, .system, .liquidGlass, .transparent),
        ("no-background-dark", .dark, false, false, false, .system, .liquidGlass, .transparent),
        ("wallpaper-brown-system-light", .light, true, false, false, .system, .liquidGlass, .transparent),
        ("wallpaper-brown-system-dark", .dark, true, false, false, .system, .liquidGlass, .transparent),
        ("wallpaper-white-system-light", .light, true, false, false, .system, .liquidGlass, .transparent),
        ("wallpaper-white-system-dark", .dark, true, false, false, .system, .liquidGlass, .transparent),
    ]
    for (name, scheme, collapsed, reduceTransparency, contrast, appearance, chrome, background) in variants {
        var snapshot = MarketingFixtures.sidebarSnapshot
        snapshot.configuration.appearance = appearance
        snapshot.configuration.background = background
        snapshot.configuration.menuBarBackground = !name.hasPrefix("no-background-")
        snapshot.configuration.chromeStyle = chrome
        snapshot.visibleWidth = collapsed ? snapshot.configuration.collapsedWidth : snapshot.configuration.expandedWidth
        let wallpaperSample: WorkspaceSidebarWallpaperSample? = name.hasPrefix("wallpaper-brown-")
            ? WorkspaceSidebarWallpaperSample(tone: .dark, red: 0.32, green: 0.28, blue: 0.21)
            : (name.hasPrefix("wallpaper-white-") ? WorkspaceSidebarWallpaperSample(tone: .light, red: 0.92, green: 0.92, blue: 0.92) : nil)
        if name.hasPrefix("wallpaper-brown-") || name.hasPrefix("wallpaper-white-") {
            var fixedWorkspaces: [WorkspaceSidebarWorkspaceViewModel] = []
            for number in 1...5 {
                let workspaceName = String(number)
                let workspace = WorkspaceSidebarWorkspaceViewModel(
                    name: workspaceName,
                    projectId: snapshot.activeProjectId,
                    displayName: workspaceName,
                    sidebarLabel: "",
                    isGeneratedName: false,
                    monitorScopeId: snapshot.targetMonitorScopeId,
                    monitorName: nil,
                    isFocused: number == 4,
                    isVisible: number == 4,
                    items: []
                )
                fixedWorkspaces.append(workspace)
            }
            snapshot.workspaces = fixedWorkspaces
            snapshot.configuration.showsClock = false
            snapshot.configuration.showsStatusPills = false
            snapshot.configuration.menuBarBackground = false
        }
        let resolvedScheme = wallpaperSample.map {
            workspaceSidebarResolvedColorScheme(menuBarColorScheme: nil, wallpaperTone: $0.tone, systemColorScheme: scheme)
        } ?? scheme
        let size = CGSize(width: snapshot.visibleWidth, height: 700)
        // A code-defined backdrop, not the user's wallpaper or application windows.
        let backdrop = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false
        backdrop.level = .floating
        let backdropColors: [Color] = wallpaperSample.map { [$0.color] } ?? (scheme == .light
            ? [.white, .cyan.opacity(0.35), .pink.opacity(0.3)]
            : [.black, .indigo, .purple])
        backdrop.contentView = NSHostingView(rootView: LinearGradient(
            colors: backdropColors,
            startPoint: .topLeading, endPoint: .bottomTrailing
        ))
        backdrop.backgroundColor = scheme == .light ? .white : .black
        if let screen = NSScreen.main?.visibleFrame {
            backdrop.setFrameOrigin(CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2))
        }
        backdrop.orderFrontRegardless()
        defer { backdrop.orderOut(nil) }
        try await renderMarketingView(
            WorkspaceSidebarView(snapshot: snapshot)
                .environment(\.workspaceSidebarWallpaperSample, wallpaperSample)
                .environment(\.colorScheme, resolvedScheme)
                .background {
                // Include the synthetic backdrop in the transparent proof's own surface,
                // so exported PNGs show controls over it rather than over transparent pixels.
                if background == .transparent {
                    LinearGradient(colors: backdropColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            },
            to: directory.appendingPathComponent(name + ".png"),
            size: size,
            colorScheme: scheme,
            reduceTransparency: reduceTransparency,
            increasedContrast: contrast,
            isOpaque: false,
            backdrop: backdrop
        )
    }
}

@MainActor
func renderMarketingView<Content: View>(
    _ rootView: Content,
    to outputURL: URL,
    size: CGSize = CGSize(width: 1_600, height: 900),
    renderScale: CGFloat = 1,
    colorScheme: ColorScheme = .dark,
    reduceTransparency: Bool = false,
    increasedContrast: Bool = false,
    isOpaque: Bool = true,
    backdrop: NSWindow? = nil
) async throws {
    let renderSize = CGSize(width: size.width * renderScale, height: size.height * renderScale)
    let content = rootView
        .frame(width: size.width, height: size.height)
        .scaleEffect(renderScale, anchor: .topLeading)
        .frame(width: renderSize.width, height: renderSize.height, alignment: .topLeading)
        .environment(\.colorScheme, colorScheme)
        .environment(\.workspaceSidebarPreviewAccessibility, WorkspaceSidebarPreviewAccessibility(
            reduceTransparency: reduceTransparency,
            increasedContrast: increasedContrast
        ))
        .environment(\.workspaceSidebarClockDate, Calendar.current.date(
            from: DateComponents(year: 2026, month: 9, day: 5, hour: 10)
        ))

    // Liquid Glass is composed by WindowServer. A detached NSHostingView cannot reproduce the
    // material: SwiftUI.ImageRenderer omits AppKit-backed surfaces, and cacheDisplay has no live
    // compositor. Host the code-defined scene in a dedicated window, wait for composition, then
    // read only that window's surface. No existing app window or desktop content is captured.
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    if !application.isRunning {
        application.finishLaunching()
    }

    let hostingView = NSHostingView(rootView: content)
    hostingView.frame = CGRect(origin: .zero, size: renderSize)
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: renderSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    window.backgroundColor = isOpaque ? .black : .clear
    window.isOpaque = isOpaque
    let appearanceName: NSAppearance.Name = increasedContrast
        ? (colorScheme == .light ? .accessibilityHighContrastAqua : .accessibilityHighContrastDarkAqua)
        : (colorScheme == .light ? .aqua : .darkAqua)
    window.appearance = NSAppearance(named: appearanceName)
    window.hasShadow = false
    window.level = .floating
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    window.sharingType = .readOnly

    if let screenFrame = NSScreen.main?.visibleFrame {
        window.setFrameOrigin(CGPoint(
            x: screenFrame.midX - (renderSize.width / 2),
            y: screenFrame.midY - (renderSize.height / 2)
        ))
    }

    window.orderFrontRegardless()
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()
    CATransaction.flush()
    try await Task.sleep(for: .milliseconds(800))

    // The backdrop is part of the picture: without it, translucent materials export
    // as nearly transparent pixels. Both windows are the renderer's own.
    let image: CGImage
    do {
        image = try await captureOwnWindows([window] + (backdrop.map { [$0] } ?? []))
    } catch {
        window.orderOut(nil)
        throw WinMuxMarketingRenderError.renderFailed
    }

    window.orderOut(nil)
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [.compressionFactor: 1]) else {
        throw WinMuxMarketingRenderError.encodingFailed
    }
    try data.write(to: outputURL, options: .atomic)
}

enum WinMuxMarketingRenderError: LocalizedError {
    case renderFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
            case .renderFailed:
                "SwiftUI did not produce a rendered image."
            case .encodingFailed:
                "AppKit could not encode the rendered image as PNG."
        }
    }
}

struct MarketingMeasuredTabGroupFrameView: View {
    let strip: WindowTabStripViewModel
    let groupSize: CGSize

    var body: some View {
        let tabHeight = min(strip.frame.height, groupSize.height)
        let outerShape = WindowTabGroupOuterShape(
            activeWindowCornerRadius: strip.activeWindowCornerRadius
        )
        let shellShape = MarketingMeasuredWindowShellShape(
            tabBarHeight: tabHeight,
            cornerRadius: strip.activeWindowCornerRadius
        )

        ZStack(alignment: .topLeading) {
            GlassSurface(
                shape: outerShape,
                style: config.workspaceSidebar.chromeStyle,
                solidColor: config.workspaceSidebar.resolvedSolidChromeColor
            )
            .mask {
                shellShape.fill(style: FillStyle(eoFill: true))
            }

            outerShape
                .stroke(Color.white.opacity(GlassToken.borderOpacity), lineWidth: windowTabGroupFrameStrokeWidth)
                .glassShadow(.raised)

            Rectangle()
                .fill(Color.white.opacity(GlassToken.separatorOpacity))
                .frame(height: StrokeToken.hairline)
                .offset(y: tabHeight - StrokeToken.hairline)

        }
        .frame(width: groupSize.width, height: groupSize.height)
        .allowsHitTesting(false)
    }
}

struct MarketingMeasuredWindowShellShape: Shape {
    let tabBarHeight: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addPath(WindowTabGroupOuterShape(activeWindowCornerRadius: cornerRadius).path(in: rect))
        path.addPath(MarketingMeasuredWindowBoundaryShape(
            tabBarHeight: tabBarHeight,
            cornerRadius: cornerRadius
        ).path(in: rect))
        return path
    }
}

struct MarketingMeasuredWindowBoundaryShape: Shape {
    let tabBarHeight: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let innerRect = WindowTabGroupShellShape.innerRect(
            in: rect,
            tabBarHeight: tabBarHeight
        )
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: innerRect)
    }
}

/// The renderer's own windows, composited as they show, at the display's full resolution.
@MainActor
private func captureOwnWindows(_ windows: [NSWindow]) async throws -> CGImage {
    let numbers = Set(windows.map { CGWindowID($0.windowNumber) })
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let included = content.windows.filter { numbers.contains($0.windowID) }
    // ScreenCaptureKit frames use a top-left origin; AppKit's start at the bottom of the main screen.
    let mainHeight = NSScreen.screens.first?.frame.height ?? 0
    let union = windows.map(\.frame).reduce(CGRect.null) { $0.union($1) }
    let frame = CGRect(x: union.minX, y: mainHeight - union.maxY, width: union.width, height: union.height)
    guard let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) })
    else { throw WinMuxMarketingRenderError.renderFailed }
    let scale = windows.first?.backingScaleFactor ?? 2
    let configuration = SCStreamConfiguration()
    configuration.sourceRect = frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    configuration.width = Int((frame.width * scale).rounded())
    configuration.height = Int((frame.height * scale).rounded())
    configuration.captureResolution = .best
    configuration.showsCursor = false
    return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, including: included),
                                                      configuration: configuration)
}
