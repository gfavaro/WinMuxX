import AppKit
import Common
import SwiftUI

@MainActor
final class WorkspaceSidebarPanel: NSPanelHud {
    static let shared = WorkspaceSidebarPanel(monitor: mainMonitor)
    private static var panelsByMonitorScopeId: [String: WorkspaceSidebarPanel] = [:]
    static weak var activeInlineTextEditingPanel: WorkspaceSidebarPanel?
    static var menuBarColorScheme: ColorScheme?

    let state: WorkspaceSidebarPanelState
    let hostingView: WorkspaceSidebarHostingView
    let materialContainer: WorkspaceSidebarMaterialContainer
    let monitorScopeId: String
    private(set) var isRetired = false
    var pendingBackingResize: DispatchWorkItem?
    var pendingExpand: DispatchWorkItem?
    /// A collapse under way, one stage at a time; nil when none is.
    var pendingCollapseWork: WorkspaceSidebarCollapse?
    var pendingCollapse: DispatchWorkItem? { pendingCollapseWork?.waitingItem }
    var pendingCollapseFinalize: DispatchWorkItem? { pendingCollapseWork?.finishingItem }
    var pendingContentUnload: DispatchWorkItem?
    var lastHoverMonitorTimestamp: CFTimeInterval = 0
    var hasPendingHoverRecheck = false
    var menuTrackingDepth = 0
    var menuTrackingGraceUntil: Date = .distantPast
    var inlineTextEditingActive = false
    var inlineTextEditingLocksExpansion = true
    var inlineTextEditingCancelsOnPointerExit = true
    var inlineTextEditingCancel: (@MainActor () -> Void)?
    var inlineTextEditingKeyDown: (@MainActor (WorkspaceSidebarInlineTextKey) -> Void)?
    var inlineTextEditingEventMonitors: [Any] = []
    var inlineTextEditingKeyEventTap: CFMachPort?
    var inlineTextEditingKeyEventTapRunLoopSource: CFRunLoopSource?
    var inlineTextEditingStartedAt: Date = .distantPast
    var inlineTextEditingPointerEnteredVisibleRegion = false
    var commandExpansionLocksCollapse = false
    var overrideConfirmationLocksCollapse = false
    var shouldLockNextSidebarSearchExpansion = false
    var bufferedCommandSidebarSearchKeys: [WorkspaceSidebarInlineTextKey] = []
    var commandMouseUnlockPoint: CGPoint?
    var commandMouseUnlockMonitors: [Any] = []
    var menuTrackingObservers: [NSObjectProtocol] = []
    var lastEdgeTrapSample: MousePointerSample?
    var edgeTrapStartedAt: TimeInterval?
    var edgeTrapSuppressedUntil: TimeInterval = 0
    var splitBrowseCollapseSuppressedUntil: Date = .distantPast
    var persistentExpansionWidth: CGFloat?
    var measuredContentHeight: CGFloat = 0
    let hoverPollInterval: TimeInterval = 1.0 / 30.0
    var hoverDwellSatisfied = false
    var hoverRevealGeneration: UInt = 0
    var leftMousePressStartedInsideSidebar = false
    let hoverCueAnimationResponse: TimeInterval = 0.18
    let animationDuration: TimeInterval = 0.14
    let menuTrackingEndGrace: TimeInterval = 0.75
    let edgeTrapBandWidth: CGFloat = 18
    let edgeTrapReleaseVelocityThreshold: CGFloat = 4
    let edgeTrapReleaseDelay: TimeInterval = 0.2
    let edgeTrapCrossingGrace: TimeInterval = 0.25

    private init(monitor: Monitor) {
        monitorScopeId = workspaceSidebarMonitorScopeId(for: monitor)
        state = WorkspaceSidebarPanelState(targetMonitorScopeId: monitorScopeId)
        hostingView = WorkspaceSidebarHostingView(rootView: WorkspaceSidebarContainerView(
            state: state,
            actions: makeWorkspaceSidebarActionsAdapter(state: state)
        ))
        materialContainer = WorkspaceSidebarMaterialContainer()
        state.contentLoaded = !workspaceSidebarUnloadsWhenResting(config.workspaceSidebar)
        super.init()
        identifier = NSUserInterfaceItemIdentifier("\(workspaceSidebarPanelId).\(monitorScopeId)")
        styleMask.remove(.nonactivatingPanel)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        hasShadow = false
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        applyWinMuxLayer(.workspaceSidebar)
        contentView = materialContainer
        materialContainer.install(content: hostingView)
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        installMenuTrackingObservers()
    }

    static var visiblePanels: [WorkspaceSidebarPanel] {
        panelsByMonitorScopeId.values.filter(\.isVisible)
    }

