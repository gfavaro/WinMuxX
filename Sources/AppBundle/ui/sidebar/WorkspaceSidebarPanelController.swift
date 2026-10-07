import AppKit
import Common
import SwiftUI

@MainActor
final class WorkspaceSidebarPanel: NSPanelHud {
    static let shared = WorkspaceSidebarPanel(monitor: mainMonitor)
    private static var panelsByMonitorScopeId: [String: WorkspaceSidebarPanel] = [:]
    static weak var activeInlineTextEditingPanel: WorkspaceSidebarPanel?
    static var menuBarColorScheme: ColorScheme?

    let viewModel: TrayMenuModel
    let hostingView: WorkspaceSidebarHostingView
    let materialContainer: WorkspaceSidebarMaterialContainer
    let monitorScopeId: String
    var pendingBackingResize: DispatchWorkItem?
    var pendingExpand: DispatchWorkItem?
    var pendingCollapse: DispatchWorkItem?
    var pendingCollapseFinalize: DispatchWorkItem?
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
    let hoverExitTolerance: CGFloat = 20
    let hoverPollInterval: TimeInterval = 1.0 / 30.0
    let hoverOpenDelay: TimeInterval = 0.05
    let hoverCueAnimationResponse: TimeInterval = 0.18
    let animationDuration: TimeInterval = 0.14
    let menuTrackingEndGrace: TimeInterval = 0.75
    let edgeTrapBandWidth: CGFloat = 18
    let edgeTrapReleaseVelocityThreshold: CGFloat = 4
    let edgeTrapReleaseDelay: TimeInterval = 0.2
    let edgeTrapCrossingGrace: TimeInterval = 0.25

    private init(monitor: Monitor) {
        monitorScopeId = workspaceSidebarMonitorScopeId(for: monitor)
        viewModel = TrayMenuModel()
        hostingView = WorkspaceSidebarHostingView(rootView: WorkspaceSidebarContainerView(
            viewModel: viewModel,
            actions: makeWorkspaceSidebarActionsAdapter(viewModel: viewModel, targetMonitorScopeId: monitorScopeId)
        ))
        materialContainer = WorkspaceSidebarMaterialContainer()
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
        let activeMonitorScopeIds = Set(workspaceSidebarResolvedPanelMonitors().map { workspaceSidebarMonitorScopeId(for: $0) })
        for monitor in workspaceSidebarResolvedPanelMonitors() {
            let scopeId = workspaceSidebarMonitorScopeId(for: monitor)
            let panel = panelsByMonitorScopeId[scopeId] ?? WorkspaceSidebarPanel(monitor: monitor)
            panelsByMonitorScopeId[scopeId] = panel
            panel.syncModelFromShared()
            panel.refresh(on: monitor)
        }
        for (scopeId, panel) in panelsByMonitorScopeId where !activeMonitorScopeIds.contains(scopeId) {
            panel.resetHiddenSidebarState()
        }
    }

    static func syncVisiblePanelModelsFromShared() {
        for panel in panelsByMonitorScopeId.values {
            panel.syncModelFromShared()
        }
    }

    static func refreshWallpaperContrast() {
        for panel in panelsByMonitorScopeId.values {
            panel.viewModel.workspaceSidebarWallpaperRefreshGeneration &+= 1
        }
    }

    func syncModelFromShared() {
        let sidebarConfiguration = workspaceSidebarConfiguration()
        materialContainer.configure(configuration: sidebarConfiguration, visibleWidth: viewModel.workspaceSidebarVisibleWidth)
        viewModel.setIfChanged(\.workspaceSidebarConfiguration, sidebarConfiguration)
        // Equality-guarded: this runs several times per refresh session, and each unguarded
        // @Published write would invalidate the whole sidebar SwiftUI tree even when nothing
        // changed. workspaceSidebarVisibleWidth/isWorkspaceSidebarExpanded are panel-local and
        // never synced. experimentalUISettings is stateless (reads UserDefaults live) and only
        // the native menu bar observes it, so it isn't synced either.
        viewModel.setIfChanged(\.isEnabled, TrayMenuModel.shared.isEnabled)
        viewModel.setIfChanged(\.workspaces, TrayMenuModel.shared.workspaces)
        viewModel.setIfChanged(\.workspaceSidebarWorkspaces, TrayMenuModel.shared.workspaceSidebarWorkspaces)
        viewModel.setIfChanged(\.workspaceSidebarProjects, TrayMenuModel.shared.workspaceSidebarProjects)
        viewModel.setIfChanged(\.workspaceSidebarActiveProjectId, resolvedLocalActiveProjectId())
        viewModel.setIfChanged(\.workspaceSidebarMonitorScopes, TrayMenuModel.shared.workspaceSidebarMonitorScopes)
        viewModel.setIfChanged(\.workspaceSidebarSelectedMonitorScopeId, resolvedLocalSelectedMonitorScopeId())
        viewModel.setIfChanged(\.workspaceSidebarTargetMonitorScopeId, monitorScopeId)
        viewModel.setIfChanged(\.workspaceSidebarFocusedMonitorScopeId, TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId)
        viewModel.setIfChanged(\.workspaceSidebarShowsMonitorSelector, TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector)
        viewModel.setIfChanged(\.workspaceSidebarDropPreview, TrayMenuModel.shared.workspaceSidebarDropPreview)
        viewModel.setIfChanged(\.windowTabStrips, TrayMenuModel.shared.windowTabStrips)
        viewModel.setIfChanged(\.workspaceSidebarTopPadding, TrayMenuModel.shared.workspaceSidebarTopPadding)
        viewModel.setIfChanged(\.workspaceSidebarHoveredWorkspaceName, resolvedLocalHoveredWorkspaceName())
    }

