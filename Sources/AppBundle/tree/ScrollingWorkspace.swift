import AppKit
import Common

// Strip gutters, fitting behavior, and parked-window previews adapt Dinky's
// Scrolling layout (MIT; see docs/licenses/Dinky-MIT.txt).

struct ScrollingColumnMetric {
    let node: TreeNode
    let start: CGFloat
    let width: CGFloat
    let frameStartInset: CGFloat
    let frameEndInset: CGFloat
}

enum ScrollingColumnVisibility: Equatable {
    case visible, leftPreview, rightPreview, parkedLeft, parkedRight
}

struct ScrollingColumnGeometry {
    let index: Int
    let spanStart: CGFloat
    let spanWidth: CGFloat
    let leadInset: CGFloat
    let trailInset: CGFloat
    let logicalFrame: CGRect
    let physicalFrame: CGRect
    let visibility: ScrollingColumnVisibility
}

struct ScrollingWorkspaceGeometry {
    let area: CGRect
    let clampedOffset: CGFloat
    let offsetRange: ClosedRange<CGFloat>
    let columns: [ScrollingColumnGeometry]
    /// Native order, back to front. Visible groups are always above parked groups.
    let stackingOrder: [Int]
}

struct ScrollingWorkspaceGeometryInput {
    struct Column {
        let preferredWidth: CGFloat
        let minimumWidth: CGFloat
        var fixedWidth: CGFloat? = nil
    }

    let bounds: CGRect
    let parkingBounds: CGRect
    let offset: CGFloat
    let columns: [Column]
    let horizontalGap: CGFloat
    let outerLeft: CGFloat
    let outerRight: CGFloat
    let leftWall: Bool
    let rightWall: Bool
    let preview: CGFloat
    var focusedColumnIndex: Int? = nil
    /// Where an open sheet needs the strip, even past either end; the range stretches to it.
    var sheetOffset: CGFloat? = nil
}

/// Pure strip geometry. It only describes logical and physical frames; it does
/// not query AX, change focus, or mutate a workspace.
func calculateScrollingWorkspaceGeometry(_ input: ScrollingWorkspaceGeometryInput) -> ScrollingWorkspaceGeometry {
    let gap = max(0, input.horizontalGap.isFinite ? input.horizontalGap : 0)
    let preview = max(0, input.preview.isFinite ? input.preview : 0)
    let area = scrollingViewportArea(input, gap: gap, preview: preview)
    let spans = scrollingColumnSpans(input, area: area, gap: gap)
    let range = scrollingOffsetRange(input, spans: spans, area: area)
    let requested = input.offset.isFinite ? input.offset : 0
    let offset = min(max(requested, range.lowerBound), range.upperBound)
    let geometries = spans.enumerated().map { index, span in
        scrollingColumnGeometry(index: index, span: span, input: input, area: area, offset: offset, preview: preview)
    }
    return ScrollingWorkspaceGeometry(area: area, clampedOffset: offset, offsetRange: range, columns: geometries,
                                      stackingOrder: scrollingStackingOrder(geometries, area: area, focused: input.focusedColumnIndex))
}

/// A column's slot on the strip: where it starts, how wide it is, and the half gaps either side.
private struct ScrollingSpan {
    let start: CGFloat
    let width: CGFloat
    let lead: CGFloat
    let trail: CGFloat
}

/// The part of the display columns are laid out in, narrowed by the gutters that keep
/// neighbouring columns' previews visible where no wall stops them.
private func scrollingViewportArea(_ input: ScrollingWorkspaceGeometryInput, gap: CGFloat, preview: CGFloat) -> CGRect {
    let bounds = input.bounds
    let hasMultiple = input.columns.count > 1
    let leftGutter = hasMultiple && !input.leftWall ? max(0, preview + gap / 2 - max(0, input.outerLeft)) : 0
    let rightGutter = hasMultiple && !input.rightWall ? max(0, preview + gap / 2 - max(0, input.outerRight)) : 0
    return CGRect(x: bounds.minX + leftGutter, y: bounds.minY,
                  width: max(1, bounds.width - leftGutter - rightGutter), height: bounds.height)
}

