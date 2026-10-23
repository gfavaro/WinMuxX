import AppKit
import Common

enum ShortcutHealth: Equatable {
    case available
    case unavailable
}

enum HotkeyRecoveryResult: Equatable {
    case recovered
    case noLongerRequired
    case exhausted
    case cancelled
}

@MainActor
func runHotkeyRecovery(
    delays: [Duration],
    shouldContinue: () -> Bool,
    wait: (Duration) async throws -> Void,
    attempt: () -> Bool
) async -> HotkeyRecoveryResult {
    for delay in delays {
        do { try await wait(delay) } catch { return .cancelled }
        guard !Task.isCancelled else { return .cancelled }
        guard shouldContinue() else { return .noLongerRequired }
        if attempt() { return .recovered }
    }
    return .exhausted
}

private let sideFilteredCallback: CGEventTapCallBack = { _, type, event, _ in
    nonisolated(unsafe) let borrowedEvent = event
    let consumed = MainActor.assumeIsolated {
        SideFilteredHotkeys.shared.handle(type, borrowedEvent)
    }
    return consumed ? nil : Unmanaged.passUnretained(event)
}

/// Restricted chords never register with Carbon, which would consume both modifier sides.
@MainActor final class SideFilteredHotkeys {
    static let shared = SideFilteredHotkeys()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var consumedKeys = Set<Int64>()
    private var recoveryTask: Task<Void, Never>?
    private var recoveryGeneration: UInt64 = 0

    private func isRequiredByActiveMode() -> Bool {
        guard let mode = activeMode.flatMap({ config.modes[$0] }) else { return false }
        return mode.exitOnUnboundKey || mode.bindings.values.contains { config.modifierSides.restricts($0.modifiers) }
    }

    func stopRecovery() {
        recoveryGeneration &+= 1
        recoveryTask?.cancel()
        recoveryTask = nil
    }

    private func scheduleRecovery() {
        guard recoveryTask == nil else { return }
        recoveryGeneration &+= 1
        let generation = recoveryGeneration
        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await runHotkeyRecovery(
                delays: [.milliseconds(500), .milliseconds(1_000), .milliseconds(2_000), .milliseconds(4_000)],
                shouldContinue: { [weak self] in
                    guard let self else { return false }
                    return self.recoveryGeneration == generation && self.isRequiredByActiveMode()
                },
                wait: { try await Task.sleep(for: $0) },
                attempt: { [weak self] in self?.install(scheduleOnFailure: false) == true }
            )
            guard self.recoveryGeneration == generation else { return }
            self.recoveryTask = nil
            if result == .exhausted { TrayMenuModel.shared.shortcutHealth = .unavailable }
        }
    }

    func install(scheduleOnFailure: Bool = true) -> Bool {
        if let tap {
            if CGEvent.tapIsEnabled(tap: tap) {
                TrayMenuModel.shared.shortcutHealth = .available
                if scheduleOnFailure { stopRecovery() }
                return true
            }
            CGEvent.tapEnable(tap: tap, enable: true)
            let restored = CGEvent.tapIsEnabled(tap: tap)
            TrayMenuModel.shared.shortcutHealth = restored ? .available : .unavailable
            if restored { stopRecovery() } else if scheduleOnFailure { scheduleRecovery() }
            return restored
        }
        if isUnitTest { return true }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: sideFilteredCallback, userInfo: nil),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            TrayMenuModel.shared.shortcutHealth = .unavailable
            if scheduleOnFailure { scheduleRecovery() }
            return false
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        TrayMenuModel.shared.shortcutHealth = .available
        if scheduleOnFailure { stopRecovery() }
        return true
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            consumedKeys.removeAll()
            finishUnboundKeyPassThrough(keyCode: nil)
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if tap.map({ CGEvent.tapIsEnabled(tap: $0) }) == true {
                TrayMenuModel.shared.shortcutHealth = .available
                stopRecovery()
            } else {
                TrayMenuModel.shared.shortcutHealth = .unavailable
                scheduleRecovery()
            }
            return false
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            finishUnboundKeyPassThrough(keyCode: key)
            return consumedKeys.remove(key) != nil
        }
        guard type == .keyDown else { return false }
        if consumedKeys.contains(key), event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        if exitModeForUnboundKey(keyCode: key, flags: flags) { return false }
        let consumed = handleSideFilteredKeyDown(keyCode: key, flags: flags)
        if consumed { consumedKeys.insert(key) }
        // Keep the rest of an accepted key press consumed if its command changed mode.
        return consumed || (consumedKeys.contains(key) && event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
    }
}
