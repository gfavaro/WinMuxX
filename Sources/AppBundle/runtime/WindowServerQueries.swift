import AppKit
import PrivateApi

/// Immutable closures can be captured by an app's AX thread without consulting main-actor state.
struct WindowServerQueries: Sendable {
    var exists: @Sendable (UInt32) -> Bool
    var frame: @Sendable (UInt32) -> CGRect?

    static let live = WindowServerQueries(
        exists: { winmux_window_exists($0) },
        frame: { id in
            var rect = CGRect.zero
            return winmux_window_frame(id, &rect) ? rect : nil
        })
    static let empty = WindowServerQueries(exists: { _ in false }, frame: { _ in nil })
}