private func scrollingColumnSpans(_ input: ScrollingWorkspaceGeometryInput, area: CGRect, gap: CGFloat) -> [ScrollingSpan] {
    var spans: [ScrollingSpan] = []
    var cursor: CGFloat = 0
    for (index, column) in input.columns.enumerated() {
        let lead = index > 0 ? gap / 2 : 0
        let trail = index < input.columns.count - 1 ? gap / 2 : 0
        let preferred = column.preferredWidth.isFinite ? column.preferredWidth : 0.49
        let share = min(max(preferred, 0.1), 1)
        let minimum = max(0, column.minimumWidth.isFinite ? column.minimumWidth : 0)
        let fixed = column.fixedWidth.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        // A fixed width is the window's own width; the gaps around it come on top.
        let desired = fixed.map { $0 + lead + trail } ?? (input.columns.count == 1 ? area.width : (area.width * share).rounded())
        let width = max(desired.rounded(), minimum + lead + trail)
        spans.append(ScrollingSpan(start: cursor, width: width, lead: lead, trail: trail))
        cursor += width
    }
    return spans
}

/// When the strip fits, a negative offset centres it. Overflowing strips start at zero and
/// stop when the final column reaches the right edge. A sheet wider than a column at either
/// end can only be shown by scrolling past that end, until the sheet closes.
private func scrollingOffsetRange(_ input: ScrollingWorkspaceGeometryInput, spans: [ScrollingSpan],
                                  area: CGRect) -> ClosedRange<CGFloat> {
    let total = spans.last.map { $0.start + $0.width } ?? 0
    let stripLower: CGFloat
    let stripUpper: CGFloat
    if input.columns.isEmpty {
        stripLower = 0
        stripUpper = 0
    } else if total <= area.width {
        stripLower = (total - area.width) / 2
        stripUpper = stripLower
    } else {
        stripLower = 0
        stripUpper = total - area.width
    }
    let sheet = input.sheetOffset.flatMap { $0.isFinite ? $0 : nil }
    return min(stripLower, sheet ?? stripLower)...max(stripUpper, sheet ?? stripUpper)
}

/// Where one column sits on the strip and where it is actually placed on the display: columns
/// off the viewport are parked at a wall or left showing only a preview sliver.
private func scrollingColumnGeometry(index: Int, span: ScrollingSpan, input: ScrollingWorkspaceGeometryInput,
                                     area: CGRect, offset: CGFloat, preview: CGFloat) -> ScrollingColumnGeometry {
    let viewport = area
    let logicalX = area.minX + span.start - offset + span.lead
    let width = max(1, span.width - span.lead - span.trail)
    let logical = CGRect(x: logicalX.rounded(), y: area.minY, width: width.rounded(), height: area.height)
    var physicalX = logical.minX
    let whollyLeft = logical.maxX <= viewport.minX
    let whollyRight = logical.minX >= viewport.maxX
    let parking = input.parkingBounds
    if span.width > parking.width, index == input.focusedColumnIndex {
        // If a learned app minimum exceeds the display width, full
        // containment is impossible. Center the focused oversized column.
        physicalX = parking.midX - logical.width / 2
    } else if whollyLeft {
        physicalX = input.leftWall ? parking.minX : parking.minX + preview - logical.width
    } else if whollyRight {
        physicalX = input.rightWall ? parking.maxX - logical.width : parking.maxX - preview
    } else {
        physicalX = min(max(physicalX, input.leftWall ? parking.minX : parking.minX + preview - logical.width),
                       input.rightWall ? parking.maxX - logical.width : parking.maxX - preview)
    }
    let visibility: ScrollingColumnVisibility = if whollyLeft {
        input.leftWall ? .parkedLeft : .leftPreview
    } else if whollyRight {
        input.rightWall ? .parkedRight : .rightPreview
    } else if logical.minX >= viewport.minX && logical.maxX <= viewport.maxX {
        .visible
    } else if logical.midX < viewport.midX {
        .leftPreview
    } else {
        .rightPreview
    }
    let physical = CGRect(x: physicalX.rounded(), y: logical.minY, width: logical.width, height: logical.height)
    return ScrollingColumnGeometry(index: index, spanStart: span.start, spanWidth: span.width,
                                   leadInset: span.lead, trailInset: span.trail,
                                   logicalFrame: logical, physicalFrame: physical, visibility: visibility)
}

