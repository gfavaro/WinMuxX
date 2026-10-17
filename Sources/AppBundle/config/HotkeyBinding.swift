import AppKit
import Common
import Foundation
import HotKey
import TOMLKit

@MainActor
final class HotkeyState {
    var hotkeys: [String: HotKey] = [:]
    var sideFilteredBindings: [Int64: [HotkeyBinding]] = [:]
    var activeTapBindings: [TapModifierKey: TapBinding] = [:]
    var pendingTapBindings: [TapModifierKey: TapBinding] = [:]
    var pressedTapModifiers: Set<TapModifierKey> = []
    var pendingTapTriggerTasks: [TapModifierKey: Task<Void, Never>] = [:]
    var pendingTapTriggerTokens: [TapModifierKey: Int] = [:]
    var nextTapTriggerToken = 0
    var hotkeysSuspended = false
    var sequenceBindingsByPrefix: [Key: [SequenceBinding]] = [:]
    var sequenceBindingsPrefixKeys: Set<Key> = []
    /// Timestamp of the last Escape press, used for sequence detection via local monitor
    var lastSequencePrefixTime: DispatchTime? = nil
    /// Which prefix key was pressed last
    var lastSequencePrefixKey: Key? = nil
    var activeMode: String? = mainModeId

    isolated deinit {
        for task in pendingTapTriggerTasks.values { task.cancel() }
        for key in hotkeys.values { key.isEnabled = false }
    }
}

@MainActor private var hotkeyState: HotkeyState { runtime.hotkeys }
@MainActor var sequenceBindingsPrefixKeys: Set<Key> {
    get { hotkeyState.sequenceBindingsPrefixKeys }
    set { hotkeyState.sequenceBindingsPrefixKeys = newValue }
}
private let tapBindingTriggerDelayNs: UInt64 = 75_000_000
/// Max time (ns) between prefix key and subsequent key for a sequence binding
private let sequenceChordTimeoutNs: UInt64 = 300_000_000 // 300ms

@MainActor func resetHotKeys() {
    // Explicitly unregister all hotkeys. We cannot always rely on destruction of the HotKey object to trigger
    // unregistration because we might be running inside a hotkey handler that is keeping its HotKey object alive.
    for (_, key) in hotkeyState.hotkeys {
        key.isEnabled = false
    }
    hotkeyState.hotkeys = [:]
    hotkeyState.activeTapBindings = [:]
    hotkeyState.sideFilteredBindings = [:]
    hotkeyState.pendingTapBindings = [:]
    hotkeyState.pressedTapModifiers = []
    cancelPendingTapTriggers()
    hotkeyState.sequenceBindingsByPrefix = [:]
    sequenceBindingsPrefixKeys = []
    hotkeyState.lastSequencePrefixTime = nil
    hotkeyState.lastSequencePrefixKey = nil
    hotkeyState.hotkeysSuspended = false
}

extension HotKey {
    var isEnabled: Bool {
        get { !isPaused }
        set {
            if isEnabled != newValue {
                isPaused = !newValue
            }
        }
    }
}

@MainActor var activeMode: String? {
    get { hotkeyState.activeMode }
    set { hotkeyState.activeMode = newValue }
}
@MainActor func setHotkeysSuspended(_ suspended: Bool) {
    if hotkeyState.hotkeysSuspended == suspended { return }
    hotkeyState.hotkeysSuspended = suspended
    if suspended {
        hotkeyState.pendingTapBindings = [:]
        hotkeyState.pressedTapModifiers = []
        cancelPendingTapTriggers()
    }
    applyHotkeyEnabledState()
}

