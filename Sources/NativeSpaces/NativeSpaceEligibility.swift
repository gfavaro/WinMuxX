import Foundation

public enum NativeSpaceExclusion: String, Codable, Equatable, Sendable {
    case unknownDisplay
    case unknownWindow
    case unknownMembership
    case sharedWindow
    case unknownSpace
    case otherDisplay
    case inactiveSpace
    case nonDesktopSpace
    case sharedDesktop
}

public enum NativeSpaceEligibility: Equatable, Sendable {
    case desktop(spaceID: String, spaceUUID: String?)
    case excluded(NativeSpaceExclusion)
}

extension NativeSpacesSnapshot {
    /// Backend-neutral classification of an immutable observation, not a write
    /// permit. A future frame writer must also validate observation generation,
    /// native transition state and live window/process identity before each write.
    /// Unknown membership never means "closed" or "use the focused workspace".
    public func eligibility(windowID: UInt32, on displayIdentifier: String) -> NativeSpaceEligibility {
        guard let display = displays.first(where: { $0.identifier == displayIdentifier }) else {
            return .excluded(.unknownDisplay)
        }
        guard let membership = windows.first(where: { $0.windowID == windowID }) else {
            return .excluded(.unknownWindow)
        }
        guard let ids = membership.spaceIDs, !ids.isEmpty else { return .excluded(.unknownMembership) }
        guard ids.count == 1 else { return .excluded(.sharedWindow) }
        let id = ids[0]
        let owners = displays.filter { $0.spaces.contains(where: { $0.id == id }) }
        guard !owners.isEmpty else { return .excluded(.unknownSpace) }
        // A single Space spanning displays needs display-region layout ownership.
        // Do not silently split it into two independently owned workspaces.
        guard owners.count == 1 else { return .excluded(.sharedDesktop) }
        guard let space = display.spaces.first(where: { $0.id == id }) else { return .excluded(.otherDisplay) }
        guard space.isDesktop else { return .excluded(.nonDesktopSpace) }
        guard display.activeSpaceID == id else { return .excluded(.inactiveSpace) }
        return .desktop(spaceID: id, spaceUUID: space.uuid)
    }
}
