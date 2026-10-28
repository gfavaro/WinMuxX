import Common
import NativeSpaces

/// Explicit native Space navigation for `workspace`. macOS still owns Spaces; this
/// only asks the Dock to swipe. Landing is confirmed from fresh topology reads, taken as
/// Space-change events arrive and at least every `pollInterval`, and a
/// swipe that has not landed is posted once more from wherever the display is.
/// One switch is in flight per display: a request meanwhile only changes its target,
/// and the next swipe leaves once the posted one lands, so a burst of shortcuts never
/// swipes from a Space the display is about to leave. After Dinky's SpaceSwitcher.
@MainActor
final class NativeSpaceNavigator {
    private struct Flight {
        var target: String
        var waiters: [CheckedContinuation<Bool, Never>] = []
    }
    /// By display identifier.
    private var flights: [String: Flight] = [:]
    var topology: () async throws -> [NativeSpaceDisplay]
    var post: (NativeSpaceSwitchPlan) async -> Bool = { plan in
        await NativeDockSwipe.post(steps: abs(plan.toIndex - plan.fromIndex),
            towardHigherIndex: plan.toIndex > plan.fromIndex, displayIdentifier: plan.displayIdentifier)
    }
    var isSupported: () -> Bool = { NativeDockSwipe.isSupported }
    var canPostEvents: () -> Bool = { NativeDockSwipe.canPostEvents }
    var landingTimeout: Duration = .seconds(1)
    /// The backstop between reads when no Space-change event arrives.
    var pollInterval: Duration = .milliseconds(50)

    init() {
        let reader = NativeSpacesReader()
        topology = { try await reader.topology() }
    }

    /// Arguments native navigation implements; anything else stays unsupported.
    static func supports(_ args: WorkspaceCmdArgs) -> Bool {
        guard !args.useStdin, args.internalName == nil else { return false }
        switch args.target.val {
            case .relative: return true
            case .direct(let name): return Int(name.raw) != nil
        }
    }

    func selectDesktop(_ args: WorkspaceCmdArgs, io: CmdIo) async -> Bool {
        guard let observed = await readyTopology(io) else { return false }
        // Next and previous count from where a switch in flight is going.
        let displays = observed.map { display in flights[display.identifier].map { display.showing($0.target) } ?? display }
        guard var plan = resolve(args, displays, io) else { return false }
        // Already showing on another display: focus it there, as virtual workspaces do.
        if plan.isNoop, let shown = runtime.workspaceBackend.native.layouts.currentBySpaceID[plan.targetSpaceID],
           shown.isVisible, shown !== focus.workspace {
            guard let window = shown.mostRecentWindowRecursive, window.focusWindow() else {
                return io.err("That desktop is showing on another display and has no window to focus")
            }
            window.nativeFocus()
            return true
        }
        if plan.isNoop, args.autoBackAndForth,
           let display = displays.first(where: { $0.identifier == plan.displayIdentifier }),
           let previous = runtime.workspaceBackend.native.activity.previousDesktop(on: display),
           let back = NativeSpaceNavigation.toward(spaceID: previous, on: display) {
            plan = back
        }
        return await perform(plan, failIfNoop: args.failIfNoop, io: io)
    }

    /// UI rows retain the Space identity while the command waits for a fresh read.
    func selectDesktop(spaceUUID: String, io: CmdIo) async -> Bool {
        guard let displays = await readyTopology(io) else { return false }
        guard let display = displays.first(where: { $0.spaces.contains { $0.uuid == spaceUUID && $0.isDesktop } }),
              let spaceID = display.spaces.first(where: { $0.uuid == spaceUUID && $0.isDesktop })?.id,
              let plan = NativeSpaceNavigation.toward(spaceID: spaceID, on: display) else {
            return io.err("The selected native desktop no longer exists")
        }
        if plan.isNoop, let shown = runtime.workspaceBackend.native.layouts.currentBySpaceID[spaceID],
           shown.isVisible, shown !== focus.workspace {
            guard let window = shown.mostRecentWindowRecursive, window.focusWindow() else {
                return io.err("That desktop is showing on another display and has no window to focus")
            }
            window.nativeFocus()
            return true
        }
        return await perform(plan, failIfNoop: false, io: io)
    }