    private func resolvedLocalActiveProjectId() -> WorkspaceProjectId {
        let monitor = workspaceSidebarMonitor(forScopeId: monitorScopeId)
        return monitor.map { activeWorkspaceProjectId(for: $0) } ?? workspaceProjectDefaultId
    }

    private func resolvedLocalSelectedMonitorScopeId() -> String {
        let validScopeIds = Set(TrayMenuModel.shared.workspaceSidebarMonitorScopes.map(\.id))
        if validScopeIds.contains(viewModel.workspaceSidebarSelectedMonitorScopeId) {
            return viewModel.workspaceSidebarSelectedMonitorScopeId
        }
        return workspaceSidebarDefaultScopeId
    }

    private func resolvedLocalHoveredWorkspaceName() -> String? {
        let visibleWorkspaceNames = visibleWorkspaceNamesForSidebar(
            workspaces: TrayMenuModel.shared.workspaceSidebarWorkspaces,
            selectedMonitorScopeId: viewModel.workspaceSidebarSelectedMonitorScopeId,
            focusedMonitorScopeId: TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId,
        )
        return sanitizedWorkspaceSidebarHoveredWorkspaceName(
            visibleWorkspaceNames: visibleWorkspaceNames,
            hoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        debugWorkspaceSidebarRenameLog("panel becomeKey isKey=\(isKeyWindow) firstResponder=\(String(describing: firstResponder))")
    }

    override func resignKey() {
        debugWorkspaceSidebarRenameLog("panel resignKey isKey=\(isKeyWindow) firstResponder=\(String(describing: firstResponder))")
        super.resignKey()
    }

    override func keyDown(with event: NSEvent) {
        debugWorkspaceSidebarRenameLog("panel keyDown keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "nil") firstResponder=\(String(describing: firstResponder)) inline=\(inlineTextEditingActive)")
        if handleInlineTextEditingKey(inlineTextKey(from: event)) {
            return
        }
        super.keyDown(with: event)
    }
}

final class WorkspaceSidebarHostingView: NSHostingView<WorkspaceSidebarContainerView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// The window reserves extra width for project browsing. Only the visible rail
/// gets material; hosting coordinates remain relative to the full window.
final class WorkspaceSidebarMaterialContainer: NSView {
    let effect = NSVisualEffectView()
    let customSurface = NSView()
    let clearSurface = NSView()
    let glassSurface: NSView?
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
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 0
            glass.tintColor = nil
            glass.contentView = glassContent
            glass.wantsLayer = true
            glassSurface = glass
        } else {
            glassSurface = nil
        }
        super.init(frame: frameRect)
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.material = .sidebar
        effect.isEmphasized = false
        effect.wantsLayer = true
        customSurface.wantsLayer = true
        clearSurface.wantsLayer = true
        addSubview(effect)
        addSubview(customSurface)
        addSubview(clearSurface)
        if let glassSurface { addSubview(glassSurface) }
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
            case .glass, .frosted: surface = glassSurface ?? effect
            case .opaque: surface = effect
            }
        }
        let contentParent = surface === glassSurface ? glassContent : surface
        if let content = hostedContent, content.superview !== contentParent {
            contentParent.addSubview(content)
        }
        effect.isHidden = surface !== effect || visibleWidth <= 0
        customSurface.isHidden = surface !== customSurface || visibleWidth <= 0
        clearSurface.isHidden = surface !== clearSurface || visibleWidth <= 0
        glassSurface?.isHidden = surface !== glassSurface || visibleWidth <= 0
        if system, expanded, let scheme = configuration.frostedTint.preferredColorScheme {
            // Only an explicit tint choice sets an appearance. Automatic tint
            // and custom chrome continue inheriting the system appearance.
            appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        } else if system, !reduceTransparency(),
                  let scheme = contentColorScheme ?? wallpaperTone?.colorScheme {
            appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        } else {
            appearance = nil
        }
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
        case .glass, .frosted: return glassSurface ?? effect
        case .opaque: return effect
        }
    }

    override func layout() {
        super.layout()
        updateGeometry()
    }

    private func updateGeometry() {
        let rect = workspaceSidebarVisibleFrame(panel: bounds, width: visibleWidth, position: configuration.position)
        let surface = activeSurface
        surface.frame = rect
        if surface === glassSurface { glassContent.frame = CGRect(origin: .zero, size: rect.size) }
        hostedContent?.frame = CGRect(x: -rect.minX, y: 0, width: bounds.width, height: bounds.height)
        let progress = configuration.transparentExpansionProgress(visibleWidth: rect.width)
        let radius = progress < workspaceSidebarRowsRevealProgress ? 0 : workspaceSidebarPanelRightCornerRadius
        let path = WorkspaceSidebarPanelShape(rightCornerRadius: radius, position: configuration.position)
            .path(in: CGRect(origin: .zero, size: rect.size)).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clippingLayer.frame = CGRect(origin: .zero, size: rect.size)
        clippingLayer.path = path
        surface.layer?.mask = clippingLayer
        CATransaction.commit()
    }
}
