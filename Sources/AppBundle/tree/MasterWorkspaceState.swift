import AppKit
import Common

/// Everything the Master arrangement keeps for a workspace.
struct MasterWorkspaceState {
    /// The main group, followed as groups come and go, and its last known place among them.
    weak var mainGroup: TreeNode?
    var savedGroupIndex = 0
    /// The main group's share of the display; nil uses `master.size`.
    var ratio: CGFloat?
}
