import Foundation

/// The adjacent workspace a swipe previews; only release can commit it.
struct WorkspaceSwipeRequest: Equatable {
    let displayPoint: CGPoint
    let isNext: Bool
    let progress: Double
    let slidesLeft: Bool
}
