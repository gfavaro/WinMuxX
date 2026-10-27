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
    var backend: WorkspaceBackendKind
    var accessibilityGranted: Bool
    var otherWindowManagers: [String]
    /// macOS "Displays have separate Spaces" (`spans-displays` off).
    var separateSpaces: Bool
    /// macOS "Automatically rearrange Spaces based on most recent use".
    var rearrangesSpaces: Bool
    var workspaceSwipe: Bool
    var overviewThreeFingerUp: Bool
    /// macOS trackpad settings: 2 assigns the gesture to three fingers.
    var macThreeFingerHorizontalSwipe: Bool
    var macThreeFingerVerticalSwipe: Bool

    @MainActor static var current: Self {
        func trackpad(_ key: String) -> Int {
            ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]
                .compactMap { CFPreferencesCopyAppValue(key as CFString, $0 as CFString) as? Int }.max() ?? 0
        }
        return Self(
            backend: runtime.workspaceBackend.kind,
            accessibilityGranted: AXIsProcessTrusted(),
            otherWindowManagers: runningOtherWindowManagers(),
            separateSpaces: !(CFPreferencesCopyAppValue("spans-displays" as CFString, "com.apple.spaces" as CFString) as? Bool ?? false),
            rearrangesSpaces: CFPreferencesCopyAppValue("mru-spaces" as CFString, "com.apple.dock" as CFString) as? Bool ?? true,
            workspaceSwipe: config.workspaceSwipe.enabled,
            overviewThreeFingerUp: config.workspaceOverview.threeFingerUp,
            macThreeFingerHorizontalSwipe: trackpad("TrackpadThreeFingerHorizSwipeGesture") == 2,
            macThreeFingerVerticalSwipe: trackpad("TrackpadThreeFingerVertSwipeGesture") == 2,
        )
    }
}

private let accessibilitySettings = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
private let desktopSettings = "x-apple.systempreferences:com.apple.Desktop-Settings.extension"
private let trackpadSettings = "x-apple.systempreferences:com.apple.Trackpad-Settings.extension"

func setupCheckItems(_ input: SetupCheckInput) -> [SetupCheckItem] {
    var items = [
        SetupCheckItem(id: "accessibility", title: "Accessibility permission", ok: input.accessibilityGranted,
                       detail: input.accessibilityGranted ? "Granted." : "WinMuxX cannot move or resize windows without it. Turn on WinMuxX in Privacy & Security › Accessibility.",
                       fixURL: input.accessibilityGranted ? nil : accessibilitySettings),
        SetupCheckItem(id: "other-window-managers", title: "No other window manager", ok: input.otherWindowManagers.isEmpty,
                       detail: input.otherWindowManagers.isEmpty ? "None running." : "\(input.otherWindowManagers.joined(separator: ", ")) also moves windows; quit it so the two do not fight."),
    ]
    switch input.backend {
        case .native:
            items.append(SetupCheckItem(id: "separate-spaces", title: "Displays have separate Spaces", ok: input.separateSpaces,
                detail: input.separateSpaces ? "On." : "Native tiling lays out each display's own desktop. Turn on Displays have separate Spaces in Desktop & Dock, then log out and back in.",
                fixURL: input.separateSpaces ? nil : desktopSettings))
            items.append(SetupCheckItem(id: "rearrange-spaces", title: "Desktops keep their order", ok: !input.rearrangesSpaces,
                detail: input.rearrangesSpaces ? "macOS reorders desktops by recent use, so desktop numbers and shortcuts change. Turn off Automatically rearrange Spaces based on most recent use in Desktop & Dock." : "Off.",
                fixURL: input.rearrangesSpaces ? desktopSettings : nil))
        case .virtual:
            let swipeClash = input.workspaceSwipe && input.macThreeFingerHorizontalSwipe
            items.append(SetupCheckItem(id: "three-finger-swipe", title: "Three-finger swipe is free", ok: !swipeClash,
                detail: swipeClash ? "macOS also swipes between full-screen apps with three fingers. Set Trackpad › More Gestures › Swipe between full-screen applications to four fingers." : "No clash.",
                fixURL: swipeClash ? trackpadSettings : nil))
            let overviewClash = input.overviewThreeFingerUp && input.macThreeFingerVerticalSwipe
            if input.overviewThreeFingerUp {
                items.append(SetupCheckItem(id: "three-finger-up", title: "Three-finger swipe up is free", ok: !overviewClash,
                    detail: overviewClash ? "macOS also opens Mission Control with three fingers up. Set Trackpad › More Gestures › Mission Control to four fingers." : "No clash.",
                    fixURL: overviewClash ? trackpadSettings : nil))
            }
    }
    return items
}

/// Opens Settings › General once per backend when something needs attention.
@MainActor func showSetupCheckIfNeeded() {
    guard !isUnitTest else { return }
    let key = "setupCheck.shown.\(runtime.workspaceBackend.kind.rawValue)"
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
