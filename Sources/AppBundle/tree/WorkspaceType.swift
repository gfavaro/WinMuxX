import AppKit
import Common

final class Workspace: TreeNode, NonLeafTreeNodeObject, Hashable, Comparable {
    let id: WorkspaceId
    private(set) var name: String
    nonisolated private var nameLogicalSegments: StringLogicalSegments
    private(set) var namingStyle: WorkspaceNamingStyle = .explicit
    var projectId: WorkspaceProjectId = workspaceProjectDefaultId
    var restoredDisplayIndex: Int?
    var preferredMonitorPoint: CGPoint? {
        didSet { if oldValue != preferredMonitorPoint { scrollingSessionEpoch &+= 1 } }
    }
    var lifecycle: WorkspaceLifecycle = .durable
    var lastConfiguredLayout: WorkspaceLayoutSettings?
    // Once workspace arrangements are used, returning to Dwindle must retain
    // the same group boundaries rather than rerun the legacy tree migration.
    var preservesTopLevelGroups = false
    var arrangement: WorkspaceLayoutName = .dwindle {
        didSet {
            if arrangement != .dwindle { preservesTopLevelGroups = true }
            if oldValue != arrangement { scrollingSessionEpoch &+= 1 }
        }
    }
    var scrollingSessionEpoch: UInt64 = 0
    var scrollingOffset: CGFloat = 0
    /// A column held at a screen edge, full height, while the rest of the strip scrolls.
    weak var scrollingPinnedNode: TreeNode?
    var scrollingPinSide = ScrollingPinCmdArgs.Side.left
    var lastScrollingFocusWindowId: UInt32?
    var scrollingAnchorWindowId: UInt32?
    var scrollingAnchorViewportPosition: CGFloat?
    var scrollingAnchorAreaWidth: CGFloat?
    @MainActor var scrollingGestureMotionActive = false
    @MainActor var scrollingGestureSessionID: UUID?
    private var savedMasterGroupIndex = 0
    private weak var masterGroup: TreeNode?
    @MainActor var nativePersistentMasterGroupIndex: Int {
        masterGroup.flatMap { selected in rootTilingContainer.children.firstIndex { $0 === selected } }
            ?? min(max(savedMasterGroupIndex, 0), max(rootTilingContainer.children.count - 1, 0))
    }

    @MainActor func restoreNativeMasterGroupIndex(_ index: Int) {
        savedMasterGroupIndex = index
        let groups = rootTilingContainer.children
        masterGroup = groups.indices.contains(index) ? groups[index] : nil
    }

    @MainActor var masterGroupIndex: Int {
        get {
            let groups = workspaceLayoutUnits
            let index = masterGroup.flatMap { selected in groups.firstIndex { $0 === selected } }
                ?? min(max(savedMasterGroupIndex, 0), max(groups.count - 1, 0))
            if runtime.workspaceBackend.kind == .native, let masterGroup,
               masterGroup.nodeWorkspace === self, !masterGroup.hasNativeLayoutWindow { return index }
            savedMasterGroupIndex = index
            masterGroup = groups.indices.contains(index) ? groups[index] : nil
            return index
        }
        set {
            savedMasterGroupIndex = newValue
            let groups = workspaceLayoutUnits
            masterGroup = groups.indices.contains(newValue) ? groups[newValue] : nil
        }
    }
    var masterRatio: CGFloat?
    var masterStackLayout: Layout = .tiles

    @MainActor
    private init(_ name: String) {
        self.id = runtime.workspaces.nextWorkspaceId()
        self.name = name
        self.nameLogicalSegments = name.toLogicalSegments()
        super.init(parent: NilTreeNode.instance, adaptiveWeight: 0, index: 0)
    }

    @MainActor static var all: [Workspace] {
        runtime.workspaces.sortedWorkspaces()
    }

    @MainActor static func get(byName name: String) -> Workspace {
        if let existing = runtime.workspaces.workspace(named: name) {
            return existing
        } else {
            let workspace = Workspace(name)
            runtime.workspaces.registerWorkspace(workspace)
            return workspace
        }
    }

    @MainActor static func existing(byName name: String) -> Workspace? {
        runtime.workspaces.workspace(named: name)
    }

    nonisolated static func < (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.nameLogicalSegments < rhs.nameLogicalSegments
    }

