import AppKit
import Common
import Foundation

@MainActor
public final class ShortcutSettingsModel: ObservableObject {
    public static let shared = ShortcutSettingsModel()

    @Published var sections: [Section] = []
    @Published var assignments: [String: String] = [:] { didSet { conflictMessages = nil } }
    @Published var tapBindings: [Summary] = []
    @Published var customBindings: [Summary] = [] { didSet { conflictMessages = nil } }
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
    @Published var workspaceNumbers: [String] = []
    @Published var workspaceSwitchModifiers: NSEvent.ModifierFlags = defaultWorkspaceSwitchModifiers
    @Published var workspaceMoveModifiers: NSEvent.ModifierFlags = defaultWorkspaceMoveModifiers
    @Published var workspaceOverrides: [WorkspaceOverride] = []
    @Published public var openRequestId: Int = 0
    /// The settings pages exist only while their window is open; see ShortcutSettingsWindowContent.
    @Published var isWindowShown = false
    @Published var failedSaveRevision: Int = 0
    @Published var settingsRevision: Int = 0
    @Published var savingSettingIDs: Set<String> = []
    @Published var failedSettingID: String? = nil
    var retrySettingsSave: (() -> Void)?
    var configurationDraft: RawConfigDraft?
    @Published var failedSettingTitle: String? = nil
    var activeSettingTitle: String? = nil
    @Published var errorMessage: String? = nil

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
