import Common
import CoreServices
import Foundation
import os

private let configWatcherLog = Logger(subsystem: winMuxAppId, category: "config")

/// Include both the link and its target; directories survive atomic file replacement.
struct ConfigWatchPaths: Equatable, Sendable {
    let files: Set<String>
    let directories: Set<String>

    init(url: URL) {
        let written = url.standardizedFileURL.path
        let resolved = Self.resolve(written)
        let parent = Self.resolve((written as NSString).deletingLastPathComponent)
        let link = (parent as NSString).appendingPathComponent((written as NSString).lastPathComponent)
        files = [written, resolved, link]
        directories = Set(files.map { ($0 as NSString).deletingLastPathComponent })
    }

    private static func resolve(_ path: String) -> String {
        if let pointer = realpath(path, nil) {
            defer { free(pointer) }
            return String(cString: pointer)
        }
        let parent = (path as NSString).deletingLastPathComponent
        guard parent != path, !parent.isEmpty else { return path }
        return (resolve(parent) as NSString).appendingPathComponent((path as NSString).lastPathComponent)
    }

    func matches(path: String, flags: FSEventStreamEventFlags) -> Bool {
        let dropped = kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
        let changed = kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved
            | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemModified
        return flags & UInt32(dropped) != 0 || files.contains(path) && flags & UInt32(changed) != 0
    }
}

final class ConfigFileWatcher {
    let paths: ConfigWatchPaths
    private let stream: FSEventStreamRef

    private final class Handler: Sendable {
        let paths: ConfigWatchPaths
        let onChange: @MainActor @Sendable () -> Void
        init(paths: ConfigWatchPaths, onChange: @escaping @MainActor @Sendable () -> Void) {
            self.paths = paths
            self.onChange = onChange
        }
    }

    @MainActor
    init?(url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        paths = ConfigWatchPaths(url: url)
        let handler = Unmanaged.passRetained(Handler(paths: paths, onChange: onChange))
        defer { handler.release() }
        var context = FSEventStreamContext(
            version: 0, info: handler.toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<Handler>.fromOpaque(pointer).retain()
                return UnsafeRawPointer(pointer)
            },
            release: { pointer in
                if let pointer { Unmanaged<Handler>.fromOpaque(pointer).release() }
            }, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, rawPaths, flags, _ in
            guard let info else { return }
            let handler = Unmanaged<Handler>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(rawPaths).takeUnretainedValue() as? [String] ?? []
            guard (0..<min(count, paths.count)).contains(where: {
                handler.paths.matches(path: paths[$0], flags: flags[$0])
            }) else { return }
            Task { @MainActor in handler.onChange() }
        }
        let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
        guard let stream = FSEventStreamCreate(nil, callback, &context, paths.directories.sorted() as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05,
                                               FSEventStreamCreateFlags(flags)) else { return nil }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
        self.stream = stream
    }

    deinit {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

/// A later save cancels only the debounce, never a reload already applying its config.
@MainActor
final class ConfigReloadScheduler {
    private let delay: Duration
    private let reload: @MainActor () async -> Void
    private var debounce: Task<Void, Never>?
    private var reloading = false
    private var pending = false
    private var waitingForStartup = false

    init(delay: Duration = .milliseconds(200), reload: @escaping @MainActor () async -> Void) {
        self.delay = delay
        self.reload = reload
    }

    func fileChanged(runtimeReady: Bool = true) {
        guard runtimeReady else { waitingForStartup = true; return }
        debounce?.cancel()
        debounce = Task { [weak self, delay] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self else { return }
            self.debounce = nil
            if self.reloading { self.pending = true; return }
            self.reloading = true
            repeat {
                self.pending = false
                await self.reload()
            } while self.pending
            self.reloading = false
        }
    }

    func startupFinished() {
        guard waitingForStartup else { return }
        waitingForStartup = false
        fileChanged()
    }

    func cancelPending() {
        waitingForStartup = false
        debounce?.cancel()
        debounce = nil
        pending = false
    }
}

@MainActor private var currentWatcher: ConfigFileWatcher?
@MainActor private let reloadScheduler = ConfigReloadScheduler { await reloadConfigAfterFileChange() }

@MainActor func syncConfigFileWatcher() {
    guard !isUnitTest else { return }
    guard config.autoReloadConfig else {
        currentWatcher = nil
        reloadScheduler.cancelPending()
        return
    }
    let url = preferredEditableConfigUrl()
    guard currentWatcher?.paths != ConfigWatchPaths(url: url) else { return }
    currentWatcher = ConfigFileWatcher(url: url) {
        guard config.autoReloadConfig else { return }
        reloadScheduler.fileChanged(runtimeReady: isWinMuxRuntimeReady)
    }
    if currentWatcher == nil { configWatcherLog.error("Could not observe the configuration directory") }
}

@MainActor func reloadConfigIfSavedDuringStartup() {
    if config.autoReloadConfig { reloadScheduler.startupFinished() }
}

@MainActor func reloadConfigAfterFileChange() async {
    guard config.autoReloadConfig else { return }
    guard isWinMuxRuntimeReady else { reloadScheduler.fileChanged(runtimeReady: false); return }
    let url = preferredEditableConfigUrl()
    // Force this path: a delete/rename must not select the shipped defaults.
    do {
        var output = ""
        if let token: RunSessionGuard = .isServerEnabled {
            _ = try await runLightSession(.configAutoReload, token, shouldSchedulePostRefresh: false) {
                try await reloadConfig(forceConfigUrl: url, automatic: true, stdout: &output)
            }
        } else {
            _ = try await reloadConfig(forceConfigUrl: url, automatic: true, stdout: &output)
        }
    } catch {
        lastConfigReloadError = error.localizedDescription
        configWatcherLog.error("Config reload failed: \(error.localizedDescription, privacy: .public)")
    }
}