    static func panel(containing point: CGPoint) -> WorkspaceSidebarPanel? {
        visiblePanels.first { $0.visibleScreenRectNormalized()?.contains(point) == true }
    }

    static func panel(for monitorScopeId: String) -> WorkspaceSidebarPanel? {
        panelsByMonitorScopeId[monitorScopeId]
    }

    static func updateVisibleDropTargets(_ targets: [WorkspaceSidebarDropTargetFrame]) {
        workspaceSidebarDropTargets = visiblePanels.flatMap { $0.convertDropTargets(targets) }
    }

    static func refreshAll() {
        refreshAll(on: workspaceSidebarResolvedPanelMonitors())
    }

    static func refreshAll(on monitors: [Monitor]) {
        let activeMonitorScopeIds = Set(monitors.map { workspaceSidebarMonitorScopeId(for: $0) })
        // Scope IDs include display positions. Do not keep a hosting tree for every
        // arrangement the user has ever connected; returning scopes get fresh panels.
        for scopeId in panelsByMonitorScopeId.keys.filter({ !activeMonitorScopeIds.contains($0) }) {
            panelsByMonitorScopeId.removeValue(forKey: scopeId)?.retire()
        }
        for monitor in monitors {
            let scopeId = workspaceSidebarMonitorScopeId(for: monitor)
            let panel = panelsByMonitorScopeId[scopeId] ?? WorkspaceSidebarPanel(monitor: monitor)
            panelsByMonitorScopeId[scopeId] = panel
            panel.syncModelFromShared()
            panel.refresh(on: monitor)
        }
    }

    func retire() {
        guard !isRetired else { return }
        isRetired = true
        cancelExpansionWork()
        pendingContentUnload?.cancel()
        pendingContentUnload = nil
        endInlineTextEditing()
        removeInlineTextEditingEventMonitors()
        removeInlineTextEditingKeyEventTap()
        removeCommandMouseUnlockMonitors()
        inlineTextEditingCancel = nil
        inlineTextEditingKeyDown = nil
        commandExpansionLocksCollapse = false
        shouldLockNextSidebarSearchExpansion = false
        bufferedCommandSidebarSearchKeys = []
        for observer in menuTrackingObservers { NotificationCenter.default.removeObserver(observer) }
        menuTrackingObservers = []
        // A search view may itself retain this panel. Drop the SwiftUI subtree
        // explicitly so removing the registry entry also breaks that ownership path.
        hostingView.rootView = nil
        state.isExpanded = false
        state.visibleWidth = 0
        ignoresMouseEvents = true
        contentView = nil
        close()
    }

    static func syncVisiblePanelModelsFromShared() {
        for panel in panelsByMonitorScopeId.values {
            panel.syncModelFromShared()
        }
    }

    static func refreshWallpaperContrast() {
        TrayMenuModel.shared.wallpaperRefreshGeneration &+= 1
    }

    func syncModelFromShared() {
        guard !isRetired else { return }
        var sidebarConfiguration = workspaceSidebarConfiguration()
        // Scrolling columns slide under the sidebar, as at the display's edge: a clear sidebar
        // would show them, so it takes its background while one is beneath it.
        if let monitor = workspaceSidebarMonitor(forScopeId: monitorScopeId), scrollingColumnIsUnderSidebar(on: monitor) {
            sidebarConfiguration.menuBarBackground = true
        }
        materialContainer.configure(configuration: sidebarConfiguration, visibleWidth: state.visibleWidth)
        // Only what differs per display is kept here; shared values are read from
        // TrayMenuModel.shared directly, and Observation skips unchanged writes.
        state.configuration = sidebarConfiguration
        state.activeProjectId = resolvedLocalActiveProjectId()
        state.selectedMonitorScopeId = resolvedLocalSelectedMonitorScopeId()
    }

    private func resolvedLocalActiveProjectId() -> WorkspaceProjectId {
        let monitor = workspaceSidebarMonitor(forScopeId: monitorScopeId)
        return monitor.map { activeWorkspaceProjectId(for: $0) } ?? workspaceProjectDefaultId
    }

    private func resolvedLocalSelectedMonitorScopeId() -> String {
        let validScopeIds = Set(TrayMenuModel.shared.workspaceSidebarMonitorScopes.map(\.id))
        if validScopeIds.contains(state.selectedMonitorScopeId) {
            return state.selectedMonitorScopeId
        }
        return workspaceSidebarDefaultScopeId
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        debugLog(.sidebarRename, "panel becomeKey isKey=\(isKeyWindow) firstResponder=\(String(describing: firstResponder))")
    }

