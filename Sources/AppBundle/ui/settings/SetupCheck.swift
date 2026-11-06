import AppKit
import Common
import SwiftUI

/// One thing WinMuxX needs from macOS, and how to fix it when it is missing.
struct SetupCheckItem: Equatable, Identifiable {
    let id: String
    let title: String
    let ok: Bool
    let detail: String
    var fixURL: String? = nil
}

/// What the checks read, so tests can supply it.
struct SetupCheckInput {
    var accessibilityGranted: Bool
    var otherWindowManagers: [String]
    var workspaceSwipe: Bool
    var overviewThreeFingerUp: Bool
    /// macOS trackpad settings: 2 assigns the gesture to three fingers.
    var macThreeFingerHorizontalSwipe: Bool
    var macThreeFingerVerticalSwipe: Bool

    @MainActor static var current: Self {
        return Self(
            accessibilityGranted: AXIsProcessTrusted(),
            otherWindowManagers: runningOtherWindowManagers(),
            workspaceSwipe: config.workspaceSwipe.enabled,
            overviewThreeFingerUp: config.workspaceOverview.threeFingerUp,
            macThreeFingerHorizontalSwipe: macTrackpadGesture("TrackpadThreeFingerHorizSwipeGesture") == 2,
            macThreeFingerVerticalSwipe: macTrackpadGesture("TrackpadThreeFingerVertSwipeGesture") == 2,
        )
    }
}

private let accessibilitySettings = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
private let trackpadSettings = "x-apple.systempreferences:com.apple.Trackpad-Settings.extension"

func setupCheckItems(_ input: SetupCheckInput) -> [SetupCheckItem] {
    var items = [
        SetupCheckItem(id: "accessibility", title: "Accessibility permission", ok: input.accessibilityGranted,
                       detail: input.accessibilityGranted ? "Granted." : "WinMuxX cannot move or resize windows without it. Turn on WinMuxX in Privacy & Security › Accessibility.",
                       fixURL: input.accessibilityGranted ? nil : accessibilitySettings),
        SetupCheckItem(id: "other-window-managers", title: "No other window manager", ok: input.otherWindowManagers.isEmpty,
                       detail: input.otherWindowManagers.isEmpty ? "None running." : "\(input.otherWindowManagers.joined(separator: ", ")) also moves windows; quit it so the two do not fight."),
    ]
    // The swipes are macOS's own: they need the matching gesture on three fingers.
    if input.workspaceSwipe {
        items.append(SetupCheckItem(id: "three-finger-swipe", title: "Three-finger swipe", ok: input.macThreeFingerHorizontalSwipe,
            detail: input.macThreeFingerHorizontalSwipe
                ? "WinMuxX switches workspaces with macOS's own three-finger swipe recognition."
                : "Set Trackpad › More Gestures › Swipe between full-screen applications to three fingers; WinMuxX switches workspaces with that swipe.",
            fixURL: input.macThreeFingerHorizontalSwipe ? nil : trackpadSettings))
    }
    if input.overviewThreeFingerUp {
        items.append(SetupCheckItem(id: "three-finger-up", title: "Three-finger swipe up", ok: input.macThreeFingerVerticalSwipe,
            detail: input.macThreeFingerVerticalSwipe
                ? "Three fingers up opens the overview with macOS's own recognition, in place of Mission Control. Mission Control stays on its keyboard shortcut."
                : "Set Trackpad › More Gestures › Mission Control to three fingers; the swipe then opens the overview instead.",
            fixURL: input.macThreeFingerVerticalSwipe ? nil : trackpadSettings))
    }
    return items
}

/// Opens Settings › General once when something needs attention.
@MainActor func showSetupCheckIfNeeded() {
    guard !isUnitTest else { return }
    let key = "setupCheck.shown.virtual"
    guard !UserDefaults.standard.bool(forKey: key), setupCheckItems(.current).contains(where: { !$0.ok }) else { return }
    UserDefaults.standard.set(true, forKey: key)
    UserDefaults.standard.set(SettingsSidebarItem.general.rawValue, forKey: "settings.selectedPage")
    ShortcutSettingsModel.shared.requestWindowOpen()
}

struct SetupCheckView: View {
    @State private var items: [SetupCheckItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(item.ok ? .green : .orange)
                        .accessibilityLabel(item.ok ? "OK" : "Needs attention")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                        Text(item.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if let fix = item.fixURL.flatMap(URL.init(string:)) {
                        Button("Open Settings") { NSWorkspace.shared.open(fix) }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Check Again") { items = setupCheckItems(.current) }
            }
        }
        .onAppear { items = setupCheckItems(.current) }
    }
}
