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
        didSet { if oldValue != preferredMonitorPoint { scrollingState.sessionEpoch &+= 1 } }
    }
    var lifecycle: WorkspaceLifecycle = .durable
    var lastConfiguredLayout: WorkspaceLayoutSettings?
    // Once workspace arrangements are used, returning to Dwindle must retain
    // the same group boundaries rather than turn their Tiles splits into Dwindle ones.
    var preservesTopLevelGroups = false
    /// What the Tabbed arrangement keeps for this workspace, kept while other arrangements show.
    @MainActor var tabbedState = TabbedWorkspaceState()
    var arrangement: WorkspaceLayoutName = .dwindle {
        didSet {
            if arrangement != .dwindle { preservesTopLevelGroups = true }
            if oldValue != arrangement { scrollingState.sessionEpoch &+= 1 }
        }
    }
    /// What the Scrolling arrangement keeps for this workspace.
    var scrollingState = ScrollingWorkspaceState()
    /// What the Master arrangement keeps for this workspace.
    var masterState = MasterWorkspaceState()
    /// The main group's place among the groups. The group itself is followed, so the main window
    /// stays main when groups before it come and go.
    @MainActor var masterGroupIndex: Int {
        get {
            let groups = workspaceLayoutUnits
            let index = masterState.mainGroup.flatMap { selected in groups.firstIndex { $0 === selected } }
                ?? min(max(masterState.savedGroupIndex, 0), max(groups.count - 1, 0))
            masterState.savedGroupIndex = index
            masterState.mainGroup = groups.indices.contains(index) ? groups[index] : nil
            return index
        }
        set {
            masterState.savedGroupIndex = newValue
            let groups = workspaceLayoutUnits
            masterState.mainGroup = groups.indices.contains(newValue) ? groups[newValue] : nil
        }
    }

    @MainActor
    private init(_ name: String) {
        self.id = runtime.workspaces.nextWorkspaceId()
        self.name = name
        self.nameLogicalSegments = name.toLogicalSegments()
        super.init(parent: NilTreeNode.instance, adaptiveWeight: 0, index: 0)
        // Restored and configured workspaces set their own arrangement after this.
        if config.defaultWorkspaceScrolling { arrangement = .scrolling }
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
        rearrangeWorkspacesOnMonitors()
        showAssignedWorkspacesOnTheirDisplays()
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
}

extension Workspace {
    @MainActor
    func seedMonitorIfNeeded(_ monitor: Monitor) {
        if preferredMonitorPoint == nil {
            preferredMonitorPoint = monitor.rect.topLeftCorner
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
        visibleMonitor?.rect.topLeftCorner ?? preferredMonitorPoint
    }

    var isArchived: Bool {
        lifecycle == .archived
    }
}
