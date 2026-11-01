import AppKit
import Common
import NativeSpaces
import SwiftUI

private let switcherPalettePanelId = "WinMux.switcherPalette"
private let switcherPaletteWidth: CGFloat = 560
private let switcherPaletteMaxHeight: CGFloat = 440

struct SwitcherPaletteItem: Identifiable {
    let id: UInt32
    let title: String
    let appName: String
    let icon: NSImage?
    let workspaceName: String
    let isFocused: Bool
    var workspaceTitle: String? = nil
    var projectName: String? = nil
}

// MARK: - Panel

@MainActor
final class SwitcherPaletteModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { selection = 0 } }
    }
    @Published var selection = 0
    @Published var groupByWorkspace = false {
        didSet { if groupByWorkspace != oldValue { selection = 0 } }
    }
    var items: [SwitcherPaletteItem] = []
    var onSelect: ((UInt32) -> Void)? = nil

    var results: [SwitcherPaletteItem] {
        let matches = filterSwitcherPaletteItems(items, query: query)
        return groupByWorkspace ? groupSwitcherPaletteItems(matches, workspaceOrder: items) : matches
    }

    var selectedResultId: UInt32? {
        get {
            let current = results
            return current.indices.contains(selection) ? current[selection].id : nil
        }
        set {
            guard let id = newValue, let index = results.firstIndex(where: { $0.id == id }) else { return }
            if selection != index { selection = index }
        }
    }

    func moveSelection(_ delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        selection = min(max(selection + delta, 0), count - 1)
    }

    func selectCurrent() {
        select(at: selection)
    }

    func select(at index: Int) {
        let results = results
        guard results.indices.contains(index) else { return }
        onSelect?(results[index].id)
    }
}

@MainActor
final class SwitcherPalettePanel: NSPanelHud {
    static let shared = SwitcherPalettePanel()
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    /// Building the view took ~35 ms of each open, so a closed palette keeps its view and
    /// rows for `heldContentLifetime`; reopening within it only updates what changed.
    private var hasPaletteView = false
    private let heldContentLifetime: Duration
    private var pendingRelease: Task<Void, Never>?
    private let model: SwitcherPaletteModel
    private(set) var isPaletteActive = false
    private var outsideClickMonitors: [Any] = []
    private var presentationGeneration: UInt64 = 0
    private let loadItems: @MainActor () async -> [SwitcherPaletteItem]
    private let nativePresentation: Bool
    private let observeOutsideClicks: (@MainActor (@escaping @MainActor () -> Void) -> [Any])?
    private let removeMonitor: @MainActor (Any) -> Void

    var ownedMonitorCount: Int { outsideClickMonitors.count }

    init(model: SwitcherPaletteModel = SwitcherPaletteModel(),
         loadItems: (@MainActor () async -> [SwitcherPaletteItem])? = nil,
         nativePresentation: Bool = true,
         observeOutsideClicks: (@MainActor (@escaping @MainActor () -> Void) -> [Any])? = nil,
         removeMonitor: @escaping @MainActor (Any) -> Void = { NSEvent.removeMonitor($0) },
         heldContentLifetime: Duration = .seconds(30)) {
        self.model = model
        self.heldContentLifetime = heldContentLifetime
        self.loadItems = loadItems ?? { await buildSwitcherPaletteItems() }
        self.nativePresentation = nativePresentation
        self.observeOutsideClicks = observeOutsideClicks
        self.removeMonitor = removeMonitor
        super.init()
        identifier = NSUserInterfaceItemIdentifier(switcherPalettePanelId)
        hasShadow = true
        isFloatingPanel = true
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        backgroundColor = .clear
        applyWinMuxLayer(.overlay)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
    }

    func toggle(groupByWorkspace: Bool = false) async {
        if isPaletteActive { dismiss() } else { await show(groupByWorkspace: groupByWorkspace) }
    }

