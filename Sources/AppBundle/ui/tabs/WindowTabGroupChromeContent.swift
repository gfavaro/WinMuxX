import CoreGraphics

struct WindowTabGroupChromeContent: Equatable {
    let theme: AppAppearance
    let workspaceName: String
    let activeWindowId: UInt32?
    let activeWindowCornerRadius: CGFloat
    let tabs: [WindowTabItemViewModel]
    let occludingFloatingWindowFrames: [CGRect]
    let chromeStyle: ChromeStyle
    let solidChromeColor: ChromeSolidColor
    let solidChromeCustomColor: String
    let frostedTint: WorkspaceSidebarFrostedTint
    let shownWindowIds: Set<UInt32>
    let headerHeight: CGFloat

    @MainActor init(strip: WindowTabStripViewModel) {
        shownWindowIds = strip.shownWindowIds
        headerHeight = strip.headerHeight
        theme = config.appearance
        workspaceName = strip.workspaceName
        activeWindowId = strip.activeWindowId
        activeWindowCornerRadius = strip.activeWindowCornerRadius
        tabs = strip.tabs
        occludingFloatingWindowFrames = strip.occludingFloatingWindowFrames
        chromeStyle = config.workspaceSidebar.chromeStyle
        solidChromeColor = config.workspaceSidebar.solidChromeColor
        solidChromeCustomColor = config.workspaceSidebar.solidChromeCustomColor
        frostedTint = config.workspaceSidebar.frostedTint
    }
}
