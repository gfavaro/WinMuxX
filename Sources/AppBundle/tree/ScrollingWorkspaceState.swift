import AppKit
import Common

/// Everything the Scrolling arrangement keeps for a workspace. A value, so a preview can lay the
/// strip out as it would be and put all of it back.
struct ScrollingWorkspaceState {
    /// Changes with the arrangement or display, ending anything begun on the strip before.
    var sessionEpoch: UInt64 = 0
    /// A column held at a screen edge, full height, while the rest of the strip scrolls.
    weak var pinnedNode: TreeNode?
    var pinSide = ScrollingPinCmdArgs.Side.left
    /// The viewport: how far the strip's left edge is scrolled along the columns.
    var offset: CGFloat = 0
    /// The window the strip last scrolled to, so focus scrolls it only when focus moves.
    var lastFocusWindowId: UInt32?
    /// Where the anchor window's column sat in the viewport, so the strip keeps it there when
    /// columns change width or the display does.
    var anchorWindowId: UInt32?
    var anchorViewportPosition: CGFloat?
    var anchorAreaWidth: CGFloat?
    var anchorLogicalCenter: CGFloat?
    /// While fingers pan the strip, layouts write each step straight to the windows instead of
    /// gliding to it, so the columns keep up with the fingers.
    var gestureMotionActive = false
    var gestureSessionID: UUID?
}