    func show(groupByWorkspace: Bool = false) async {
        guard !isPaletteActive else { return }
        pendingRelease?.cancel()
        pendingRelease = nil
        if nativePresentation { WorkspaceOverviewController.shared.dismiss(restoreFocus: false) }
        presentationGeneration &+= 1
        let generation = presentationGeneration
        isPaletteActive = true
        runtime.publicState.paletteVisible = true
        requestPublicStateUpdate()
        let items = await loadItems()
        // Palette construction suspends while first-sight window titles are fetched. A second
        // toggle may have dismissed the palette in the meantime.
        guard isPaletteActive, presentationGeneration == generation else { return }
        model.items = items
        model.objectWillChange.send()
        model.groupByWorkspace = groupByWorkspace
        model.query = ""
        model.selection = 0
        model.onSelect = { [weak self] id in self?.select(id) }
        guard nativePresentation else {
            installOutsideClickMonitors()
            return
        }
        let monitorRect = focus.workspace.workspaceMonitor.visibleRect
        // Center horizontally on the focused monitor, top edge at ~1/4 of its height
        // (converting top-left-origin coordinates back to AppKit's bottom-left origin).
        setFrame(
            NSRect(
                x: monitorRect.topLeftX + (monitorRect.width - switcherPaletteWidth) / 2,
                y: appKitScreenMaxY() - monitorRect.topLeftY - monitorRect.height * 0.25 - switcherPaletteMaxHeight,
                width: switcherPaletteWidth,
                height: switcherPaletteMaxHeight,
            ),
            display: true,
            animate: false,
        )
        if !hasPaletteView {
            hasPaletteView = true
            hostingView.rootView = AnyView(SwitcherPaletteView(model: model, dismiss: { [weak self] in self?.dismiss() }))
        }
        orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        makeKey()
        // A new field focuses itself once; a kept one is focused on every open.
        if let field = hostingView.firstDescendant(ofType: NativeSearchField.self) { makeFirstResponder(field) }
        installOutsideClickMonitors()
    }

    private func installOutsideClickMonitors() {
        for monitor in outsideClickMonitors { removeMonitor(monitor) }
        outsideClickMonitors.removeAll()
        let generation = presentationGeneration
        let dismissCurrent: @MainActor () -> Void = { [weak self] in
            guard let self, self.isPaletteActive, self.presentationGeneration == generation else { return }
            self.dismiss()
        }
        if let observeOutsideClicks {
            outsideClickMonitors = observeOutsideClicks(dismissCurrent)
            return
        }
        guard nativePresentation else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            if let self, event.window !== self { dismissCurrent() }
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { _ in
            Task { @MainActor in dismissCurrent() }
        }
        outsideClickMonitors = [local, global].compactMap { $0 }
    }

