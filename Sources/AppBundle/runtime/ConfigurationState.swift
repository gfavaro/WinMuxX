import Foundation

@MainActor
final class ConfigurationState {
    var value: Config
    var url: URL
    var isReady = false
    var lastReloadError: String?
    var lastAutomaticNotification: String?
    let reloadGate = ConfigReloadGate()
    var watcher: ConfigFileWatcher?
    var reloadScheduler: ConfigReloadScheduler?

    init(value: Config, url: URL) {
        self.value = value
        self.url = url
    }

    /// Publish the pair before any observer sees the new configuration.
    func publish(_ value: Config, from url: URL) {
        self.value = value
        self.url = url
    }
}