    /// `workspace-back-and-forth`: the focused display's previous desktop.
    func selectPreviousDesktop(io: CmdIo) async -> Bool {
        guard let displays = await readyTopology(io),
              let id = targetDisplay(monitor: nil, displays, io),
              let display = displays.first(where: { $0.identifier == id }) else { return false }
        guard let previous = runtime.workspaceBackend.native.activity.previousDesktop(on: display),
              let plan = NativeSpaceNavigation.toward(spaceID: previous, on: display) else {
            return io.err("No previous desktop on this display")
        }
        return await perform(plan, failIfNoop: false, io: io)
    }

    private func readyTopology(_ io: CmdIo) async -> [NativeSpaceDisplay]? {
        guard isSupported() else { _ = io.err("Native Space switching requires macOS 27 or later"); return nil }
        guard canPostEvents() else { _ = io.err("Native Space switching needs WinMuxX Accessibility permission"); return nil }
        do { return try await topology() } catch { _ = io.err("Native Spaces unavailable: \(error)"); return nil }
    }

    private func perform(_ initial: NativeSpaceSwitchPlan, failIfNoop: Bool, io: CmdIo) async -> Bool {
        let display = initial.displayIdentifier
        if flights[display] != nil {
            flights[display]!.target = initial.targetSpaceID
            let landed = await withCheckedContinuation { flights[display]!.waiters.append($0) }
            return landed || io.err("Native Space switch did not land on Space \(initial.targetSpaceID)")
        }
        if initial.isNoop {
            if failIfNoop { return false }
            io.err("Already on that Space. Tip: use --fail-if-noop to exit with non-zero code")
            return true
        }
        flights[display] = Flight(target: initial.targetSpaceID)
        let result = await fly(initial)
        let waiters = flights.removeValue(forKey: display)?.waiters ?? []
        waiters.forEach { $0.resume(returning: result == nil) }
        if result == nil { runtime.workspaceBackend.native.observation?.requestRead(event: "nativeSpaceSwitch") }
        return result.map { io.err($0) } ?? true
    }

    /// Swipes until the display shows the flight's newest target. Nil when it does, else why not.
    private func fly(_ initial: NativeSpaceSwitchPlan) async -> String? {
        let display = initial.displayIdentifier
        var plan = initial
        var retried = false
        while true {
            guard await post(plan) else { return "Posting the native Space switch failed" }
            let posted = plan.targetSpaceID
            let deadline = ContinuousClock.now + landingTimeout
            var latest: NativeSpaceDisplay?
            while ContinuousClock.now < deadline {
                await runtime.workspaceBackend.native.stateChanges.nextChange(before: min(deadline, .now + pollInterval))
                if Task.isCancelled { break }
                latest = (try? await topology())?.first { $0.identifier == display }
                if latest?.activeSpaceID == posted { break }
            }
            let target = flights[display]?.target ?? posted
            if latest?.activeSpaceID == target { return nil }
            if latest?.activeSpaceID == posted {
                retried = false // Landed on an older request; go on to the newest.
            } else if retried {
                return "Native Space switch did not land on Space \(target)"
            } else {
                retried = true
            }
            guard let latest, let next = NativeSpaceNavigation.toward(spaceID: target, on: latest) else {
                return "Native Space switch did not land on Space \(target)"
            }
            plan = next
        }
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
                guard let display = targetDisplay(monitor: args.monitorDescription, displays, io) else { return nil }
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
    private func targetDisplay(monitor: MonitorDescription?, _ displays: [NativeSpaceDisplay], _ io: CmdIo) -> String? {
        let known = Set(displays.map(\.identifier))
        if let description = monitor {
            guard let uuid = description.resolveMonitor(sortedMonitors: sortedMonitors)?.displayUUID, known.contains(uuid) else {
                _ = io.err("No native Space display matches '\(description)'")
                return nil
            }
            return uuid
        }
        if displays.count == 1 { return displays[0].identifier }
        let layouts = runtime.workspaceBackend.native.layouts
        let focused = focus.workspace
        let focusedDisplay = layouts.currentBySpaceID.values.contains { $0 === focused } ? focused.workspaceMonitor.displayUUID : nil
        if let uuid = focusedDisplay ?? mouseLocation.monitorApproximation.displayUUID, known.contains(uuid) { return uuid }
        _ = io.err("Cannot determine which display's Spaces to switch; use --monitor")
        return nil
    }
}
