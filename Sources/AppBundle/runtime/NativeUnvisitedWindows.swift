import AppKit
import Common
import NativeSpaces

/// A window on a desktop that is not showing, known only from WindowServer. Native
/// tiling adopts windows through AX on visible desktops, so these are listed for
/// navigation and never laid out or moved from here.
struct NativeListedWindow: Equatable, Sendable {
    let windowId: UInt32
    let spaceID: String
    let pid: pid_t
    let title: String?
}

@MainActor
final class NativeUnvisitedWindows {
    static let shared = NativeUnvisitedWindows()
    private(set) var bySpaceID: [String: [NativeListedWindow]] = [:]
    private let reader = NativeSpacesReader()
    private var task: Task<Void, Never>?
    private var requested = false

    /// Reads the desktops that are not showing; coalesced, off the main actor.
    func refresh() {
        guard runtime.workspaceBackend.kind == .native, !isUnitTest else { return }
        guard task == nil else { requested = true; return }
        guard let displays = nativeObservedDisplays() else { return }
        let hidden = Set(displays.flatMap { display in
            display.spaces.filter { $0.isDesktop && $0.id != display.activeSpaceID }.map(\.id)
        })
        let reader = reader
        task = Task { @MainActor [weak self] in
            var found: [NativeListedWindow]?
            if let snapshot = try? await reader.snapshot(spaceIDs: hidden) {
                found = await Task.detached { nativeListedWindows(snapshot) }.value
            }
            guard let self else { return }
            self.task = nil
            if let found {
                let unmanaged = found.filter { Window.get(byId: $0.windowId) == nil }
                let grouped = Dictionary(grouping: unmanaged, by: \.spaceID)
                if grouped != self.bySpaceID {
                    self.bySpaceID = grouped
                    await updateWorkspaceSidebarModel()
                }
            }
            if self.requested { self.requested = false; self.refresh() }
        }
    }

    func spaceID(of windowId: UInt32) -> String? {
        bySpaceID.first { $0.value.contains { $0.windowId == windowId } }?.key
    }

    /// Test seam.
    func set(_ windows: [NativeListedWindow]) { bySpaceID = Dictionary(grouping: windows, by: \.spaceID) }
}

/// Ordinary app windows among the memberships: layer 0, a regular app, on one Space,
/// big enough to be a document. Titles need Screen Recording; without it they are nil.
nonisolated func nativeListedWindows(_ snapshot: NativeSpacesSnapshot) -> [NativeListedWindow] {
    let rows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let byId = Dictionary(rows.compactMap { row in (row[kCGWindowNumber as String] as? UInt32).map { ($0, row) } },
        uniquingKeysWith: { first, _ in first })
    return snapshot.windows.compactMap { membership in
        guard let space = membership.unambiguousSpaceID, let row = byId[membership.windowID],
              row[kCGWindowLayer as String] as? Int == 0,
              let pid = row[kCGWindowOwnerPID as String] as? pid_t,
              NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular,
              let bounds = row[kCGWindowBounds as String] as? [String: CGFloat],
              (bounds["Width"] ?? 0) >= 100, (bounds["Height"] ?? 0) >= 100 else { return nil }
        let title = (row[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return NativeListedWindow(windowId: membership.windowID, spaceID: space, pid: pid, title: title)
    }
}

/// Switches to a listed window's desktop first; the read after the switch adopts it,
/// then it is focused like any other native window.
@MainActor
func focusNativeWindow(_ windowId: UInt32) async throws -> String? {
    if Window.get(byId: windowId) == nil, let space = NativeUnvisitedWindows.shared.spaceID(of: windowId),
       let number = NativeSpaceNavigation.desktopNumber(of: space, in: nativeObservedDisplays() ?? []) {
        if let error = try await runNativeCommands(["workspace \(number)"]) { return error }
        for _ in 0..<50 where Window.get(byId: windowId) == nil { try await Task.sleep(for: .milliseconds(30)) }
        guard Window.get(byId: windowId) != nil else { return nil } // Shown, but not an adoptable window.
    }
    return try await runNativeCommands(nativeFocusWindowCommands(windowId))
}
