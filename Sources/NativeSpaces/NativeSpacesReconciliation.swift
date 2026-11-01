import Foundation

public enum NativeSpacesReconciliation {
    /// Switching only active IDs needs incoming Spaces, while a structural change
    /// or a window/app event with unchanged topology refreshes current Spaces.
    public static func targets(previous: [NativeSpaceDisplay]?, current: [NativeSpaceDisplay]) -> Set<String> {
        guard let previous, previous.count == current.count,
              Set(previous.map(\.identifier)).count == previous.count,
              Set(current.map(\.identifier)).count == current.count,
              Set(previous.map(\.identifier)) == Set(current.map(\.identifier)) else {
            return Set(current.map(\.activeSpaceID))
        }
        let old = Dictionary(uniqueKeysWithValues: previous.map { ($0.identifier, $0) })
        guard current.allSatisfy({ old[$0.identifier]?.spaces == $0.spaces }) else {
            return Set(current.map(\.activeSpaceID))
        }
        let incoming = current.filter { old[$0.identifier]?.activeSpaceID != $0.activeSpaceID }.map(\.activeSpaceID)
        return Set(incoming.isEmpty ? current.map(\.activeSpaceID) : incoming)
    }
}
