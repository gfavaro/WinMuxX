import Common
import NativeSpaces

/// Explicit native Space navigation for `workspace`. macOS still owns Spaces; this
/// only asks the Dock to swipe. Landing is confirmed from fresh topology reads, a
/// swipe that has not landed is posted once more from wherever the display is, and
/// a newer request supersedes an older one rather than replaying obsolete swipes.
@MainActor
final class NativeSpaceNavigator {
    private var generation = 0
    var topology: () async throws -> [NativeSpaceDisplay]
    var post: (NativeSpaceSwitchPlan) async -> Bool = { plan in
        await NativeDockSwipe.post(steps: abs(plan.toIndex - plan.fromIndex),
            towardHigherIndex: plan.toIndex > plan.fromIndex, displayIdentifier: plan.displayIdentifier)
    }
    var isSupported: () -> Bool = { NativeDockSwipe.isSupported }
    var canPostEvents: () -> Bool = { NativeDockSwipe.canPostEvents }
    var landingTimeout: Duration = .seconds(1)
    var pollInterval: Duration = .milliseconds(20)

    init() {
        let reader = NativeSpacesReader()
        topology = { try await reader.topology() }
    }

    /// Arguments native navigation implements; anything else stays unsupported.
    static func supports(_ args: WorkspaceCmdArgs) -> Bool {
        guard !args.autoBackAndForth, !args.useStdin, args.internalName == nil else { return false }
        switch args.target.val {
            case .relative: return true
            case .direct(let name): return Int(name.raw) != nil
        }
    }

    func run(_ args: WorkspaceCmdArgs, io: CmdIo) async -> Bool {
        guard isSupported() else { return io.err("Native Space switching requires macOS 27 or later") }
        guard canPostEvents() else { return io.err("Native Space switching needs WinMuxX Accessibility permission") }
        let displays: [NativeSpaceDisplay]
        do { displays = try await topology() } catch { return io.err("Native Spaces unavailable: \(error)") }
        guard var plan = resolve(args, displays, io) else { return false }
        if plan.isNoop {
            if args.failIfNoop { return false }
            io.err("Already on that Space. Tip: use --fail-if-noop to exit with non-zero code")
            return true
        }
        generation += 1
        let request = generation
        for attempt in 0..<2 {
            guard await post(plan) else { return io.err("Posting the native Space switch failed") }
            let deadline = ContinuousClock.now + landingTimeout
            var latest: NativeSpaceDisplay?
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: pollInterval)
                guard request == generation else { return true } // A newer request owns the display.
                latest = (try? await topology())?.first { $0.identifier == plan.displayIdentifier }
                if latest?.activeSpaceID == plan.targetSpaceID {
                    runtime.workspaceBackend.observation?.requestRead(event: "nativeSpaceSwitch")
                    return true
                }
            }
            guard attempt == 0, let latest, let retry = NativeSpaceNavigation.toward(spaceID: plan.targetSpaceID, on: latest) else { break }
            plan = retry
        }
        return io.err("Native Space switch did not land on Space \(plan.targetSpaceID)")
    }

    private func resolve(_ args: WorkspaceCmdArgs, _ displays: [NativeSpaceDisplay], _ io: CmdIo) -> NativeSpaceSwitchPlan? {
        switch args.target.val {
            case .direct(let name):
                guard let number = Int(name.raw) else {
                    _ = io.err("Native Spaces are addressed by desktop number, as in Mission Control")
                    return nil
                }
                guard let plan = NativeSpaceNavigation.desktop(number: number, in: displays) else {
                    _ = io.err("Desktop \(number) doesn't exist; add it in Mission Control")
                    return nil
                }
                return plan
            case .relative(let direction):
                guard let display = targetDisplay(args, displays, io) else { return nil }
                guard let plan = NativeSpaceNavigation.adjacent(next: direction == .next, wrapAround: args.wrapAround,
                    on: display, in: displays) else {
                    _ = io.err("No \(direction == .next ? "next" : "previous") Space on this display")
                    return nil
                }
                return plan
        }
    }

    /// The display Control-arrow would act on: the focused native desktop's display,
    /// else the one under the pointer.
    private func targetDisplay(_ args: WorkspaceCmdArgs, _ displays: [NativeSpaceDisplay], _ io: CmdIo) -> String? {
        let known = Set(displays.map(\.identifier))
        if let description = args.monitorDescription {
            guard let uuid = description.resolveMonitor(sortedMonitors: sortedMonitors)?.displayUUID, known.contains(uuid) else {
                _ = io.err("No native Space display matches '\(description)'")
                return nil
            }
            return uuid
        }
        if displays.count == 1 { return displays[0].identifier }
        let layouts = runtime.workspaceBackend.nativeLayouts
        let focused = focus.workspace
        let focusedDisplay = layouts.currentBySpaceID.values.contains { $0 === focused } ? focused.workspaceMonitor.displayUUID : nil
        if let uuid = focusedDisplay ?? mouseLocation.monitorApproximation.displayUUID, known.contains(uuid) { return uuid }
        _ = io.err("Cannot determine which display's Spaces to switch; use --monitor")
        return nil
    }
}
