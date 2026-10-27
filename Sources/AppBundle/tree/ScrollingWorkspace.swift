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
}

/// Pure strip geometry. It only describes logical and physical frames; it does
/// not query AX, change focus, or mutate a workspace.
func calculateScrollingWorkspaceGeometry(_ input: ScrollingWorkspaceGeometryInput) -> ScrollingWorkspaceGeometry {
    let bounds = input.bounds
    let gap = max(0, input.horizontalGap.isFinite ? input.horizontalGap : 0)
    let preview = max(0, input.preview.isFinite ? input.preview : 0)
    let hasMultiple = input.columns.count > 1
    let leftGutter = hasMultiple && !input.leftWall ? max(0, preview + gap / 2 - max(0, input.outerLeft)) : 0
    let rightGutter = hasMultiple && !input.rightWall ? max(0, preview + gap / 2 - max(0, input.outerRight)) : 0
    let area = CGRect(x: bounds.minX + leftGutter, y: bounds.minY,
                      width: max(1, bounds.width - leftGutter - rightGutter), height: bounds.height)

    var spans: [(start: CGFloat, width: CGFloat, lead: CGFloat, trail: CGFloat)] = []
    var cursor: CGFloat = 0
    for (index, column) in input.columns.enumerated() {
        let lead = index > 0 ? gap / 2 : 0
        let trail = index < input.columns.count - 1 ? gap / 2 : 0
        let preferred = column.preferredWidth.isFinite ? column.preferredWidth : 0.49
        let share = min(max(preferred, 0.1), 1)
        let minimum = max(0, column.minimumWidth.isFinite ? column.minimumWidth : 0)
        let width = input.columns.count == 1 ? max(area.width, minimum + lead + trail) : max((area.width * share).rounded(), minimum + lead + trail)
        spans.append((cursor, width, lead, trail))
        cursor += width
    }
    let total = spans.last.map { $0.start + $0.width } ?? 0
    // When the strip fits, a negative offset centres it. Overflowing strips start
    // at zero and stop when the final column reaches the right edge.
    let lower: CGFloat
    let upper: CGFloat
    if input.columns.isEmpty {
        lower = 0
        upper = 0
    } else if total <= area.width {
        lower = (total - area.width) / 2
        upper = lower
    } else {
        lower = 0
        upper = total - area.width
    }
    let requested = input.offset.isFinite ? input.offset : 0
    let offset = min(max(requested, lower), upper)
    let viewport = area
    let geometries = spans.enumerated().map { index, span -> ScrollingColumnGeometry in
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
    let order = geometries.indices.sorted { lhs, rhs in
        let lVisible = geometries[lhs].logicalFrame.intersects(area)
        let rVisible = geometries[rhs].logicalFrame.intersects(area)
        if lVisible != rVisible { return !lVisible }
        if lhs == input.focusedColumnIndex { return false }
        if rhs == input.focusedColumnIndex { return true }
        let lDistance = abs(geometries[lhs].logicalFrame.midX - viewport.midX)
        let rDistance = abs(geometries[rhs].logicalFrame.midX - viewport.midX)
        return lDistance == rDistance ? lhs < rhs : lDistance > rDistance
    }
    return ScrollingWorkspaceGeometry(area: area, clampedOffset: offset, offsetRange: lower...upper,
                                      columns: geometries, stackingOrder: order)
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
                       mode: ScrollingCenterMode = config.scrolling.centerFocusedColumn) -> CGFloat {
        switch mode {
            case .never: return revealedOffset(for: column, current: current)
            case .always: return centeredOffset(for: column)
            case .onOverflow:
                // Already wholly visible: stay. Otherwise centre instead of edging it in.
                let current = clampedOffset(current)
                return revealedOffset(for: column, current: current) == current ? current : centeredOffset(for: column)
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
    /// The pinned column while it is still a column of this scrolling strip and others remain.
    @MainActor
    var pinnedScrollingColumn: TreeNode? {
        guard arrangement == .scrolling, let node = scrollingPinnedNode, node.parent === rootTilingContainer,
              workspaceLayoutUnits.count > 1, workspaceLayoutUnits.contains(where: { $0 === node }) else { return nil }
        return node
    }

    /// The columns that scroll: every layout unit except a pinned one.
    @MainActor
    var scrollingStripUnits: [TreeNode] {
        let pinned = pinnedScrollingColumn
        return workspaceLayoutUnits.filter { $0 !== pinned }
    }

    /// The pinned column's frame at its screen edge, and the rect left for the strip.
    @MainActor
    func scrollingPinSplit(in rect: Rect, gaps: ResolvedGaps) -> (pinned: Rect, strip: Rect)? {
        guard let pinned = pinnedScrollingColumn else { return nil }
        let gap = CGFloat(gaps.inner.horizontal)
        let share = min(pinned.scrollingColumnWidth ?? config.scrolling.columnWidth, 0.8)
        let minimum = pinned.minimumLayoutExtent(along: .h, gaps: gaps, rect: rect)
        let width = min(max((rect.width * share).rounded(), minimum), rect.width * 0.8).rounded()
        let stripWidth = max(1, rect.width - width - gap)
        return scrollingPinSide == .left
            ? (Rect(topLeftX: rect.minX, topLeftY: rect.minY, width: width, height: rect.height),
               Rect(topLeftX: rect.minX + width + gap, topLeftY: rect.minY, width: stripWidth, height: rect.height))
            : (Rect(topLeftX: rect.maxX - width, topLeftY: rect.minY, width: width, height: rect.height),
               Rect(topLeftX: rect.minX, topLeftY: rect.minY, width: stripWidth, height: rect.height))
    }

    @MainActor
    func scrollingGeometry(in rect: Rect? = nil, gaps: ResolvedGaps? = nil) -> ScrollingWorkspaceGeometry {
        let fullRect = rect ?? workspaceTilingRect(self)
        let gaps = gaps ?? ResolvedGaps(gaps: config.gaps, monitor: workspaceMonitor)
        let pin = scrollingPinSplit(in: fullRect, gaps: gaps)
        let rect = pin?.strip ?? fullRect
        let bounds = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        let monitorRect = workspaceMonitor.rect
        let parking = CGRect(x: monitorRect.minX, y: monitorRect.minY, width: monitorRect.width, height: monitorRect.height)
        let otherDisplays = monitors.filter { $0.rect.topLeftCorner != monitorRect.topLeftCorner }
        let overlapsVertically: (Rect) -> Bool = { $0.minY < monitorRect.maxY && $0.maxY > monitorRect.minY }
        // A pinned column is a wall: the strip shows no previews on its side.
        let leftWall = pin != nil && scrollingPinSide == .left ||
            otherDisplays.contains { abs($0.rect.maxX - monitorRect.minX) < 1 && overlapsVertically($0.rect) }
        let rightWall = pin != nil && scrollingPinSide == .right ||
            otherDisplays.contains { abs($0.rect.minX - monitorRect.maxX) < 1 && overlapsVertically($0.rect) }
        let units = scrollingStripUnits
        let focused = lastScrollingFocusWindowId.flatMap(Window.get(byId:))
            ?? (focus.workspace === self ? focus.windowOrNil : nil)
        let focusedIndex = focused.flatMap { focused in units.firstIndex(where: { $0 === focused.topLevelWorkspaceGroup }) }
        return calculateScrollingWorkspaceGeometry(.init(
            bounds: bounds, parkingBounds: parking, offset: scrollingOffset,
            columns: units.map { node in
                let saved = node.scrollingColumnWidth ?? config.scrolling.columnWidth
                return .init(preferredWidth: saved,
                             minimumWidth: node.minimumLayoutExtent(along: .h, gaps: gaps, rect: rect))
            },
            horizontalGap: CGFloat(gaps.inner.horizontal),
            outerLeft: CGFloat(gaps.outer.left), outerRight: CGFloat(gaps.outer.right),
            leftWall: leftWall, rightWall: rightWall, preview: 25, focusedColumnIndex: focusedIndex))
    }

    @MainActor
    var scrollingMetrics: ScrollingWorkspaceMetrics {
        let rect = workspaceTilingRect(self)
        let units = scrollingStripUnits
        let geometry = scrollingGeometry(in: rect)
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

    @MainActor
    func captureScrollingViewportAnchor(using metrics: ScrollingWorkspaceMetrics? = nil, preferredWindow: Window? = nil) {
        guard arrangement == .scrolling else { return }
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
        scrollingAnchorViewportPosition = (column.start + column.width / 2 - scrollingOffset) / metrics.areaWidth
        scrollingAnchorAreaWidth = metrics.areaWidth
    }

    @MainActor
    func rebaseScrollingViewportIfNeeded(using metrics: ScrollingWorkspaceMetrics) {
        guard arrangement == .scrolling, metrics.areaWidth > 0 else { return }
        guard let oldWidth = scrollingAnchorAreaWidth else {
            captureScrollingViewportAnchor(using: metrics)
            return
        }
        guard abs(oldWidth - metrics.areaWidth) > 0.5 else { return }
        let anchor = scrollingAnchorWindowId.flatMap(Window.get(byId:))
            ?? lastScrollingFocusWindowId.flatMap(Window.get(byId:))
            ?? mostRecentWorkspaceFocusableWindowRecursive
        guard let anchor, anchor.nodeWorkspace === self,
              let position = scrollingAnchorViewportPosition, position.isFinite,
              let column = metrics.columns.first(where: { $0.node === anchor.topLevelWorkspaceGroup }) else {
            scrollingAnchorAreaWidth = metrics.areaWidth
            return
        }
        scrollingOffset = metrics.clampedOffset(column.start + column.width / 2 - position * metrics.areaWidth)
        scrollingAnchorAreaWidth = metrics.areaWidth
    }

    @MainActor
    func centerFocusedScrollingColumn() {
        guard arrangement == .scrolling, let window = focus.windowOrNil else { return }
        let metrics = scrollingMetrics
        guard let column = metrics.columns.first(where: { $0.node === window.topLevelWorkspaceGroup }) else { return }
        scrollingOffset = metrics.centeredOffset(for: column)
        lastScrollingFocusWindowId = window.windowId
        scheduleRefreshSession(.globalObserver("scrollingCenter"))
    }
}