    func dismiss() {
        presentationGeneration &+= 1
        for monitor in outsideClickMonitors { removeMonitor(monitor) }
        outsideClickMonitors.removeAll()
        if isPaletteActive {
            isPaletteActive = false
            runtime.publicState.paletteVisible = false
            requestPublicStateUpdate()
            orderOut(nil)
        }
        model.onSelect = nil
        if !model.query.isEmpty { model.query = "" }
        if model.selection != 0 { model.selection = 0 }
        guard pendingRelease == nil, hasPaletteView || !model.items.isEmpty else { return }
        let lifetime = heldContentLifetime
        pendingRelease = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: lifetime) } catch { return }
            self?.releaseHeldContent()
        }
    }

    /// Drops the rows, their icons and the view tree of a palette not reopened in time.
    func releaseHeldContent() {
        pendingRelease?.cancel()
        pendingRelease = nil
        guard !isPaletteActive else { return }
        model.items = []
        model.objectWillChange.send()
        hostingView.rootView = AnyView(EmptyView())
        hasPaletteView = false
    }

    private func select(_ windowId: UInt32) {
        dismiss()
        Task { @MainActor in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.menuBarButton, token) {
                if let error = try await runtime.workspaceBackend.current.bringForward(windowId) {
                    MessageModel.shared.message = Message(description: "Palette", body: error)
                }
            }
        }
    }

    // Only quick-select is panel-wide. Editing/navigation belongs to the search
    // field delegate or the native list; input-method candidates always take priority.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, isPaletteActive,
           let index = paletteQuickSelectIndex(characters: event.charactersIgnoringModifiers,
                modifiers: event.modifierFlags, hasMarkedText: overlayHasMarkedText(firstResponder)) {
            model.select(at: index)
            return
        }
        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        guard isPaletteActive, !overlayHasMarkedText(firstResponder),
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
            super.keyDown(with: event); return
        }
        switch event.keyCode {
        case 53: dismiss()
        case 36, 76: model.selectCurrent()
        default: super.keyDown(with: event)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private func appKitScreenMaxY() -> CGFloat {
    NSScreen.screens.first?.frame.maxY ?? 0
}

@MainActor
private func buildSwitcherPaletteItems() async -> [SwitcherPaletteItem] {
    let focusedWindowId = focus.windowOrNil?.windowId
    let focusedWorkspace = focus.workspace
    // Focused workspace first, then the rest — so an empty query shows nearby windows on top.
    let candidates = runtime.workspaceBackend.current.listedWorkspaces(.all)
    // A focused workspace outside the listing (a native fullscreen Space) adds nothing.
    let workspaces = candidates.contains(focusedWorkspace)
        ? [focusedWorkspace] + candidates.filter { $0 != focusedWorkspace }
        : candidates
    let indexedWindows = workspaces.flatMap { workspace in
        workspace.allLeafWindowsRecursive.filter(\.isBound).map { (window: $0, workspaceName: workspace.name) }
    }
    var items = [SwitcherPaletteItem?](repeating: nil, count: indexedWindows.count)
    await withTaskGroup(of: (Int, SwitcherPaletteItem).self) { group in
        for (index, entry) in indexedWindows.enumerated() {
            group.addTask { @Sendable @MainActor in
                (index, await makeSwitcherPaletteItem(
                    window: entry.window,
                    workspaceName: entry.workspaceName,
                    focusedWindowId: focusedWindowId,
                ))
            }
        }
        for await (index, item) in group {
            items[index] = item
        }
    }
    return items.compactMap { $0 } + runtime.workspaceBackend.ui.extraPaletteItems()
}

/// Windows on desktops not showing yet; choosing one switches there first.
@MainActor
func nativeListedPaletteItems() -> [SwitcherPaletteItem] {
    let displays = nativeObservedDisplays() ?? []
    return NativeUnvisitedWindows.shared.bySpaceID.flatMap { space, windows -> [SwitcherPaletteItem] in
        guard let number = NativeSpaceNavigation.desktopNumber(of: space, in: displays) else { return [] }
        return windows.map { listed in
            let app = NSRunningApplication(processIdentifier: listed.pid)
            let appName = app?.localizedName ?? app?.bundleIdentifier ?? "Unknown"
            return SwitcherPaletteItem(id: listed.windowId, title: listed.title ?? appName, appName: appName, icon: app?.icon,
                workspaceName: "", isFocused: false, workspaceTitle: nativeDesktopDisplayName(number))
        }
    }
}

@MainActor
func makeSwitcherPaletteItem(
    window: Window,
    workspaceName: String,
    focusedWindowId: UInt32?,
) async -> SwitcherPaletteItem {
    let appName = window.app.name ?? window.app.rawAppBundleId ?? "Unknown"
    let backend = runtime.workspaceBackend.current
    let workspaceTitle = backend.title(ofWorkspaceNamed: workspaceName)
    let projectName = runtime.workspaceBackend.ui.hasProjects ? Workspace.existing(byName: workspaceName).map { workspaceProjectName($0.projectId) } : nil
    // A cold cache previously indexed every Finder window as only "Finder" until some other
    // UI happened to fetch its title. Fetch first-sight titles before showing the palette so
    // folder names are searchable immediately; known stale titles still return instantly and
    // refresh in the background.
    let title = await getSessionWindowTitle(window) ?? appName
    return SwitcherPaletteItem(
        id: window.windowId,
        title: title,
        appName: appName,
        icon: (window as? MacWindow)?.macApp.nsApp.icon,
        workspaceName: workspaceName,
        isFocused: window.windowId == focusedWindowId,
        workspaceTitle: workspaceTitle,
        projectName: projectName,
    )
}

// MARK: - Fuzzy matching

func switcherPaletteFuzzyScore(_ needle: String, in haystack: String) -> Int? {
    var score = 0
    var previousMatched = false
    var previousChar: Character? = nil
    var index = haystack.startIndex
    for char in needle {
        var found = false
        while index < haystack.endIndex {
            let candidate = haystack[index]
            let isWordStart = previousChar == nil || previousChar == " " || previousChar == "-" || previousChar == "." || previousChar == "/"
            previousChar = candidate
            index = haystack.index(after: index)
            if candidate == char {
                score += previousMatched ? 2 : (isWordStart ? 3 : 1)
                previousMatched = true
                found = true
                break
            }
            previousMatched = false
        }
        if !found { return nil }
    }
    return score
}

func filterSwitcherPaletteItems(_ items: [SwitcherPaletteItem], query: String) -> [SwitcherPaletteItem] {
    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !needle.isEmpty else { return items }
    return items
        .compactMap { item in
            switcherPaletteFuzzyScore(needle, in: "\(item.appName) \(item.title) \(item.workspaceName) \(item.workspaceTitle ?? "") \(item.projectName ?? "")".lowercased())
                .map { (item, $0) }
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
}

// MARK: - View

struct SwitcherPaletteView: View {
    @ObservedObject var model: SwitcherPaletteModel
    let dismiss: () -> Void

    var body: some View {
        let results = model.results
        let selectedId = results.indices.contains(model.selection) ? results[model.selection].id : nil
        let sections = model.groupByWorkspace ? paletteResultSections(results) : []
        let indices = Dictionary(uniqueKeysWithValues: results.enumerated().map { ($0.element.id, $0.offset) })
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                PaletteSearchField(text: $model.query) { command in
                    switch command {
                    case .previous: model.moveSelection(-1)
                    case .next: model.moveSelection(1)
                    case .activate: model.selectCurrent()
                    case .dismiss: dismiss()
                    }
                }
                .frame(maxWidth: .infinity)
                Toggle(isOn: $model.groupByWorkspace) {
                    Label("Group by workspace", systemImage: "rectangle.3.group")
                }
                .labelStyle(.iconOnly)
                .toggleStyle(.button)
                .help("Group by workspace")
                .accessibilityLabel("Group by workspace")
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Divider()

            ScrollViewReader { proxy in
                List(selection: Binding(get: { selectedId }, set: { model.selectedResultId = $0 })) {
                    if model.groupByWorkspace {
                        ForEach(sections, id: \.workspace) { section in
                            Section {
                                ForEach(section.items) { item in
                                    resultRow(item, index: indices[item.id] ?? 0, selected: selectedId == item.id)
                                }
                            } header: {
                                HStack {
                                    Text(section.items.first?.workspaceTitle ?? section.workspace)
                                    Spacer()
                                    if let project = section.items.first?.projectName { Text(project) }
                                }
                            }
                        }
                    } else {
                        ForEach(results) { item in resultRow(item, index: indices[item.id] ?? 0, selected: selectedId == item.id) }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Window results")
                .overlay {
                    if results.isEmpty {
                        Text("No matching windows").foregroundStyle(.secondary).allowsHitTesting(false)
                    }
                }
                .onChange(of: selectedId) { id in
                    if let id { proxy.scrollTo(id, anchor: nil) }
                }
            }
            .frame(height: switcherPaletteMaxHeight - 44)
        }
        .frame(width: switcherPaletteWidth)
        .background {
            OverlaySurface(cornerRadius: systemWindowCornerRadius())
        }
        .clipShape(RoundedRectangle(cornerRadius: systemWindowCornerRadius(), style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(OverlayAppearance())
    }

    private func resultRow(_ item: SwitcherPaletteItem, index: Int, selected: Bool) -> some View {
        Button { model.select(at: index) } label: {
            SwitcherPaletteRow(item: item, hotkeyLabel: index < 9 ? "⌘\(index + 1)" : nil)
        }
        .buttonStyle(.plain)
        .tag(item.id)
        .id(item.id)
        .listRowSeparator(.hidden)
        .accessibilityLabel("\(item.appName): \(item.title), workspace \(item.workspaceTitle ?? item.workspaceName)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Open this window")
    }
}

struct PaletteResultSection {
    let workspace: String
    var items: [SwitcherPaletteItem]
}

/// Results are already ranked/grouped. Preserve that order, including quick-select indices.
func paletteResultSections(_ results: [SwitcherPaletteItem]) -> [PaletteResultSection] {
    var sections: [PaletteResultSection] = []
    for item in results {
        if sections.last?.workspace == item.workspaceName {
            sections[sections.count - 1].items.append(item)
        } else {
            sections.append(PaletteResultSection(workspace: item.workspaceName, items: [item]))
        }
    }
    return sections
}

private struct SwitcherPaletteRow: View {
    let item: SwitcherPaletteItem
    let hotkeyLabel: String?

    var body: some View {
        HStack(spacing: 8) {
            if let icon = item.icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18).accessibilityHidden(true)
            } else {
                Image(systemName: "macwindow").frame(width: 18, height: 18).accessibilityHidden(true)
            }
            Text(item.title).font(.body).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            if let hotkeyLabel {
                Text(hotkeyLabel).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 26)
        .contentShape(Rectangle())
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T ?? subview.firstDescendant(ofType: type) { return match }
        }
        return nil
    }
}
