import Foundation

enum NativeLayoutProjection {
    // Structural conversion needs geometry for the complete retained tree. It
    // does not write frames; presentation/navigation still use visible children.
    @TaskLocal static var includesConcealed = false
}

extension TreeNode {
    /// Presentation-only filtering. Retained windows/groups never leave the live
    /// tree merely because native AX cannot currently expose them.
    var hasNativeLayoutWindow: Bool {
        if let window = self as? Window { return window.nativeLayoutEligible }
        return children.contains(where: \.hasNativeLayoutWindow)
    }
}

extension TilingContainer {
    @MainActor var frameLayoutChildren: [TreeNode] {
        runtime.workspaceBackend.kind == .native && !NativeLayoutProjection.includesConcealed
            ? children.filter(\.hasNativeLayoutWindow) : children
    }

    @MainActor var frameDwindleShares: [CGFloat]? {
        guard isExplicitDwindle else { return nil }
        let shares = dwindleShares(count: children.count)
        guard runtime.workspaceBackend.kind == .native, !NativeLayoutProjection.includesConcealed else { return shares }
        let visible = Set(frameLayoutChildren.map(ObjectIdentifier.init))
        let selected = children.indices.filter { visible.contains(ObjectIdentifier(children[$0])) }.map { shares[$0] }
        let total = selected.reduce(0, +)
        return total > 0 ? selected.map { $0 / total } : nil
    }
}
