import CoreGraphics

struct WindowTabStripViewModel: Identifiable, Equatable {
    let id: ObjectIdentifier
    let workspaceName: String
    let frame: CGRect
    let groupFrame: CGRect
    let activeWindowId: UInt32?
    let activeWindowCornerRadius: CGFloat
    let tabs: [WindowTabItemViewModel]
    let occludingFloatingWindowFrames: [CGRect]
    /// Windows on screen: the active tab, or every column a strip shows.
    var shownWindowIds: Set<UInt32> = []
    /// The header the group reserves above its windows: the strip's height, or none with pills.
    var headerHeight: CGFloat = 0
    /// The bar of a Tabbed workspace, whose tabs are the workspace's windows rather than a group's
    /// children: there is no group to drag as a whole or to remove a tab from.
    var isWorkspaceTabs = false

    var groupFrameIsOccludedByFloatingWindow: Bool {
        occludingFloatingWindowFrames.contains { $0.intersects(groupFrame) }
    }
}

struct WindowTabItemViewModel: Hashable, Identifiable {
    let windowId: UInt32
    let workspaceName: String
    let appName: String
    let appBundleId: String?
    let appBundlePath: String?
    let title: String
    let isActive: Bool

    var id: UInt32 { windowId }
}
