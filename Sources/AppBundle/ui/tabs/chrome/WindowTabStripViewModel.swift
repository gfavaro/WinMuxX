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

    var tabStripIsOccludedByFloatingWindow: Bool {
        occludingFloatingWindowFrames.contains { $0.intersects(frame) }
    }

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