/// Back to front: hidden columns first, the focused one above its neighbours, nearer the
/// middle of the viewport above farther.
private func scrollingStackingOrder(_ geometries: [ScrollingColumnGeometry], area: CGRect, focused: Int?) -> [Int] {
    geometries.indices.sorted { lhs, rhs in
        let lVisible = geometries[lhs].logicalFrame.intersects(area)
        let rVisible = geometries[rhs].logicalFrame.intersects(area)
        if lVisible != rVisible { return !lVisible }
        if lhs == focused { return false }
        if rhs == focused { return true }
        let lDistance = abs(geometries[lhs].logicalFrame.midX - area.midX)
        let rDistance = abs(geometries[rhs].logicalFrame.midX - area.midX)
        return lDistance == rDistance ? lhs < rhs : lDistance > rDistance
    }
}

/// macOS keeps any sliver of a window on its display, down to one point, but moves a
/// window placed wholly off the display back to show 40 points (measured on macOS 27.2,
/// both edges). So a parked column always keeps at least one point on screen.
func effectiveEdgePreview(_ configured: Int) -> CGFloat {
    CGFloat(max(configured, 1))
}

struct ScrollingWorkspaceMetrics {
    let areaStart: CGFloat
    let areaWidth: CGFloat
    let totalWidth: CGFloat
    let columns: [ScrollingColumnMetric]
    let geometry: ScrollingWorkspaceGeometry

    var offsetRange: ClosedRange<CGFloat> {
        geometry.offsetRange
    }

    func clampedOffset(_ offset: CGFloat) -> CGFloat {
        min(max(offset, offsetRange.lowerBound), offsetRange.upperBound)
    }

    func centeredOffset(for column: ScrollingColumnMetric) -> CGFloat {
        clampedOffset(column.start + column.width / 2 - areaWidth / 2)
    }

    /// Where the strip goes when focus lands on `column`, per `center-focused-column`.
    @MainActor
    func focusedOffset(for column: ScrollingColumnMetric, current: CGFloat,
                       mode: ScrollingCenterMode = config.scrolling.centerFocusedColumn,
                       previous: ScrollingColumnMetric? = nil) -> CGFloat {
        switch mode {
            case .never: return revealedOffset(for: column, current: current)
            case .always: return centeredOffset(for: column)
            case .onOverflow:
                // Already wholly visible: stay. Otherwise centre instead of edging it in.
                let current = clampedOffset(current)
                if revealedOffset(for: column, current: current) == current { return current }
                if let previous {
                    let first = min(previous.start, column.start)
                    let last = max(previous.start + previous.width, column.start + column.width)
                    if last - first <= areaWidth { return revealedOffset(for: column, current: current) }
                }
                return centeredOffset(for: column)
        }
    }

    func revealedOffset(for column: ScrollingColumnMetric, current: CGFloat) -> CGFloat {
        revealedOffset(start: column.start, end: column.start + column.width, current: current)
    }

    func revealedOffset(start: CGFloat, end: CGFloat, current: CGFloat) -> CGFloat {
        if end - start > areaWidth { return clampedOffset((start + end) / 2 - areaWidth / 2) }
        let current = clampedOffset(current)
        if start < current { return clampedOffset(start) }
        if end > current + areaWidth {
            return clampedOffset(end - areaWidth)
        }
        return current
    }
}

