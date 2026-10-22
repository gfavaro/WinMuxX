import AppKit
import Common

struct ModeBindingToken {
    let generation: UInt64
    let id: UInt64
}

/// One deadline belongs to one activation, not merely to a mode name.
@MainActor
final class ModeSession {
    private(set) var generation: UInt64 = 0
    private var cancelDeadline: (() -> Void)?
    private var acceptedBindings = Set<UInt64>()
    private var nextBindingId: UInt64 = 0
    private var deadlineGeneration: UInt64 = 0
    var schedule: ((Int, @escaping @MainActor () -> Void) -> (() -> Void))?

    func invalidate() {
        generation &+= 1
        deadlineGeneration &+= 1
        cancelDeadline?()
        cancelDeadline = nil
        acceptedBindings.removeAll()
    }

    func activate(preservingAcceptedWork: Bool = false) {
        let accepted = acceptedBindings
        invalidate()
        if preservingAcceptedWork { acceptedBindings = accepted }
        arm()
    }

    func begin(expected: UInt64) -> ModeBindingToken? {
        guard expected == generation, activeMode != nil,
              !runtime.hotkeys.hotkeysSuspended, TrayMenuModel.shared.isEnabled else { return nil }
        cancelDeadline?()
        cancelDeadline = nil
        deadlineGeneration &+= 1
        nextBindingId &+= 1
        acceptedBindings.insert(nextBindingId)
        return ModeBindingToken(generation: generation, id: nextBindingId)
    }

    func finish(_ token: ModeBindingToken) {
        guard acceptedBindings.remove(token.id) != nil else { return }
        if acceptedBindings.isEmpty { arm() }
    }

    private func arm() {
        guard acceptedBindings.isEmpty, !runtime.hotkeys.hotkeysSuspended,
              TrayMenuModel.shared.isEnabled, let name = activeMode, name != mainModeId,
              let mode = config.modes[name], mode.timeoutMs > 0 else { return }
        deadlineGeneration &+= 1
        let deadline = deadlineGeneration
        let token = generation
        let owner = runtime
        let fire: @MainActor () -> Void = { [weak self, weak owner] in
            guard let self, let owner else { return }
            owner.withValue {
                guard self.generation == token, self.deadlineGeneration == deadline, self.acceptedBindings.isEmpty, activeMode == name,
                      !owner.hotkeys.hotkeysSuspended, TrayMenuModel.shared.isEnabled else { return }
                // Commit activation before its first suspension. Hooks may themselves change mode.
                owner.task {
                    guard self.generation == token, self.deadlineGeneration == deadline, self.acceptedBindings.isEmpty else { return }
                    do { try await activateMode(mainModeId) }
                    catch { NSLog("WinMuxX mode timeout activation failed: %@", String(describing: error)) }
                }
            }
        }
        if let schedule { cancelDeadline = schedule(mode.timeoutMs, fire) }
        else {
            let task = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(mode.timeoutMs)) }
                catch { return }
                fire()
            }
            cancelDeadline = { task.cancel() }
        }
    }

    isolated deinit { cancelDeadline?() }
}

struct ModePresentation: Equatable, Sendable {
    let name: String
    let initial: String
    let configuredColor: String?
    let escapeReturnsToMain: Bool

    init(name: String, mode: Mode) {
        self.name = name
        initial = name.trimmingCharacters(in: .whitespacesAndNewlines).first
            .flatMap { String($0).uppercased().first }.map(String.init) ?? "?"
        configuredColor = mode.indicatorColor
        escapeReturnsToMain = mode.bindings.values.contains {
            $0.descriptionWithKeyNotation == "esc" && $0.commands.last?.args.description == "mode main"
        }
    }

    func color(dark: Bool, increasedContrast: Bool) -> NSColor {
        let base: NSColor
        if let hex = configuredColor, let value = UInt32(hex.dropFirst(), radix: 16) {
            base = NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        } else { base = .controlAccentColor }
        let rgb = base.usingColorSpace(.sRGB) ?? base
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func luminance(_ c: NSColor) -> CGFloat {
            0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
        }
        let background: CGFloat = dark ? 0.015 : 0.9
        let target: CGFloat = increasedContrast ? 7 : 4.5
        var candidate = rgb
        for step in 0...20 {
            let l = luminance(candidate)
            if (max(l, background) + 0.05) / (min(l, background) + 0.05) >= target { return candidate }
            let fraction = CGFloat(step + 1) / 21
            let target: CGFloat = dark ? 1 : 0
            candidate = NSColor(srgbRed: rgb.redComponent * (1 - fraction) + target * fraction,
                                green: rgb.greenComponent * (1 - fraction) + target * fraction,
                                blue: rgb.blueComponent * (1 - fraction) + target * fraction, alpha: 1)
        }
        return candidate
    }
}

@MainActor
func updateModePresentation() {
    let presentation: ModePresentation?
    if TrayMenuModel.shared.isEnabled, !runtime.hotkeys.hotkeysSuspended,
       let name = activeMode, name != mainModeId, let mode = config.modes[name], mode.showIndicator {
        presentation = ModePresentation(name: name, mode: mode)
    } else { presentation = nil }
    TrayMenuModel.shared.setIfChanged(\.modePresentation, presentation)
    requestPublicStateUpdate()
}
