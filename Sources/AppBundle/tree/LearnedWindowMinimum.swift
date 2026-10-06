import AppKit

func shouldLearnWindowMinimum(nativeFullscreen: Bool, nativeMinimized: Bool, animating: Bool) -> Bool {
    !nativeFullscreen && !nativeMinimized && !animating
}

/// Conservative, session-local evidence. A refused request is not proof of a minimum:
/// apps may resize asynchronously, and terminal windows round to character cells.
struct LearnedWindowMinimum {
    private(set) var size: CGSize = .zero

    init(size: CGSize = .zero) {
        self.size = size
    }

    mutating func observe(requested: CGSize, first: CGSize, confirmed: CGSize) {
        guard [requested.width, requested.height, first.width, first.height,
               confirmed.width, confirmed.height].allSatisfy({ $0.isFinite && $0 > 0 }) else { return }
        if abs(first.width - confirmed.width) <= 2, confirmed.width - requested.width >= 32 {
            size.width = max(size.width, min(first.width, confirmed.width))
        }
        if abs(first.height - confirmed.height) <= 2, confirmed.height - requested.height >= 32 {
            size.height = max(size.height, min(first.height, confirmed.height))
        }
        // A later successful smaller resize disproves an earlier learned floor.
        if abs(confirmed.width - requested.width) <= 2, confirmed.width < size.width { size.width = 0 }
        if abs(confirmed.height - requested.height) <= 2, confirmed.height < size.height { size.height = 0 }
    }

    var isEmpty: Bool { size == .zero }
}
