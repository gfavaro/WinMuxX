import AppKit
import Common

enum FrozenTreeNode: Codable, Equatable, Sendable {
    case container(FrozenContainer)
    case window(FrozenWindow)
}

struct FrozenContainer: Codable, Equatable, Sendable {
    let children: [FrozenTreeNode]
    let layout: Layout
    let orientation: Orientation
    let weight: CGFloat
    let isMasterStack: Bool?
    let masterRatio: CGFloat?
    let masterStackLayout: Layout?
    let dwindleSplitRatios: [CGFloat]?
    let dwindleOrientation: Orientation?
    let dwindleChildRatios: [CGFloat]?

    @MainActor init(_ container: TilingContainer) {
        children = container.children.map {
            switch $0.nodeCases {
                case .window(let w): .window(FrozenWindow(w))
                case .tilingContainer(let c): .container(FrozenContainer(c))
                case .workspace,
                     .macosMinimizedWindowsContainer,
                     .macosHiddenAppsWindowsContainer,
                     .macosFullscreenWindowsContainer,
                     .macosPopupWindowsContainer:
                    illegalChildParentRelation(child: $0, parent: container)
            }
        }
        isMasterStack = container.isMasterStack ? true : nil
        masterRatio = container.masterRatio
        masterStackLayout = container.masterStackLayout
        layout = container.layout
        orientation = container.orientation
        weight = getWeightOrNil(container) ?? 1
        dwindleSplitRatios = container.dwindleSplitRatios.isEmpty ? nil : container.dwindleSplitRatios
        dwindleOrientation = container.dwindleOrientation
        dwindleChildRatios = container.dwindleChildRatios
    }

    /// A terminated process can recover assignments, but cannot finish its old
    /// live-process tree. Keep only the target leaf and constant-size root policy.
    @MainActor init(assignment: FrozenWindow?, in container: TilingContainer) {
        children = assignment.map { [.window($0)] } ?? []
        isMasterStack = container.isMasterStack ? true : nil
        masterRatio = container.masterRatio
        masterStackLayout = container.masterStackLayout
        layout = container.layout
        orientation = container.orientation
        weight = getWeightOrNil(container) ?? 1
        dwindleSplitRatios = nil
        dwindleOrientation = nil
        dwindleChildRatios = nil
    }
}

struct FrozenWindow: Codable, Equatable, Sendable {
    let id: UInt32
    let restartIdentity: RestartWindowIdentity?
    let weight: CGFloat
    let isFullscreen: Bool
    let noOuterGapsInFullscreen: Bool
    let layoutReason: LayoutReason
    let learnedMinimumSize: CGSize?
    let minimumEvidenceVersion: Int
    let lastFloatingSize: CGSize?
    let singleWindowManualWidth: CGFloat?
    let workspacePreviewFrame: CGRect?

    @MainActor init(_ window: Window) {
        id = window.windowId
        restartIdentity = window.restartIdentity
        weight = getWeightOrNil(window) ?? 1
        isFullscreen = window.isFullscreen
        noOuterGapsInFullscreen = window.noOuterGapsInFullscreen
        layoutReason = window.layoutReason
        lastFloatingSize = window.parent is Workspace && !window.isFullscreen
            ? window.lastKnownActualRect?.size ?? window.lastFloatingSize : window.lastFloatingSize
        singleWindowManualWidth = window.singleWindowManualWidth
        if window.nodeWorkspace?.isVisible == true, !window.isHiddenInCorner,
           let rect = window.lastKnownActualRect ?? window.lastAppliedLayoutPhysicalRect,
           let monitor = window.nodeMonitor
        {
            workspacePreviewFrame = normalizedWorkspacePreviewFrame(CGRect(origin: rect.topLeftCorner, size: rect.size),
                origin: monitor.rect.topLeftCorner, desktopSize: monitor.rect.size) ?? window.workspacePreviewFrame
        } else {
            workspacePreviewFrame = window.workspacePreviewFrame
        }
        minimumEvidenceVersion = 2
        learnedMinimumSize = (window as? MacWindow)?.learnedMinimum.size == .zero ? nil : (window as? MacWindow)?.learnedMinimum.size
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case restartIdentity
        case weight
        case isFullscreen
        case noOuterGapsInFullscreen
        case layoutReason
        case learnedMinimumSize
        case minimumEvidenceVersion
        case lastFloatingSize
        case singleWindowManualWidth
        case workspacePreviewFrame
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UInt32.self, forKey: .id)
        restartIdentity = try container.decodeIfPresent(RestartWindowIdentity.self, forKey: .restartIdentity)
        weight = try container.decode(CGFloat.self, forKey: .weight)
        isFullscreen = try container.decode(Bool.self, forKey: .isFullscreen)
        noOuterGapsInFullscreen = try container.decode(Bool.self, forKey: .noOuterGapsInFullscreen)
        layoutReason = try container.decodeIfPresent(LayoutReason.self, forKey: .layoutReason) ?? .standard
        minimumEvidenceVersion = try container.decodeIfPresent(Int.self, forKey: .minimumEvidenceVersion) ?? 1
        learnedMinimumSize = minimumEvidenceVersion == 2
            ? try container.decodeIfPresent(CGSize.self, forKey: .learnedMinimumSize) : nil
        lastFloatingSize = try container.decodeIfPresent(CGSize.self, forKey: .lastFloatingSize)
        singleWindowManualWidth = try container.decodeIfPresent(CGFloat.self, forKey: .singleWindowManualWidth)
        workspacePreviewFrame = try container.decodeIfPresent(CGRect.self, forKey: .workspacePreviewFrame)
    }
}

@MainActor private func getWeightOrNil(_ node: TreeNode) -> CGFloat? {
    ((node.parent as? TilingContainer)?.orientation).map { node.getWeight($0) }
}

extension FrozenTreeNode {
    private enum CodingKeys: String, CodingKey {
        case kind
        case container
        case window
    }

    private enum Kind: String, Codable {
        case container
        case window
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
            case .container:
                self = .container(try container.decode(FrozenContainer.self, forKey: .container))
            case .window:
                self = .window(try container.decode(FrozenWindow.self, forKey: .window))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .container(let frozenContainer):
                try container.encode(Kind.container, forKey: .kind)
                try container.encode(frozenContainer, forKey: .container)
            case .window(let frozenWindow):
                try container.encode(Kind.window, forKey: .kind)
                try container.encode(frozenWindow, forKey: .window)
        }
    }
}
