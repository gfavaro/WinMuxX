import Common

/// Everything the Tabbed arrangement keeps for a workspace.
struct TabbedWorkspaceState {
    /// The tab groups; kept while other arrangements show, so returning to Tabbed finds them again.
    var layout: TabbedLayout?
    /// The group last worked in, which windows opened later join.
    weak var lastGroup: TabbedGroup?
    /// The window last focused in this Tabbed workspace, which a group joined later shows.
    var lastFocusedWindowId: UInt32?
    /// The groups as the last layout showed them, without those folded into another's bar.
    var presentedLayout: TabbedLayout?
}
