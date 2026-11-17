import AppBundle
import SwiftUI

// This file is shared between SPM and xcode project

@main
struct WinMuxApp: App {
    @NSApplicationDelegateAdaptor(WinMuxApplicationDelegate.self) var applicationDelegate
    @State var viewModel = TrayMenuModel.shared
    @State var messageModel = MessageModel.shared
    @State var shortcutSettingsModel = ShortcutSettingsModel.shared
    @Environment(\.openWindow) var openWindow: OpenWindowAction

    init() {
        initAppBundle()
        // Fork builds intentionally have no updater until a separately signed feed exists.
        installNativeMenuBar()
    }

    var body: some Scene {
        getShortcutSettingsWindow(model: shortcutSettingsModel)
            .onChange(of: shortcutSettingsModel.openRequestId) {
                openShortcutSettingsWindow(openWindow)
            }
        getMessageWindow(messageModel: messageModel)
            .onChange(of: messageModel.message) { _, message in
                if message != nil {
                    openWindow(id: messageWindowId)
                }
            }
    }
}
