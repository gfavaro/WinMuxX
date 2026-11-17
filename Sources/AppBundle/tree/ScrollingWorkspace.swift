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

/// A node's Scrolling columns: a window, a vertical stack and a tab group are each one column;
/// a side-by-side split opens up into its children's columns.
/// A container holding a single child (which Dwindle leaves behind) is not a column of its own:
/// its child decides.
@MainActor
private func scrollingColumnUnits(_ node: TreeNode) -> [TreeNode] {
    guard let container = node as? TilingContainer, container.layout != .tabGroup else { return [node] }
    if let only = container.children.singleOrNil() { return scrollingColumnUnits(only) }
    guard container.children.count > 1, container.navigationOrientation == .h else { return [node] }
    return container.children.flatMap(scrollingColumnUnits)
}

extension Workspace {
    /// The strip's columns, left to right. They come from the tree without changing it, so
    /// another layout finds its splits as they were.
    @MainActor
    var scrollingColumns: [TreeNode] {
        let root = rootTilingContainer
        if root.layout == .tabGroup { return [root] }
        return root.children.flatMap(scrollingColumnUnits)
    }

    /// The column `node` is in, or nil when it is not tiled in this workspace.
    @MainActor
    func scrollingColumn(of node: TreeNode) -> TreeNode? {
        let columns = scrollingColumns
        var current: TreeNode? = node
        while let candidate = current {
            if columns.contains(where: { $0 === candidate }) { return candidate }
            current = candidate.parent as? TreeNode
        }
        return nil
    }

    /// Puts `column` beside `target` on the strip, before or after it, in `target`'s split.
    @MainActor
    func placeScrollingColumn(_ column: TreeNode, beside target: TreeNode, after: Bool) {
        guard column !== target, let parent = target.parent as? TilingContainer else { return }
        let binding = column.unbindFromParent()
        guard let index = parent.children.firstIndex(where: { $0 === target }) else {
            column.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
            return
        }
        // Within its own split the column keeps its share there, so another layout finds it as it was.
        column.bind(to: parent, adaptiveWeight: binding.parent === parent ? binding.adaptiveWeight : WEIGHT_AUTO,
                    index: index + (after ? 1 : 0))
        normalizeContainers()
    }