    override func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        workspaceMonitor.visibleRectPaddedByOuterGaps.getDimension(targetOrientation)
    }

    override func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        die("It's not possible to change weight of Workspace")
    }

    @MainActor
    var description: String {
        let description = [
            ("id", id.rawValue),
            ("name", name),
            ("projectId", projectId.rawValue),
            ("lifecycle", lifecycle.rawValue),
            ("isVisible", String(isVisible)),
            ("isEffectivelyEmpty", String(isEffectivelyEmpty)),
            ("namingStyle", namingStyle.rawValue),
        ].map { "\($0.0): '\(String(describing: $0.1))'" }.joined(separator: ", ")
        return "Workspace(\(description))"
    }

    @MainActor
    static func reconcileWorkspaceState() {
        materializePersistedWorkspaces()
        for workspace in runtime.workspaces.workspaceById.values {
            workspace.refreshEmptyLifecycle()
        }
        runtime.workspaces.pruneProjectWorkspaceIndexes()
        repairInvalidVisibleWorkspaceAssignments()
        rearrangeWorkspacesOnMonitors()
        reconcileSecondaryWorkspaceAssignments()
        ensureMinimumWorkspaceForAllProjects()
        pruneEmptyWorkspaces()
        clearOrphanedWorkspaceSidebarLabels()
        ensureVisibleActiveProjectWorkspaces()
        checkWorkspaceHierarchyInvariants(requireActiveMonitorViewports: true)
    }

    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        return lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

}

extension Workspace {
    @MainActor
    var scrollingTopologySignature: String {
        let bounds = workspaceTilingRect(self)
        var values: [String] = [arrangement.rawValue, id.rawValue,
            "\(bounds.minX),\(bounds.minY),\(bounds.width),\(bounds.height)"]
        func visit(_ node: TreeNode) {
            values.append("\(ObjectIdentifier(node).hashValue):\(node.bindingGeneration):\(node.children.count):\(node.scrollingColumnWidth ?? config.scrolling.columnWidth)")
            if let window = node as? Window {
                values.append("\(window.minimumLayoutSize.width),\(window.minimumLayoutSize.height)")
            }
            node.children.forEach(visit)
        }
        visit(rootTilingContainer)
        return values.joined(separator: ",")
    }
}

extension Workspace {
    @MainActor
    func seedMonitorIfNeeded(_ monitor: Monitor) {
        if preferredMonitorPoint == nil {
            preferredMonitorPoint = (forceAssignedMonitor ?? monitor).rect.topLeftCorner
        }
    }

    @MainActor
    func assignProject(_ projectId: WorkspaceProjectId) {
        guard self.projectId != projectId else { return }
        restoredDisplayIndex = nil
        runtime.workspaces.assignWorkspace(self, to: projectId)
    }

    @MainActor
    func markAsSidebarManaged() {
        markAsAutomaticallyNamed()
        lifecycle = .durable
    }

    @MainActor
    func markAsTransientBlank() {
        markAsAutomaticallyNamed()
        lifecycle = .transient
    }

    @MainActor
    func markAsAutomaticallyNamed() {
        namingStyle = .automatic
    }

    @MainActor
    func restoreNamingStyle(_ namingStyle: WorkspaceNamingStyle) {
        self.namingStyle = namingStyle
    }

    @MainActor
    func refreshEmptyLifecycle() {
        if workspaceHasLifecycleWindows(self), lifecycle == .transient {
            lifecycle = .durable
        }
    }

    @MainActor
    var isConfiguredPersistent: Bool {
        config.persistentWorkspaces.contains(name)
    }

    @MainActor
    var isOrdinaryEmptySlot: Bool {
        !workspaceHasLifecycleWindows(self) && !isConfiguredPersistent
    }

    var usesAutomaticDisplayName: Bool {
        namingStyle == .automatic
    }

    @MainActor
    var isVisible: Bool {
        runtime.workspaces.monitorViewportsById.values.contains { $0.activeWorkspaceId == id }
    }
    @MainActor
    var assignedMonitor: Monitor? {
        visibleMonitor ?? forceAssignedMonitor ?? preferredMonitorPoint?.monitorApproximation
    }

    @MainActor
    var workspaceMonitor: Monitor {
        assignedMonitor ?? focus.workspace.visibleMonitor ?? mainMonitor
    }

    @MainActor
    var visibleMonitor: Monitor? {
        runtime.workspaces.monitorViewportsById.first { _, viewport in
            viewport.activeWorkspaceId == id
        }?.key.topLeftCorner.monitorApproximation
    }

    @MainActor
    var preferredMonitorPointForTesting: CGPoint? {
        visibleMonitor?.rect.topLeftCorner ?? forceAssignedMonitor?.rect.topLeftCorner ?? preferredMonitorPoint
    }

    var isArchived: Bool {
        lifecycle == .archived
    }
}