extension Workspace {
    @MainActor
    func scrollingGeometry(in rect: Rect? = nil, gaps: ResolvedGaps? = nil) -> ScrollingWorkspaceGeometry {
        let rect = rect ?? workspaceTilingRect(self)
        let gaps = gaps ?? ResolvedGaps(gaps: config.gaps, monitor: workspaceMonitor)
        let bounds = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        let monitorRect = workspaceMonitor.rect
        let parking = CGRect(x: monitorRect.minX, y: monitorRect.minY, width: monitorRect.width, height: monitorRect.height)
        let otherDisplays = monitors.filter { $0.rect.topLeftCorner != monitorRect.topLeftCorner }
        let overlapsVertically: (Rect) -> Bool = { $0.minY < monitorRect.maxY && $0.maxY > monitorRect.minY }
        // A display beside this one is a wall: a column parked there would show on it.
        let leftWall = otherDisplays.contains { abs($0.rect.maxX - monitorRect.minX) < 1 && overlapsVertically($0.rect) }
        let rightWall = otherDisplays.contains { abs($0.rect.minX - monitorRect.maxX) < 1 && overlapsVertically($0.rect) }
        let units = workspaceLayoutUnits
        let focused = lastScrollingFocusWindowId.flatMap(Window.get(byId:))
            ?? (focus.workspace === self ? focus.windowOrNil : nil)
        let focusedIndex = focused.flatMap { focused in units.firstIndex(where: { $0 === focused.topLevelWorkspaceGroup }) }
        return calculateScrollingWorkspaceGeometry(.init(
            bounds: bounds, parkingBounds: parking, offset: scrollingOffset,
            columns: units.map { node in
                .init(preferredWidth: node.scrollingColumnWidth ?? config.scrolling.columnWidth,
                      minimumWidth: node.minimumLayoutExtent(along: .h, gaps: gaps))
            },
            horizontalGap: CGFloat(gaps.inner.horizontal),
            outerLeft: CGFloat(gaps.outer.left), outerRight: CGFloat(gaps.outer.right),
            leftWall: leftWall, rightWall: rightWall, preview: effectiveEdgePreview(config.scrolling.edgePreview),
            focusedColumnIndex: focusedIndex))
    }

    @MainActor
    var scrollingMetrics: ScrollingWorkspaceMetrics {
        let units = workspaceLayoutUnits
        let geometry = scrollingGeometry()
        let columns = zip(units, geometry.columns).map { node, frame in
            ScrollingColumnMetric(node: node,
                start: frame.spanStart + frame.leadInset,
                width: max(1, frame.spanWidth - frame.leadInset - frame.trailInset),
                frameStartInset: frame.leadInset, frameEndInset: frame.trailInset)
        }
        let total = geometry.columns.last.map { $0.spanStart + $0.spanWidth } ?? 0
        return ScrollingWorkspaceMetrics(areaStart: geometry.area.minX, areaWidth: geometry.area.width,
                                         totalWidth: total, columns: columns, geometry: geometry)
    }

    /// Scrolls the strip to the focused window's column when focus has moved there since the
    /// last layout, then keeps the offset inside the strip.
    @MainActor
    func scrollToFocusedColumnIfNeeded() {
        rebaseScrollingViewportIfNeeded(using: scrollingMetrics)
        let metrics = scrollingMetrics
        if let focused = focus.windowOrNil, focused.nodeWorkspace === self,
           lastScrollingFocusWindowId != focused.windowId,
           let column = metrics.columns.first(where: { $0.node === focused.topLevelWorkspaceGroup })
        {
            let previous = lastScrollingFocusWindowId.flatMap(Window.get(byId:)).flatMap { window in
                metrics.columns.first(where: { $0.node === window.topLevelWorkspaceGroup })
            }
            scrollingOffset = metrics.focusedOffset(for: column, current: scrollingOffset, previous: previous)
            lastScrollingFocusWindowId = focused.windowId
        }
        scrollingOffset = metrics.clampedOffset(scrollingOffset)
    }

    @MainActor
    func captureScrollingViewportAnchor(using metrics: ScrollingWorkspaceMetrics? = nil, preferredWindow: Window? = nil) {
        let metrics = metrics ?? scrollingMetrics
        guard metrics.areaWidth > 0 else { return }
        let anchor = preferredWindow
            ?? (focus.workspace === self ? focus.windowOrNil : nil)
            ?? lastScrollingFocusWindowId.flatMap(Window.get(byId:))
            ?? scrollingAnchorWindowId.flatMap(Window.get(byId:))
            ?? mostRecentWorkspaceFocusableWindowRecursive
        guard let anchor, anchor.nodeWorkspace === self,
              let column = metrics.columns.first(where: { $0.node === anchor.topLevelWorkspaceGroup }) else { return }
        scrollingAnchorWindowId = anchor.windowId
        let center = column.start + column.width / 2
        scrollingAnchorViewportPosition = (center - scrollingOffset) / metrics.areaWidth
        scrollingAnchorAreaWidth = metrics.areaWidth
        scrollingAnchorLogicalCenter = center
    }

