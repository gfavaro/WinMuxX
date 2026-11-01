import Foundation

/// A requested native Space switch on one display. Indices are positions in the
/// display's Space list, fullscreen Spaces included, because a Dock swipe steps
/// through every Space the way Control-arrow does.
public struct NativeSpaceSwitchPlan: Equatable, Sendable {
    public let displayIdentifier: String
    public let fromIndex: Int
    public let toIndex: Int
    public let targetSpaceID: String

    public var isNoop: Bool { fromIndex == toIndex }
}

/// Pure target resolution. Numbering follows macOS's own shortcuts so WinMuxX
/// bindings and Mission Control agree on what "Desktop 3" means.
public enum NativeSpaceNavigation {
    /// macOS's Control-N numbering: ordinary desktops counted across displays in
    /// managed-display order, skipping fullscreen Spaces. Nil when N doesn't exist.
    public static func desktop(number: Int, in displays: [NativeSpaceDisplay]) -> NativeSpaceSwitchPlan? {
        guard number >= 1 else { return nil }
        var remaining = number
        for display in displays {
            for (index, space) in display.spaces.enumerated() where space.isDesktop {
                remaining -= 1
                if remaining == 0 { return plan(display, to: index) }
            }
        }
        return nil
    }

    /// macOS's Control-arrow: the adjacent Space on one display, fullscreen
    /// Spaces included. Without wrap-around the ends are not crossed.
    public static func adjacent(next: Bool, wrapAround: Bool, on displayIdentifier: String,
                                in displays: [NativeSpaceDisplay]) -> NativeSpaceSwitchPlan? {
        guard let display = displays.first(where: { $0.identifier == displayIdentifier }),
              let from = display.spaces.firstIndex(where: { $0.id == display.activeSpaceID }) else { return nil }
        let count = display.spaces.count
        var to = from + (next ? 1 : -1)
        if !(0..<count).contains(to) {
            guard wrapAround else { return nil }
            to = (to + count) % count
        }
        return plan(display, to: to)
    }

    /// A fresh plan to an existing Space from wherever the display is now, used to
    /// retry a swipe that landed short. Nil when the Space left the display.
    public static func toward(spaceID: String, on display: NativeSpaceDisplay) -> NativeSpaceSwitchPlan? {
        display.spaces.firstIndex { $0.id == spaceID }.flatMap { plan(display, to: $0) }
    }

    /// The 1-based desktop number of a Space, or nil for a fullscreen or unknown Space.
    public static func desktopNumber(of spaceID: String, in displays: [NativeSpaceDisplay]) -> Int? {
        let desktops = displays.flatMap { $0.spaces.filter(\.isDesktop) }
        return desktops.firstIndex { $0.id == spaceID }.map { $0 + 1 }
    }

    /// The 1-based desktop number of a display's active Space, or nil on a
    /// fullscreen Space. Inverse of `desktop(number:in:)`.
    public static func activeDesktopNumber(on displayIdentifier: String, in displays: [NativeSpaceDisplay]) -> Int? {
        var number = 0
        for display in displays {
            for space in display.spaces where space.isDesktop {
                number += 1
                if display.identifier == displayIdentifier, space.id == display.activeSpaceID { return number }
            }
        }
        return nil
    }

    private static func plan(_ display: NativeSpaceDisplay, to index: Int) -> NativeSpaceSwitchPlan? {
        guard let from = display.spaces.firstIndex(where: { $0.id == display.activeSpaceID }) else { return nil }
        return NativeSpaceSwitchPlan(displayIdentifier: display.identifier, fromIndex: from, toIndex: index,
            targetSpaceID: display.spaces[index].id)
    }
}