    override func resignKey() {
        debugLog(.sidebarRename, "panel resignKey isKey=\(isKeyWindow) firstResponder=\(String(describing: firstResponder))")
        super.resignKey()
    }

    override func keyDown(with event: NSEvent) {
        debugLog(.sidebarRename, "panel keyDown keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "nil") firstResponder=\(String(describing: firstResponder)) inline=\(inlineTextEditingActive)")
        if handleInlineTextEditingKey(inlineTextKey(from: event)) {
            return
        }
        super.keyDown(with: event)
    }
}

final class WorkspaceSidebarHostingView: NSHostingView<WorkspaceSidebarContainerView?> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// The window reserves extra width for project browsing. Only the visible rail
/// gets material; hosting coordinates remain relative to the full window.
final class WorkspaceSidebarMaterialContainer: NSView {
    let customSurface = NSView()
    let clearSurface = NSView()
    let opaqueSurface = NSView()
    let glassSurface: NSView
    let glassContent = NSView()
    private var hostedContent: NSView?
    private var configuration = WorkspaceSidebarConfiguration.empty
    private var visibleWidth: CGFloat = 0
    private let clippingLayer = CAShapeLayer()
    private var wallpaperTone: WorkspaceSidebarWallpaperTone?
    private let reduceTransparency: () -> Bool

