import AppKit
import Common

/// Columns of a strip that fit inside its group. Windows cannot be clipped, so a column is
/// shown only when it fits whole; the others wait hidden, like inactive tabs, until focus
/// scrolls them in. The visible run is stretched to fill the group.
struct WindowStripGeometry: Equatable {
    let visible: Range<Int>
    let frames: [Rect]

    /// `shares` are each column's preferred width as a fraction of the group. The run moves
    /// only as far as needed to show `focused`, then widens backwards to fill any room.
    static func calculate(in rect: Rect, shares: [CGFloat], gap: CGFloat, focused: Int, firstVisible: Int) -> WindowStripGeometry {
        guard !shares.isEmpty, rect.width > 0 else { return WindowStripGeometry(visible: 0..<0, frames: []) }
        // A share includes its gap, so halves fit two columns and thirds three.
        let widths = shares.map { max(min(max($0, 0.1), 1) * (rect.width + gap) - gap, 1) }
        func end(from start: Int) -> Int {
            var used = widths[start]
            var end = start + 1
            while end < widths.count, used + gap + widths[end] <= rect.width + 0.5 {
                used += gap + widths[end]
                end += 1
            }
            return end
        }
        func fits(_ range: Range<Int>) -> Bool {
            widths[range].reduce(0, +) + gap * CGFloat(range.count - 1) <= rect.width + 0.5
        }
        let focused = min(max(focused, 0), widths.count - 1)
        var start = min(max(firstVisible, 0), widths.count - 1)
        if focused < start { start = focused }
        while focused >= end(from: start) { start += 1 }
        let last = end(from: start)
        while start > 0, fits(start - 1 ..< last) { start -= 1 }

        let visible = start ..< last
        let available = max(rect.width - gap * CGFloat(visible.count - 1), 0)
        let total = widths[visible].reduce(0, +)
        var x = rect.topLeftX
        let frames = visible.map { index in
            let width = total > 0 ? widths[index] * available / total : available / CGFloat(visible.count)
            defer { x += width + gap }
            return Rect(topLeftX: x, topLeftY: rect.topLeftY, width: width, height: rect.height)
        }
        return WindowStripGeometry(visible: visible, frames: frames)
    }
}

extension TilingContainer {
    @MainActor
    var isWindowStrip: Bool { presentsAsStrip && usesWindowTabBehavior }

    /// Column widths come from each child's scrolling width, else the scrolling column width.
    @MainActor
    func windowStripGeometry(in rect: Rect, gaps: ResolvedGaps) -> WindowStripGeometry {
        let fallback = CGFloat(config.scrolling.columnWidth)
        return .calculate(in: rect, shares: children.map { $0.scrollingColumnWidth ?? fallback },
            gap: CGFloat(gaps.inner.horizontal), focused: mostRecentChild?.ownIndex ?? 0,
            firstVisible: stripFirstVisibleIndex)
    }
}