    /// Puts `window` at the bottom of `target`'s column, which becomes a vertical stack that
    /// keeps the column's place and width.
    @MainActor
    func stackScrollingWindow(_ window: Window, onto target: TreeNode) {
        guard window !== target, let parent = target.parent as? TilingContainer else { return }
        let binding = window.unbindFromParent()
        if let stack = target as? TilingContainer, stack.layout != .tabGroup, stack.orientation == .v {
            window.bind(to: stack, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        } else if let index = parent.children.firstIndex(where: { $0 === target }) {
            let width = target.scrollingColumnWidth
            let binding = target.unbindFromParent()
            let stack = TilingContainer(parent: parent, adaptiveWeight: binding.adaptiveWeight, .v, .tiles, index: index)
            stack.scrollingColumnWidth = width
            target.scrollingColumnWidth = nil
            target.bind(to: stack, adaptiveWeight: WEIGHT_AUTO, index: 0)
            window.bind(to: stack, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        } else {
            // The target left the tree: the window stays where it was.
            window.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
            return
        }
        window.scrollingColumnWidth = nil
        lastScrollingFocusWindowId = nil
        normalizeContainers()
    }

    /// The pinned column while it is still a column of this strip and others remain.
    @MainActor
    var pinnedScrollingColumn: TreeNode? {
        let columns = scrollingColumns
        guard let node = scrollingPinnedNode, columns.count > 1, columns.contains(where: { $0 === node }) else { return nil }
        return node
    }

    /// The columns that scroll: every column except a pinned one.
    @MainActor
    var scrollingStripUnits: [TreeNode] {
        let pinned = pinnedScrollingColumn
        return scrollingColumns.filter { $0 !== pinned }
    }

    /// The pinned column's frame at its screen edge, and the rect left for the strip.
    @MainActor
    func scrollingPinSplit(in rect: Rect, gaps: ResolvedGaps) -> (pinned: Rect, strip: Rect)? {
        guard let pinned = pinnedScrollingColumn else { return nil }
        let gap = CGFloat(gaps.inner.horizontal)
        let share = min(pinned.scrollingColumnWidth ?? config.scrolling.columnWidth, 0.8)
        let minimum = pinned.minimumLayoutExtent(along: .h, gaps: gaps)
        let width = min(max((rect.width * share).rounded(), minimum), rect.width * 0.8).rounded()
        let stripWidth = max(1, rect.width - width - gap)
        return scrollingPinSide == .left
            ? (Rect(topLeftX: rect.minX, topLeftY: rect.minY, width: width, height: rect.height),
               Rect(topLeftX: rect.minX + width + gap, topLeftY: rect.minY, width: stripWidth, height: rect.height))
            : (Rect(topLeftX: rect.maxX - width, topLeftY: rect.minY, width: width, height: rect.height),
               Rect(topLeftX: rect.minX, topLeftY: rect.minY, width: stripWidth, height: rect.height))
    }

    /// Moves a strip column, by identity, to an index among the strip's columns.
    @MainActor
    func moveScrollingColumn(_ id: ObjectIdentifier, toStripIndex index: Int) {
        let units = scrollingStripUnits
        guard let from = units.firstIndex(where: { ObjectIdentifier($0) == id }), units.indices.contains(index),
              from != index else { return }
        placeScrollingColumn(units[from], beside: units[index], after: index > from)
        lastScrollingFocusWindowId = nil
        scheduleRefreshSession(.globalObserver("scrollingMove"))
    }

    /// Changes whenever a column, its width or the display changes, so a minimap click made on
    /// an older picture of the strip does nothing.
    @MainActor
    var scrollingTopologySignature: String {
        let bounds = workspaceTilingRect(self)
        var values: [String] = [arrangement.rawValue, id.rawValue,
            "\(bounds.minX),\(bounds.minY),\(bounds.width),\(bounds.height)"]
        func visit(_ node: TreeNode) {
            values.append("\(ObjectIdentifier(node).hashValue):\(node.bindingGeneration):\(node.children.count):\(node.scrollingColumnWidth ?? config.scrolling.columnWidth)")
            if let window = node as? Window {
                values.append("\(window.minimumLayoutSize.width),\(window.minimumLayoutSize.height)")
            }
            node.children.forEach(visit)
        }
        visit(rootTilingContainer)
        return values.joined(separator: ",")
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
        // A display beside this one is a wall: a column parked there would show on it. So is
        // a pinned column: the strip shows no previews on its side.
        let leftWall = pin != nil && scrollingPinSide == .left ||
            otherDisplays.contains { abs($0.rect.maxX - monitorRect.minX) < 1 && overlapsVertically($0.rect) }
        let rightWall = pin != nil && scrollingPinSide == .right ||
            otherDisplays.contains { abs($0.rect.minX - monitorRect.maxX) < 1 && overlapsVertically($0.rect) }
        let units = scrollingStripUnits
        let focused = lastScrollingFocusWindowId.flatMap(Window.get(byId:))
            ?? (focus.workspace === self ? focus.windowOrNil : nil)
        let focusedIndex = focused.flatMap(scrollingColumn(of:)).flatMap { column in units.firstIndex(where: { $0 === column }) }
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
        let units = scrollingStripUnits
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
           let column = metrics.columns.first(where: { $0.node === scrollingColumn(of: focused) })
        {
            let previous = lastScrollingFocusWindowId.flatMap(Window.get(byId:)).flatMap { window in
                metrics.columns.first(where: { $0.node === scrollingColumn(of: window) })
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
              let column = metrics.columns.first(where: { $0.node === scrollingColumn(of: anchor) }) else { return }
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
              let column = metrics.columns.first(where: { $0.node === scrollingColumn(of: anchor) }) else {
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

    /// The column `group` is, with its current window width and the most it can take.
    @MainActor
    func scrollingColumnWidthRange(of group: TreeNode) -> (width: CGFloat, minimum: CGFloat, maximum: CGFloat, insets: CGFloat, area: CGFloat)? {
        let rect = workspaceTilingRect(self)
        let minimum = group.minimumLayoutExtent(along: .h, rect: rect)
        if group === pinnedScrollingColumn {
            let width = group.lastAppliedLayoutPhysicalRect?.width ?? rect.width * (group.scrollingColumnWidth ?? config.scrolling.columnWidth)
            return (width, minimum, max(rect.width * 0.8, minimum), 0, rect.width)
        }
        let metrics = scrollingMetrics
        guard let column = metrics.columns.first(where: { $0.node === group }) else { return nil }
        let insets = column.frameStartInset + column.frameEndInset
        return (column.width, minimum, max(metrics.areaWidth - insets, minimum), insets, metrics.areaWidth)
    }

    /// Sets a column's window width in points, kept between its app's minimum and the display,
    /// and stores it as the share of the display the column takes. False when nothing changed.
    @MainActor
    @discardableResult
    func setScrollingColumnWidth(of group: TreeNode, to requested: CGFloat) -> Bool {
        guard let range = scrollingColumnWidthRange(of: group), requested.isFinite else { return false }
        let actual = min(max(requested, range.minimum), range.maximum)
        guard abs(actual - range.width) >= 0.5 else { return false }
        group.scrollingColumnWidth = min(max((actual + range.insets) / max(range.area, 1), 0.1), 1)
        // The resized column is scrolled into view again.
        lastScrollingFocusWindowId = nil
        return true
    }

    /// A mouse resize of `window`'s column from `previous` to `rect`: the width follows the dragged
    /// edge and the strip scrolls so the other edge stays where it was on screen.
    /// Returns the column it resized, or nil when nothing changed.
    @MainActor
    @discardableResult
    func resizeScrollingColumnWithMouse(_ window: Window, from previous: Rect, to rect: Rect) -> TreeNode? {
        guard let group = scrollingColumn(of: window), abs(rect.width - previous.width) > 1,
              let before = scrollingMetrics.columns.first(where: { $0.node === group }),
              let range = scrollingColumnWidthRange(of: group) else { return nil }
        let offset = scrollingOffset
        guard setScrollingColumnWidth(of: group, to: range.width + rect.width - previous.width),
              let after = scrollingMetrics.columns.first(where: { $0.node === group }) else { return nil }
        let leftEdgeDragged = abs(rect.minX - previous.minX) > 1
        scrollingOffset = leftEdgeDragged
            ? after.start + after.width - (before.start + before.width - offset)
            : after.start - (before.start - offset)
        // The strip stays where the mouse left it: neither focus nor the anchor scrolls it back.
        lastScrollingFocusWindowId = window.windowId
        captureScrollingViewportAnchor(preferredWindow: window)
        return group
    }

    /// Where the strip is looking and what keeps it there: saved before a preview lays the strip
    /// out as it would be, and put back after, so nothing of the preview reaches the real layout.
    struct ScrollingViewState {
        fileprivate let offset: CGFloat
        fileprivate let lastFocusWindowId: UInt32?
        fileprivate let anchorWindowId: UInt32?
        fileprivate let anchorViewportPosition: CGFloat?
        fileprivate let anchorAreaWidth: CGFloat?
        fileprivate let anchorLogicalCenter: CGFloat?
    }

    @MainActor
    var scrollingViewState: ScrollingViewState {
        get {
            ScrollingViewState(offset: scrollingOffset, lastFocusWindowId: lastScrollingFocusWindowId,
                               anchorWindowId: scrollingAnchorWindowId, anchorViewportPosition: scrollingAnchorViewportPosition,
                               anchorAreaWidth: scrollingAnchorAreaWidth, anchorLogicalCenter: scrollingAnchorLogicalCenter)
        }
        set {
            scrollingOffset = newValue.offset
            lastScrollingFocusWindowId = newValue.lastFocusWindowId
            scrollingAnchorWindowId = newValue.anchorWindowId
            scrollingAnchorViewportPosition = newValue.anchorViewportPosition
            scrollingAnchorAreaWidth = newValue.anchorAreaWidth
            scrollingAnchorLogicalCenter = newValue.anchorLogicalCenter
        }
    }

    @MainActor
    func centerFocusedScrollingColumn() {
        guard let window = focus.windowOrNil, window.nodeWorkspace === self else { return }
        let metrics = scrollingMetrics
        guard let column = metrics.columns.first(where: { $0.node === scrollingColumn(of: window) }) else { return }
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