    override convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, reduceTransparency: {
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        })
    }

    init(frame frameRect: NSRect, reduceTransparency: @escaping () -> Bool) {
        self.reduceTransparency = reduceTransparency
        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = 0
        glass.tintColor = nil
        glass.contentView = glassContent
        glass.wantsLayer = true
        glassSurface = glass
        super.init(frame: frameRect)
        customSurface.wantsLayer = true
        clearSurface.wantsLayer = true
        opaqueSurface.wantsLayer = true
        addSubview(customSurface)
        addSubview(clearSurface)
        addSubview(opaqueSurface)
        addSubview(glassSurface)
        configure(configuration: configuration, visibleWidth: 0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func install(content: NSView) {
        hostedContent = content
        configure(configuration: configuration, visibleWidth: visibleWidth)
    }

    func configure(configuration: WorkspaceSidebarConfiguration, visibleWidth: CGFloat, wallpaperTone: WorkspaceSidebarWallpaperTone? = nil, contentColorScheme: ColorScheme? = nil) {
        self.configuration = configuration
        self.visibleWidth = visibleWidth
        self.wallpaperTone = wallpaperTone
        let system = configuration.appearance == .system
        let expanded = configuration.alwaysExpanded || visibleWidth > configuration.collapsedWidth + 8
        let background = WorkspaceSidebarSystemBackground.resolve(
            showBackground: configuration.menuBarBackground,
            reduceTransparency: reduceTransparency(),
            expanded: expanded
        )
        let surface: NSView
        if !system {
            surface = customSurface
        } else {
            switch background {
            case .clear: surface = clearSurface
            case .glass, .frosted: surface = glassSurface
            case .opaque: surface = opaqueSurface
            }
        }
        let contentParent = surface === glassSurface ? glassContent : surface
        if let content = hostedContent, content.superview !== contentParent {
            contentParent.addSubview(content)
        }
        customSurface.isHidden = surface !== customSurface || visibleWidth <= 0
        clearSurface.isHidden = surface !== clearSurface || visibleWidth <= 0
        opaqueSurface.isHidden = surface !== opaqueSurface || visibleWidth <= 0
        glassSurface.isHidden = surface !== glassSurface || visibleWidth <= 0
        if system, expanded {
            let systemScheme: ColorScheme = contentColorScheme ??
                (NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light)
            let resolved = configuration.chromeAppearance(systemScheme: systemScheme,
                reduceTransparency: reduceTransparency())
            appearance = NSAppearance(named: resolved.scheme == .dark ? .darkAqua : .aqua)
        } else if system, configuration.theme != .system {
            appearance = configuration.theme.nativeAppearance
        } else if system, !reduceTransparency(), let scheme = contentColorScheme ?? wallpaperTone?.colorScheme {
            appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        } else { appearance = nil }
        updateOpaqueBackground()
        updateGeometry()
    }

    var activeSurface: NSView {
        guard configuration.appearance == .system else { return customSurface }
        let expanded = configuration.alwaysExpanded || visibleWidth > configuration.collapsedWidth + 8
        switch WorkspaceSidebarSystemBackground.resolve(
            showBackground: configuration.menuBarBackground,
            reduceTransparency: reduceTransparency(),
            expanded: expanded
        ) {
        case .clear: return clearSurface
        case .glass, .frosted: return glassSurface
        case .opaque: return opaqueSurface
        }
    }

    override func layout() {
        super.layout()
        updateGeometry()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateOpaqueBackground()
    }

    private func updateOpaqueBackground() {
        // AppKit exposes no menu-bar material. Match the measured opaque palette
        // without screen capture, polling, or wallpaper-dependent contrast.
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        opaqueSurface.layer?.backgroundColor = workspaceSidebarOpaqueColor(dark: dark).cgColor
    }

    private func updateGeometry() {
        let windowEdge = (window as? WorkspaceSidebarPanel)?.windowEdge(visibleWidth: visibleWidth)
        let rect = workspaceSidebarSurfaceFrame(panel: bounds, width: visibleWidth, position: configuration.position,
                                                windowEdge: windowEdge)
        let surface = activeSurface
        // The mask path is drawn top-down; a layer that is not flipped is bottom-up.
        let maskEdge = surface.isFlipped ? windowEdge : windowEdge.map { edge in
            var flipped = edge
            flipped.topInset = edge.bottomInset
            flipped.bottomInset = edge.topInset
            return flipped
        }
        surface.frame = rect
        if surface === glassSurface { glassContent.frame = CGRect(origin: .zero, size: rect.size) }
        hostedContent?.frame = CGRect(x: -rect.minX, y: 0, width: bounds.width, height: bounds.height)
        let path = workspaceSidebarPanelShape(configuration: configuration, visibleWidth: visibleWidth, windowEdge: maskEdge)
            .path(in: CGRect(origin: .zero, size: rect.size)).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clippingLayer.frame = CGRect(origin: .zero, size: rect.size)
        clippingLayer.path = path
        surface.layer?.mask = clippingLayer
        CATransaction.commit()
    }
}

/// A sidebar collapse: first waiting briefly for the pointer to stay out, then animating closed
/// until the panel is marked collapsed. Cancelling it cancels whichever stage it is in.
enum WorkspaceSidebarCollapse {
    case waiting(DispatchWorkItem)
    case finishing(DispatchWorkItem)

    var waitingItem: DispatchWorkItem? { if case .waiting(let item) = self { item } else { nil } }
    var finishingItem: DispatchWorkItem? { if case .finishing(let item) = self { item } else { nil } }

    func cancel() {
        switch self {
            case .waiting(let item), .finishing(let item): item.cancel()
        }
    }
}

extension WorkspaceSidebarPanel {
    /// Set while a resting rail sits beside tiled windows (not centered, not an expanded overlay), so the
    /// sidebar can continue over the outer gap and around the windows' rounded corners.
    func windowEdge(visibleWidth: CGFloat) -> WorkspaceSidebarWindowEdge? {
        guard abs(visibleWidth - workspaceSidebarRestingWidth(config.workspaceSidebar)) < 1,
              let monitor = workspaceSidebarMonitor(forScopeId: monitorScopeId) else { return nil }
        return workspaceSidebarWindowEdge(on: monitor)
    }

    func cancelCollapse() {
        pendingCollapseWork?.cancel()
        pendingCollapseWork = nil
    }
}

/// Where tiled windows begin beside this display's resting sidebar, if it has one (macOS 27, not centered).
/// A Scrolling workspace has no such edge: its columns scroll under and past the sidebar.
@MainActor
func workspaceSidebarWindowEdge(on monitor: Monitor) -> WorkspaceSidebarWindowEdge? {
    let sidebar = config.workspaceSidebar
    guard #available(macOS 27, *), sidebar.heightMode != .centered,
          workspaceSidebarRestingWidth(sidebar) > 0,
          monitor.activeWorkspace.arrangement != .scrolling else { return nil }
    let outer = ResolvedGaps(gaps: config.gaps, monitor: monitor).outer
    return WorkspaceSidebarWindowEdge(
        gap: CGFloat(sidebar.position == .left ? outer.left : outer.right),
        radius: systemWindowCornerRadius(),
        topInset: CGFloat(outer.top), bottomInset: CGFloat(outer.bottom))
}

/// Whether the Scrolling workspace shown on `monitor` has a window laid out under its sidebar.
@MainActor
private func scrollingColumnIsUnderSidebar(on monitor: Monitor) -> Bool {
    let workspace = monitor.activeWorkspace
    let inset = monitor.workspaceSidebarInset
    guard workspace.arrangement == .scrolling, inset > 0 else { return false }
    let onRight = config.workspaceSidebar.position == .right
    let edge = onRight ? monitor.visibleRect.maxX - inset : monitor.visibleRect.minX + inset
    return workspace.rootTilingContainer.allLeafWindowsRecursive.contains { window in
        guard let rect = window.lastAppliedLayoutPhysicalRect else { return false }
        return onRight ? rect.maxX > edge + 1 : rect.minX < edge - 1
    }
}
