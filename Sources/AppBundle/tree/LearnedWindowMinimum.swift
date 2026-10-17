import AppKit

func shouldLearnWindowMinimum(nativeFullscreen: Bool, nativeMinimized: Bool, animating: Bool) -> Bool {
    !nativeFullscreen && !nativeMinimized && !animating
}

/// A stable refusal is only evidence after two different requests hit the same
/// floor. Repeating a tile proves nothing for apps that snap to character cells.
struct LearnedWindowMinimum {
    private(set) var size: CGSize = .zero
    private var previousWidth: (asked: CGFloat, got: CGFloat)?
    private var previousHeight: (asked: CGFloat, got: CGFloat)?

    init(size: CGSize = .zero) {
        self.size = size
    }

    mutating func observe(requested: CGSize, first: CGSize, confirmed: CGSize) {
        guard [requested.width, requested.height, first.width, first.height,
               confirmed.width, confirmed.height].allSatisfy({ $0.isFinite && $0 > 0 }) else { return }
        Self.observe(requested.width, first.width, confirmed.width, floor: &size.width, previous: &previousWidth)
        Self.observe(requested.height, first.height, confirmed.height, floor: &size.height, previous: &previousHeight)
    }

    private static func observe(_ asked: CGFloat, _ first: CGFloat, _ got: CGFloat,
                                floor: inout CGFloat, previous: inout (asked: CGFloat, got: CGFloat)?) {
        // A successful smaller resize disproves an earlier learned floor.
        if abs(got - asked) <= 2, got < floor { floor = 0 }
        guard abs(first - got) <= 2, got - asked >= 32 else { previous = nil; return }
        let stable = min(first, got)
        if let earlier = previous {
            if abs(earlier.asked - asked) <= 2 { return }
            if abs(earlier.got - stable) <= 2 { floor = max(floor, max(earlier.got, stable)) }
        }
        previous = (asked, stable)
    }

    var isEmpty: Bool { size == .zero }
}
