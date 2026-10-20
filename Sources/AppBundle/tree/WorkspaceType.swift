import AppKit
import Common

final class Workspace: TreeNode, NonLeafTreeNodeObject, Hashable, Comparable {
    let id: WorkspaceId
    private(set) var name: String
    nonisolated private var nameLogicalSegments: StringLogicalSegments
    private(set) var namingStyle: WorkspaceNamingStyle = .explicit
    var projectId: WorkspaceProjectId = workspaceProjectDefaultId
    var restoredDisplayIndex: Int?
    var preferredMonitorPoint: CGPoint?
    var lifecycle: WorkspaceLifecycle = .durable
    var lastConfiguredLayout: WorkspaceLayoutSettings?

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
        ensureConfiguredMinimumWorkspaces()
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
