import AppKit
import Observation
import Common
import Foundation

@MainActor
@Observable
public final class ShortcutSettingsModel {
    public static let shared = ShortcutSettingsModel()

    var sections: [Section] = []
    var assignments: [String: String] = [:] { didSet { conflictMessages = nil } }
    var tapBindings: [Summary] = []
    var customBindings: [Summary] = [] { didSet { conflictMessages = nil } }
    /// macOS's own shortcuts, read when Settings loads; never changed by WinMuxX.
    var systemShortcuts: [SystemShortcut] = isUnitTest ? [] : SystemShortcuts.current() { didSet { conflictMessages = nil } }
    private var conflictMessages: [String: String]?

    /// Why this action's shortcut clashes and which free keys would not, or nil.
    func shortcutConflict(for actionId: String) -> String? {
        if conflictMessages == nil {
            conflictMessages = shortcutConflictMessages(assignments: assignments, titles: actionsById.mapValues(\.title),
                customNotations: customBindings.map(\.notation), system: systemShortcuts)
        }
        return conflictMessages?[actionId]
    }
    var workspaceNumbers: [String] = []
    var workspaceSwitchModifiers: NSEvent.ModifierFlags = defaultWorkspaceSwitchModifiers
    var workspaceMoveModifiers: NSEvent.ModifierFlags = defaultWorkspaceMoveModifiers
    var workspaceOverrides: [WorkspaceOverride] = []
    public var openRequestId: Int = 0
    /// The settings pages exist only while their window is open; see ShortcutSettingsWindowContent.
    var isWindowShown = false
    var failedSaveRevision: Int = 0
    var settingsRevision: Int = 0
    var savingSettingIDs: Set<String> = []
    var failedSettingID: String? = nil
    var retrySettingsSave: (() -> Void)?
    var configurationDraft: RawConfigDraft?
    var failedSettingTitle: String? = nil
    var activeSettingTitle: String? = nil
    var errorMessage: String? = nil

    let saveQueue = SettingsSaveQueue()
    let configAccess: SettingsConfigAccess
    let drafts: SettingsDraftStore
    var bindingsDraftRevision = 0
    var savedBindingsRevision = 0

    var actionsById: [String: Action] = [:]
    var actionIdByCommand: [String: String] = [:]

    init(configAccess: SettingsConfigAccess = .native, drafts: SettingsDraftStore = .shared) {
        self.configAccess = configAccess
        self.drafts = drafts
        reload()
    }
}