@MainActor func activateMode(_ targetMode: String?) async throws {
    let owner = runtime
    let mode = targetMode.flatMap { config.modes[$0] }
    let targetBindings = mode?.bindings ?? [:]
    hotkeyState.sideFilteredBindings = Dictionary(grouping: targetBindings.values.filter { config.modifierSides.restricts($0.modifiers) },
        by: { Int64($0.keyCode.carbonKeyCode) })
    hotkeyState.activeTapBindings = mode?
        .tapBindings
        .values
        .reduce(into: [:]) { $0[$1.trigger] = $1 } ?? [:]
    hotkeyState.pendingTapBindings = [:]
    hotkeyState.pressedTapModifiers = []
    cancelPendingTapTriggers()
    for binding in targetBindings.values where !config.modifierSides.restricts(binding.modifiers) && !hotkeyState.hotkeys.keys.contains(binding.descriptionWithKeyCode) {
        hotkeyState.hotkeys[binding.descriptionWithKeyCode] = HotKey(key: binding.keyCode, modifiers: binding.modifiers, keyDownHandler: { [weak owner] in
            Task { @MainActor in
                guard let owner else { return }
                owner.withValue {
                    if hotkeyState.hotkeysSuspended { return }
                    noteTapBindingKeyDown()
                    triggerBinding(binding.descriptionWithKeyNotation, binding.commands)
                }
            }
        })
    }
    // Populate sequence binding lookup tables
    hotkeyState.sequenceBindingsByPrefix = [:]
    sequenceBindingsPrefixKeys = []
    hotkeyState.lastSequencePrefixTime = nil
    hotkeyState.lastSequencePrefixKey = nil
    if let seqBindings = mode?.sequenceBindings.values {
        for seq in seqBindings {
            hotkeyState.sequenceBindingsByPrefix[seq.prefix, default: []].append(seq)
            sequenceBindingsPrefixKeys.insert(seq.prefix)
        }
    }
    if targetBindings.values.contains(where: { config.modifierSides.restricts($0.modifiers) }),
       !SideFilteredHotkeys.shared.install() {
        MessageModel.shared.message = Message(description: "Shortcut modifiers", body: "Could not install side-filtered shortcuts. Check WinMuxX Accessibility access, then reload the configuration.")
    }
    let oldMode = activeMode
    activeMode = targetMode
    applyHotkeyEnabledState()
    if oldMode != targetMode {
        broadcastEvent(.modeChanged(mode: targetMode))
        if !config.onModeChanged.isEmpty {
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.onModeChanged, token) {
                _ = try await config.onModeChanged.runCmdSeq(.defaultEnv, .emptyStdin)
            }
        }
    }
}

@MainActor private func triggerBinding(_ binding: String, _ commands: [any Command]) {
    if hotkeyState.hotkeysSuspended { return }
    let owner = runtime
    Task {
        try await owner.withValue {
            if let activeMode {
                broadcastEvent(.bindingTriggered(
                    mode: activeMode,
                    binding: binding,
                ))
                try await runLightSession(
                    .hotkeyBinding,
                    .checkServerIsEnabledOrDie(),
                    shouldSchedulePostRefresh: !commands.canSkipPostCommandRefresh
                ) { () throws in
                    _ = try await commands.runCmdSeq(.defaultEnv, .emptyStdin)
                }
            }
        }
    }
}

/// Called from the local keyDown monitor when the Escape key (or other prefix key)
/// is pressed. Records the timestamp so a subsequent matching key can trigger a
/// sequence binding. Does NOT consume the event.
@MainActor func noteSequencePrefixKeyPressed(_ prefix: Key) {
    hotkeyState.lastSequencePrefixTime = DispatchTime.now()
    hotkeyState.lastSequencePrefixKey = prefix
}

/// Called from the local keyDown monitor for every keyDown event.
/// If a prefix key was pressed recently (within `sequenceChordTimeoutNs`),
/// checks if this key matches a sequence binding and executes it.
/// Returns true if the event was consumed (should not reach the app).
@MainActor func handleSequenceKeyDown(event: NSEvent) -> Bool {
    guard let prefix = hotkeyState.lastSequencePrefixKey,
          let lastTime = hotkeyState.lastSequencePrefixTime,
          let bindings = hotkeyState.sequenceBindingsByPrefix[prefix] else {
        return false
    }
    let elapsed = DispatchTime.now().uptimeNanoseconds - lastTime.uptimeNanoseconds
    guard elapsed < sequenceChordTimeoutNs else {
        // Timeout expired, clear state
        hotkeyState.lastSequencePrefixTime = nil
        hotkeyState.lastSequencePrefixKey = nil
        return false
    }
    // Check if this key matches any sequence binding for this prefix
    for seq in bindings {
        if seq.key.carbonKeyCode == event.keyCode {
            // Match! Execute the command and consume the event
            hotkeyState.lastSequencePrefixTime = nil
            hotkeyState.lastSequencePrefixKey = nil
            triggerBinding(seq.descriptionWithKeyNotation, seq.commands)
            return true
        }
    }
    // No match - clear state and let event pass through
    hotkeyState.lastSequencePrefixTime = nil
    hotkeyState.lastSequencePrefixKey = nil
    return false
}

@MainActor func noteTapBindingKeyDown() {
    if hotkeyState.hotkeysSuspended { return }
    cancelPendingTapTriggers()
    hotkeyState.pendingTapBindings = [:]
}

