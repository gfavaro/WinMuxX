import CoreGraphics
@testable import AppBundle

/// The made-up projects, workspaces and windows the pictures show.
@MainActor
enum MarketingFixtures {
    private final class Identity {}

    private static let editorGroup = Identity()
    private static let workspaceBar = Identity()
    private static let work = WorkspaceProjectId(rawValue: "work")
    static let tabBarHeight: CGFloat = 36

    static let sidebarSnapshot = sidebar(visibleWidth: 260)

    static func sidebar(visibleWidth: CGFloat) -> WorkspaceSidebarSnapshot {
        WorkspaceSidebarSnapshot(
            workspaces: [
                workspace("website", "Website", label: "W", focused: true, items: [
                    .init(kind: .tabGroup(.init(
                        representativeWindowId: 101,
                        workspaceName: "website",
                        title: "Layout.swift",
                        windowCount: 2,
                        isFocused: true,
                        tabs: [
                            window(101, "website", app: "Xcode", bundle: "com.apple.dt.Xcode", title: "Layout.swift", focused: true),
                            window(102, "website", app: "Terminal", bundle: "com.apple.Terminal", title: "fieldnotes — zsh"),
                        ]
                    ))),
                    .init(kind: .window(window(103, "website", app: "Safari", bundle: "com.apple.Safari", title: "Field Notes"))),
                    .init(kind: .window(window(104, "website", app: "Notes", bundle: "com.apple.Notes", title: "Weekly plan"))),
                ]),
                workspace("docs", "Docs", label: "D", items: [
                    .init(kind: .window(window(201, "docs", app: "TextEdit", bundle: "com.apple.TextEdit", title: "Release notes"))),
                    .init(kind: .window(window(202, "docs", app: "Preview", bundle: "com.apple.Preview", title: "Style guide.pdf"))),
                ]),
                workspace("research", "Research", label: "R", items: [
                    .init(kind: .window(window(301, "research", app: "Safari", bundle: "com.apple.Safari", title: "Reading list"))),
                ]),
            ],
            projects: [
                WorkspaceSidebarProjectViewModel(id: work, displayName: "Work", colorHex: "#7C6CF2"),
                WorkspaceSidebarProjectViewModel(id: "personal", displayName: "Personal", colorHex: "#58A6FF"),
            ],
            activeProjectId: work,
            monitorScopes: [
                WorkspaceSidebarMonitorScopeViewModel(id: "default", displayName: "All Displays", subtitle: nil,
                                                      systemImageName: "display.2", isFocusedMonitor: true),
            ],
            selectedMonitorScopeId: "default",
            targetMonitorScopeId: "display-main",
            focusedMonitorScopeId: "display-main",
            visibleWidth: visibleWidth,
            hoveredWorkspaceName: nil,
            dropPreview: nil,
            configuration: WorkspaceSidebarConfiguration(
                collapsedWidth: 44,
                expandedWidth: 260,
                topPadding: 12,
                showMonitorSelector: true,
                showsClock: true,
                showsSeconds: false,
                showsDate: true,
                showsWeekday: true,
                showsStatusPills: true,
                chromeStyle: .liquidGlass,
                solidChromeColor: .midnight,
                solidChromeCustomColor: "#191B20"
            )
        )
    }

    /// The editor and terminal sharing one tile.
    static let editorTabs = strip(editorGroup, activeWindowId: 101, tabs: [
        tab(101, app: "Xcode", bundle: "com.apple.dt.Xcode", title: "Layout.swift", active: true),
        tab(102, app: "Terminal", bundle: "com.apple.Terminal", title: "fieldnotes — zsh"),
    ])

    /// A Tabbed workspace's bar: every window of the workspace is one tab.
    static let workspaceTabs: WindowTabStripViewModel = {
        var bar = strip(workspaceBar, activeWindowId: 103, tabs: [
            tab(101, app: "Xcode", bundle: "com.apple.dt.Xcode", title: "Layout.swift"),
            tab(103, app: "Safari", bundle: "com.apple.Safari", title: "Field Notes", active: true),
            tab(104, app: "Notes", bundle: "com.apple.Notes", title: "Weekly plan"),
            tab(102, app: "Terminal", bundle: "com.apple.Terminal", title: "fieldnotes — zsh"),
        ])
        bar.isWorkspaceTabs = true
        return bar
    }()

    private static func workspace(_ name: String, _ displayName: String, label: String, focused: Bool = false,
                                  items: [WorkspaceSidebarItemViewModel]) -> WorkspaceSidebarWorkspaceViewModel {
        WorkspaceSidebarWorkspaceViewModel(
            name: name, projectId: work, displayName: displayName, sidebarLabel: label, isGeneratedName: false,
            monitorScopeId: "display-main", monitorName: nil, isFocused: focused, isVisible: focused, items: items
        )
    }

    private static func window(_ id: UInt32, _ workspace: String, app: String, bundle: String, title: String,
                               focused: Bool = false) -> WorkspaceSidebarWindowViewModel {
        WorkspaceSidebarWindowViewModel(windowId: id, workspaceName: workspace, appName: app, appBundleId: bundle,
                                        appBundlePath: nil, title: title, isFocused: focused)
    }

    private static func tab(_ id: UInt32, app: String, bundle: String, title: String, active: Bool = false) -> WindowTabItemViewModel {
        WindowTabItemViewModel(windowId: id, workspaceName: "website", appName: app, appBundleId: bundle,
                               appBundlePath: nil, title: title, isActive: active)
    }

    private static func strip(_ identity: Identity, activeWindowId: UInt32, tabs: [WindowTabItemViewModel]) -> WindowTabStripViewModel {
        WindowTabStripViewModel(
            id: ObjectIdentifier(identity),
            workspaceName: "website",
            frame: CGRect(x: 0, y: 0, width: 400, height: tabBarHeight),
            groupFrame: CGRect(x: 0, y: 0, width: 400, height: 400),
            activeWindowId: activeWindowId,
            activeWindowCornerRadius: 16,
            tabs: tabs,
            occludingFloatingWindowFrames: [],
            shownWindowIds: [activeWindowId],
            headerHeight: tabBarHeight
        )
    }
}
