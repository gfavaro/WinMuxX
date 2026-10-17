/// The overlay can disappear only after both its animation and workspace switch finish.
enum WorkspaceSwipePreviewPhase: Equatable {
    case idle
    case preparing
    case tracking
    case waitingForAnimationAndWorkspace
    case waitingForAnimation
    case waitingForWorkspace

    var isSettling: Bool {
        switch self {
            case .idle, .preparing, .tracking: false
            default: true
        }
    }

    mutating func imageReady() {
        if self == .preparing { self = .tracking }
    }

    mutating func settle(commit: Bool) {
        if self == .preparing { self = .idle; return }
        guard self == .tracking else { return }
        self = commit ? .waitingForAnimationAndWorkspace : .waitingForAnimation
    }

    mutating func animationFinished() {
        switch self {
            case .waitingForAnimationAndWorkspace: self = .waitingForWorkspace
            case .waitingForAnimation: self = .idle
            default: break
        }
    }

    mutating func workspaceReady() {
        switch self {
            case .waitingForAnimationAndWorkspace: self = .waitingForAnimation
            case .waitingForWorkspace: self = .idle
            default: break
        }
    }
}