@MainActor func noteTapBindingFlagsChanged(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
    if hotkeyState.hotkeysSuspended { return }
    if hotkeyState.activeTapBindings.isEmpty && hotkeyState.pendingTapBindings.isEmpty && hotkeyState.pendingTapTriggerTasks.isEmpty { return }
    guard let tapModifier = TapModifierKey(keyCode: keyCode) else { return }
    cancelPendingTapTriggers()

    // Rebuild the pressed-modifier state from the event snapshot instead of only
    // applying the single changed key. macOS can occasionally drop a modifier
    // release event; if that happens, a stale entry here makes later single-key
    // tap launchers look like multi-modifier chords and they stop firing.
    hotkeyState.pressedTapModifiers = tapModifiersPressed(in: modifierFlags)

    if hotkeyState.pressedTapModifiers.contains(tapModifier) {
        let hadOtherPressedModifiers = !hotkeyState.pressedTapModifiers.subtracting([tapModifier]).isEmpty
        hotkeyState.pendingTapBindings = [:]
        if !hadOtherPressedModifiers, let binding = hotkeyState.activeTapBindings[tapModifier] {
            hotkeyState.pendingTapBindings[tapModifier] = binding
        }
        return
    }

    if let binding = hotkeyState.pendingTapBindings.removeValue(forKey: tapModifier) {
        scheduleTapBindingTrigger(binding)
    }
}

private func tapModifiersPressed(in modifierFlags: NSEvent.ModifierFlags) -> Set<TapModifierKey> {
    Set(TapModifierKey.allCases.filter { $0.isPressed(in: modifierFlags) })
}

@MainActor private func scheduleTapBindingTrigger(_ binding: TapBinding) {
    let trigger = binding.trigger
    hotkeyState.nextTapTriggerToken += 1
    let token = hotkeyState.nextTapTriggerToken
    hotkeyState.pendingTapTriggerTokens[trigger] = token
    let owner = runtime
    let task = Task { @MainActor [weak owner] in
        do { try await Task.sleep(nanoseconds: tapBindingTriggerDelayNs) } catch { return }
        guard let owner else { return }
        owner.withValue {
            guard hotkeyState.pendingTapTriggerTokens[trigger] == token else { return }
            hotkeyState.pendingTapTriggerTasks[trigger] = nil
            hotkeyState.pendingTapTriggerTokens[trigger] = nil
            guard hotkeyState.pressedTapModifiers.isEmpty else { return }
            triggerBinding(binding.descriptionWithKeyNotation, binding.commands)
        }
    }
    hotkeyState.pendingTapTriggerTasks[trigger] = task
}

@MainActor private func cancelPendingTapTriggers() {
    for task in hotkeyState.pendingTapTriggerTasks.values {
        task.cancel()
    }
    hotkeyState.pendingTapTriggerTasks = [:]
    hotkeyState.pendingTapTriggerTokens = [:]
}

@MainActor private func applyHotkeyEnabledState() {
    let targetBindings = activeMode.flatMap { config.modes[$0] }?.bindings ?? [:]
    for (binding, key) in hotkeyState.hotkeys {
        key.isEnabled = !hotkeyState.hotkeysSuspended && targetBindings[binding].map { !config.modifierSides.restricts($0.modifiers) } == true
    }
}

@MainActor func tapBindingPressedModifiersForTests() -> Set<TapModifierKey> {
    hotkeyState.pressedTapModifiers
}

@MainActor func hasPendingTapBindingForTests() -> Bool {
    !hotkeyState.pendingTapBindings.isEmpty || !hotkeyState.pendingTapTriggerTasks.isEmpty
}

@MainActor func sideFilteredBinding(keyCode: Int64, flags: NSEvent.ModifierFlags) -> HotkeyBinding? {
    guard !hotkeyState.hotkeysSuspended, TrayMenuModel.shared.isEnabled, activeMode != nil else { return nil }
    return hotkeyState.sideFilteredBindings[keyCode]?.first { config.modifierSides.matches($0.modifiers, flags: flags) }
}

@MainActor func handleSideFilteredKeyDown(keyCode: Int64, flags: NSEvent.ModifierFlags) -> Bool {
    guard let binding = sideFilteredBinding(keyCode: keyCode, flags: flags) else { return false }
    noteTapBindingKeyDown()
    triggerBinding(binding.descriptionWithKeyNotation, binding.commands)
    return true
}
