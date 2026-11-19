import SwiftUI
@testable import AppBundle

/// The pictures the renderer makes, one per WinMuxX feature.
enum MarketingScene: String, CaseIterable {
    /// The sidebar beside a Dwindle workspace with a tab group: the README and site hero.
    case overview
    /// Dwindle tiling: each new window splits the focused one.
    case dwindle
    /// A Tabbed workspace: one window at a time, every window a tab.
    case tabbed
    /// A Scrolling workspace: columns on a strip wider than the display.
    case scrolling
    /// An ultrawide display with one window at a comfortable width.
    case ultrawide

    var size: CGSize {
        self == .ultrawide ? CGSize(width: 1_600, height: 640) : CGSize(width: 1_600, height: 900)
    }

    @MainActor var view: AnyView {
        switch self {
            case .overview: AnyView(OverviewScene())
            case .dwindle: AnyView(DwindleScene())
            case .tabbed: AnyView(TabbedScene())
            case .scrolling: AnyView(ScrollingScene())
            case .ultrawide: AnyView(UltrawideScene(size: size))
        }
    }
}

/// Screen geometry shared by the scenes: menu bar, gaps and the sidebar's width.
private enum Screen {
    static let menuBar: CGFloat = 26
    static let gap: CGFloat = 10
    static let width: CGFloat = 1_600

    static func area(sidebar: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: sidebar + gap, y: menuBar + gap, width: width - sidebar - 2 * gap, height: height - menuBar - 2 * gap)
    }
}

/// A desktop with the menu bar and the sidebar at its left edge.
private struct Desktop<Windows: View>: View {
    let sidebarWidth: CGFloat
    var height: CGFloat = 900
    @ViewBuilder let windows: () -> Windows

    var body: some View {
        ZStack(alignment: .topLeading) {
            MarketingDesktop()
            windows()
            WorkspaceSidebarView(snapshot: MarketingFixtures.sidebar(visibleWidth: sidebarWidth))
                .frame(width: sidebarWidth, height: height - Screen.menuBar)
                .offset(y: Screen.menuBar)
            MarketingMenuBar()
        }
        .frame(width: Screen.width, height: height)
        .clipped()
    }
}

private extension View {
    func place(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
    }
}

private struct OverviewScene: View {
    var body: some View {
        let area = Screen.area(sidebar: 260, height: 900)
        let left = CGRect(x: area.minX, y: area.minY, width: area.width * 0.57, height: area.height)
        let right = CGRect(x: left.maxX + Screen.gap, y: area.minY, width: area.maxX - left.maxX - Screen.gap, height: area.height)
        let top = CGRect(x: right.minX, y: right.minY, width: right.width, height: right.height * 0.58)
        let bottom = CGRect(x: right.minX, y: top.maxY + Screen.gap, width: right.width, height: right.maxY - top.maxY - Screen.gap)
        return Desktop(sidebarWidth: 260) {
            MarketingTabGroupWindow(strip: MarketingFixtures.editorTabs, kind: .editor, title: "Layout.swift")
                .marketingWindow(focused: true).place(left)
            MarketingAppWindow(kind: .browser, title: "Field Notes").marketingWindow().place(top)
            MarketingAppWindow(kind: .notes, title: "Weekly plan").marketingWindow().place(bottom)
        }
    }
}

private struct DwindleScene: View {
    var body: some View {
        let area = Screen.area(sidebar: 44, height: 900)
        let half = (area.width - Screen.gap) / 2
        let left = CGRect(x: area.minX, y: area.minY, width: half, height: area.height)
        let rightX = left.maxX + Screen.gap
        let top = CGRect(x: rightX, y: area.minY, width: half, height: (area.height - Screen.gap) / 2)
        let lowerY = top.maxY + Screen.gap
        let quarter = (half - Screen.gap) / 2
        let lowerLeft = CGRect(x: rightX, y: lowerY, width: quarter, height: area.maxY - lowerY)
        let lowerRight = CGRect(x: lowerLeft.maxX + Screen.gap, y: lowerY, width: quarter, height: area.maxY - lowerY)
        return Desktop(sidebarWidth: 44) {
            MarketingAppWindow(kind: .editor, title: "Layout.swift").marketingWindow().place(left)
            MarketingAppWindow(kind: .browser, title: "Field Notes").marketingWindow(focused: true).place(top)
            MarketingAppWindow(kind: .terminal, title: "fieldnotes — zsh").marketingWindow().place(lowerLeft)
            MarketingAppWindow(kind: .notes, title: "Weekly plan").marketingWindow().place(lowerRight)
        }
    }
}

private struct TabbedScene: View {
    var body: some View {
        let area = Screen.area(sidebar: 44, height: 900)
        let barHeight = MarketingFixtures.tabBarHeight
        let bar = CGRect(x: area.minX, y: area.minY, width: area.width, height: barHeight)
        let window = CGRect(x: area.minX, y: bar.maxY + 6, width: area.width, height: area.maxY - bar.maxY - 6)
        return Desktop(sidebarWidth: 44) {
            WindowTabStripView(strip: MarketingFixtures.workspaceTabs)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .place(bar)
            MarketingAppWindow(kind: .browser, title: "Field Notes").marketingWindow(focused: true).place(window)
        }
    }
}

private struct ScrollingScene: View {
    var body: some View {
        let area = Screen.area(sidebar: 44, height: 900)
        let column = area.width * 0.46
        // The strip is wider than the display: part of the first column is scrolled away to the left
        // and the last continues past the right edge.
        let kinds: [(MarketingAppKind, String)] = [(.notes, "Weekly plan"), (.editor, "Layout.swift"),
                                                   (.browser, "Field Notes"), (.terminal, "fieldnotes — zsh")]
        let startX = area.minX - column * 0.3
        return Desktop(sidebarWidth: 44) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(kinds.enumerated()), id: \.offset) { index, item in
                    MarketingAppWindow(kind: item.0, title: item.1)
                        .marketingWindow(focused: index == 1)
                        .place(CGRect(x: startX + CGFloat(index) * (column + Screen.gap), y: area.minY, width: column, height: area.height))
                }
            }
            .frame(width: Screen.width, height: 900, alignment: .topLeading)
            .mask(Rectangle().place(CGRect(x: area.minX, y: 0, width: Screen.width - area.minX, height: 900)))
        }
    }
}

private struct UltrawideScene: View {
    let size: CGSize

    var body: some View {
        let area = Screen.area(sidebar: 44, height: size.height)
        let width = area.width * 0.55
        let window = CGRect(x: area.midX - width / 2, y: area.minY, width: width, height: area.height)
        return Desktop(sidebarWidth: 44, height: size.height) {
            MarketingAppWindow(kind: .editor, title: "Layout.swift").marketingWindow(focused: true).place(window)
        }
    }
}