    /// Keeps the anchor window's column where it was in the viewport after columns change
    /// width or the display does, instead of letting the strip jump.
    @MainActor
    func rebaseScrollingViewportIfNeeded(using metrics: ScrollingWorkspaceMetrics) {
        guard metrics.areaWidth > 0 else { return }
        guard let oldWidth = scrollingAnchorAreaWidth, let oldCenter = scrollingAnchorLogicalCenter else {
            captureScrollingViewportAnchor(using: metrics)
            return
        }
        let anchor = scrollingAnchorWindowId.flatMap(Window.get(byId:))
            ?? lastScrollingFocusWindowId.flatMap(Window.get(byId:))
            ?? mostRecentWorkspaceFocusableWindowRecursive
        guard let anchor, anchor.nodeWorkspace === self,
              let position = scrollingAnchorViewportPosition, position.isFinite,
              let column = metrics.columns.first(where: { $0.node === anchor.topLevelWorkspaceGroup }) else {
            // A removed anchor is never allowed to impose an old offset on
            // a different window. Establish the new reference after layout.
            scrollingAnchorAreaWidth = nil
            scrollingAnchorLogicalCenter = nil
            return
        }
        let center = column.start + column.width / 2
        guard abs(oldWidth - metrics.areaWidth) > 0.5 || abs(oldCenter - center) > 0.5 else { return }
        scrollingOffset = metrics.clampedOffset(center - position * metrics.areaWidth)
        scrollingAnchorAreaWidth = metrics.areaWidth
        scrollingAnchorLogicalCenter = center
    }

    @MainActor
    func centerFocusedScrollingColumn() {
        guard let window = focus.windowOrNil, window.nodeWorkspace === self else { return }
        let metrics = scrollingMetrics
        guard let column = metrics.columns.first(where: { $0.node === window.topLevelWorkspaceGroup }) else { return }
        scrollingOffset = metrics.centeredOffset(for: column)
        lastScrollingFocusWindowId = window.windowId
    }
}

/// The column whose centre is nearest the viewport's; on a tie, the one further in `direction`.
func nearestScrollingColumn(in metrics: ScrollingWorkspaceMetrics, offset: CGFloat, direction: CGFloat) -> ScrollingColumnMetric? {
    let center = offset + metrics.areaWidth / 2
    return metrics.columns.min { lhs, rhs in
        let a = abs(lhs.start + lhs.width / 2 - center)
        let b = abs(rhs.start + rhs.width / 2 - center)
        if abs(a - b) < 0.5, direction != 0 { return direction > 0 ? lhs.start > rhs.start : lhs.start < rhs.start }
        return a < b
    }
}

/// A completed swipe gets one adjacent-column fallback if an oversized column remains nearest
/// after the finger-following pan. Never skip a column, reverse direction, or force a move at
/// either end of the strip.
func settledDockSwipeColumn(in metrics: ScrollingWorkspaceMetrics, offset: CGFloat,
                            direction: CGFloat, startingColumnID: ObjectIdentifier?,
                            advanceIfStuck: Bool) -> ScrollingColumnMetric? {
    let nearest = nearestScrollingColumn(in: metrics, offset: offset, direction: direction)
    guard advanceIfStuck, let startingColumnID, direction != 0,
          let current = metrics.columns.firstIndex(where: { ObjectIdentifier($0.node) == startingColumnID }),
          let nearest, ObjectIdentifier(nearest.node) == startingColumnID else { return nearest }
    let next = current + (direction > 0 ? 1 : -1)
    guard metrics.columns.indices.contains(next) else { return nearest }
    return metrics.columns[next]
}
