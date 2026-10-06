@testable import AppBundle
import Common
import CoreServices
import XCTest

@MainActor
final class ConfigFileWatcherTest: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "WinMuxWatcher-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testContentEventsMatchOnlyConfigAndDroppedEventsForceRescan() {
        let paths = ConfigWatchPaths(url: URL(filePath: "/tmp/winmux-watcher/config.toml"))
        for flag in [kFSEventStreamEventFlagItemCreated, kFSEventStreamEventFlagItemRemoved,
                     kFSEventStreamEventFlagItemRenamed, kFSEventStreamEventFlagItemModified] {
            XCTAssertTrue(paths.matches(path: "/tmp/winmux-watcher/config.toml", flags: UInt32(flag)))
            XCTAssertFalse(paths.matches(path: "/tmp/winmux-watcher/other.toml", flags: UInt32(flag)))
        }
        XCTAssertFalse(paths.matches(path: "/tmp/winmux-watcher/config.toml", flags: UInt32(kFSEventStreamEventFlagItemInodeMetaMod)))
        XCTAssertTrue(paths.matches(path: "/unrelated", flags: UInt32(kFSEventStreamEventFlagMustScanSubDirs)))
    }

    func testRealWatcherSeesCreationAtomicSaveAndRecreation() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "config.toml")
        var expected = "created"
        var observed = expectation(description: "created")
        let watcher = try XCTUnwrap(ConfigFileWatcher(url: file) {
            if (try? String(contentsOf: file, encoding: .utf8)) == expected { observed.fulfill() }
        })
        observed.assertForOverFulfill = false
        try expected.write(to: file, atomically: false, encoding: .utf8)
        await fulfillment(of: [observed], timeout: 3)
        expected = "atomic"
        observed = expectation(description: "atomic replacement")
        observed.assertForOverFulfill = false
        try expected.write(to: file, atomically: true, encoding: .utf8)
        await fulfillment(of: [observed], timeout: 3)
        try FileManager.default.removeItem(at: file)
        expected = "recreated"
        observed = expectation(description: "recreated")
        observed.assertForOverFulfill = false
        try expected.write(to: file, atomically: false, encoding: .utf8)
        await fulfillment(of: [observed], timeout: 3)
        withExtendedLifetime(watcher) {}
    }

    func testRealWatcherObservesSymlinkTargetInAnotherDirectory() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let targetDir = dir.appending(path: "target")
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let target = targetDir.appending(path: "config.toml")
        try "before".write(to: target, atomically: true, encoding: .utf8)
        let link = dir.appending(path: "linked.toml")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let observed = expectation(description: "target changed")
        observed.assertForOverFulfill = false
        let watcher = try XCTUnwrap(ConfigFileWatcher(url: link) {
            if (try? String(contentsOf: link, encoding: .utf8)) == "after" { observed.fulfill() }
        })
        try "after".write(to: target, atomically: true, encoding: .utf8)
        await fulfillment(of: [observed], timeout: 3)
        withExtendedLifetime(watcher) {}
    }

    func testSchedulerCoalescesSavesDuringReloadWithoutCancelingIt() async throws {
        var count = 0
        var release: CheckedContinuation<Void, Never>?
        let started = expectation(description: "first reload")
        let finished = expectation(description: "follow-up reload")
        let scheduler = ConfigReloadScheduler(delay: .milliseconds(10)) {
            count += 1
            if count == 1 {
                await withCheckedContinuation { release = $0; started.fulfill() }
                XCTAssertFalse(Task.isCancelled)
            } else { finished.fulfill() }
        }
        scheduler.fileChanged()
        scheduler.fileChanged()
        await fulfillment(of: [started], timeout: 1)
        scheduler.fileChanged()
        scheduler.fileChanged()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(count, 1)
        release?.resume()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(count, 2)
        scheduler.cancelPending()
    }

    func testStartupSavesWaitAndBecomeOneReloadAfterStartup() async throws {
        var count = 0
        let reloaded = expectation(description: "startup reload")
        let scheduler = ConfigReloadScheduler(delay: .milliseconds(10)) {
            count += 1
            reloaded.fulfill()
        }
        scheduler.fileChanged(runtimeReady: false)
        scheduler.fileChanged(runtimeReady: false)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(count, 0)
        scheduler.startupFinished()
        await fulfillment(of: [reloaded], timeout: 1)
        XCTAssertEqual(count, 1)
        scheduler.cancelPending()
    }

    func testCancelPendingDoesNotCancelActiveReload() async throws {
        let started = expectation(description: "active")
        let finished = expectation(description: "finished")
        var release: CheckedContinuation<Void, Never>?
        var count = 0
        let scheduler = ConfigReloadScheduler(delay: .milliseconds(10)) {
            count += 1
            await withCheckedContinuation { release = $0; started.fulfill() }
            XCTAssertFalse(Task.isCancelled)
            finished.fulfill()
        }
        scheduler.fileChanged()
        await fulfillment(of: [started], timeout: 1)
        scheduler.fileChanged()
        scheduler.cancelPending()
        release?.resume()
        await fulfillment(of: [finished], timeout: 1)
        XCTAssertEqual(count, 1)
    }

    func testAutomaticErrorsAreDeduplicatedButManualReloadStillNotifies() async throws {
        setUpWorkspacesForTests()
        let savedConfig = config
        let savedUrl = configUrl
        let savedMessage = MessageModel.shared.message
        let savedError = lastConfigReloadError
        defer {
            config = savedConfig; configUrl = savedUrl
            MessageModel.shared.message = savedMessage; lastConfigReloadError = savedError
        }
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "config.toml")
        try "invalid = [".write(to: file, atomically: true, encoding: .utf8)
        var output = ""
        _ = try await reloadConfig(forceConfigUrl: file, automatic: true, stdout: &output)
        XCTAssertNotNil(MessageModel.shared.message)
        MessageModel.shared.message = nil
        _ = try await reloadConfig(forceConfigUrl: file, automatic: true, stdout: &output)
        XCTAssertNil(MessageModel.shared.message)
        _ = try await reloadConfig(forceConfigUrl: file, stdout: &output)
        XCTAssertNotNil(MessageModel.shared.message)
        var args = ReloadConfigCmdArgs(rawArgs: [])
        args.noGui = true
        try "config-version = 2\nauto-reload-config = true\n[mode.main.binding]\n".write(to: file, atomically: true, encoding: .utf8)
        _ = try await reloadConfig(args: args, forceConfigUrl: file, stdout: &output)
        XCTAssertNil(MessageModel.shared.message)
        try "invalid = [".write(to: file, atomically: true, encoding: .utf8)
        _ = try await reloadConfig(forceConfigUrl: file, automatic: true, stdout: &output)
        XCTAssertNotNil(MessageModel.shared.message)
    }

    func testReloadPreservesExistingModeAndHandlesRemovedModeWithRecursiveCallback() async throws {
        setUpWorkspacesForTests()
        let savedConfig = config
        let savedUrl = configUrl
        let savedMode = activeMode
        let savedEnabled = TrayMenuModel.shared.isEnabled
        defer {
            setUpWorkspacesForTests()
            config = savedConfig; configUrl = savedUrl; activeMode = savedMode
            TrayMenuModel.shared.isEnabled = savedEnabled
        }
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "config.toml")
        try """
        config-version = 2
        on-mode-changed = ['reload-config --no-gui']
        [mode.main.binding]
        [mode.custom.binding]
        """.write(to: file, atomically: true, encoding: .utf8)
        TrayMenuModel.shared.isEnabled = true
        var args = ReloadConfigCmdArgs(rawArgs: [])
        args.noGui = true
        for (previous, expected) in [("custom", "custom"), ("removed", "main")] {
            activeMode = previous
            var output = ""
            let loaded = try await reloadConfig(args: args, forceConfigUrl: file, stdout: &output)
            XCTAssertTrue(loaded, output)
            XCTAssertEqual(activeMode, expected)
        }
    }

    func testDisabledAutomaticReloadDoesNotApplyButManualReloadCanEnableIt() async throws {
        setUpWorkspacesForTests()
        let savedConfig = config
        let savedUrl = configUrl
        let savedMode = activeMode
        defer { config = savedConfig; configUrl = savedUrl; activeMode = savedMode }
        config.autoReloadConfig = false
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "config.toml")
        try "config-version = 2\nauto-reload-config = true\n[mode.main.binding]\n".write(to: file, atomically: true, encoding: .utf8)
        var args = ReloadConfigCmdArgs(rawArgs: [])
        args.noGui = true
        var output = ""
        let automatic = try await reloadConfig(args: args, forceConfigUrl: file, automatic: true, stdout: &output)
        XCTAssertFalse(automatic)
        XCTAssertFalse(config.autoReloadConfig)
        XCTAssertEqual(configUrl, savedUrl)
        let manual = try await reloadConfig(args: args, forceConfigUrl: file, stdout: &output)
        XCTAssertTrue(manual)
        XCTAssertTrue(config.autoReloadConfig)
        XCTAssertEqual(configUrl, file)
    }

    func testUnreadableSelectedFileDoesNotBecomeDefaults() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        assertFail(readConfig(forceConfigUrl: dir.appending(path: "missing.toml")))
        // A directory is reliably unreadable as text, including when tests run as root.
        assertFail(readConfig(forceConfigUrl: dir))
    }

    func testInvalidAndMissingReloadRetainStateThenCorrectionSucceeds() async throws {
        setUpWorkspacesForTests()
        let oldConfig = config
        let oldUrl = configUrl
        let oldMode = activeMode
        let oldEnabled = TrayMenuModel.shared.isEnabled
        let oldError = lastConfigReloadError
        defer {
            setUpWorkspacesForTests()
            config = oldConfig; configUrl = oldUrl; activeMode = oldMode
            TrayMenuModel.shared.isEnabled = oldEnabled; lastConfigReloadError = oldError
        }
        TrayMenuModel.shared.isEnabled = false
        activeMode = nil
        let workspace = focus.workspace
        let window = TestWindow.new(id: 90, parent: workspace.rootTilingContainer)
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "config.toml")
        var args = ReloadConfigCmdArgs(rawArgs: [])
        args.noGui = true
        for invalid in ["not valid = [", nil] as [String?] {
            if let invalid { try invalid.write(to: file, atomically: true, encoding: .utf8) }
            else { try FileManager.default.removeItem(at: file) }
            var output = ""
            let ok = try await reloadConfig(args: args, forceConfigUrl: file, automatic: true, stdout: &output)
            XCTAssertFalse(ok)
            XCTAssertNotNil(lastConfigReloadError)
            XCTAssertEqual(config.defaultRootContainerLayout, oldConfig.defaultRootContainerLayout)
            XCTAssertTrue(window.nodeWorkspace === workspace)
            XCTAssertNil(activeMode)
            XCTAssertFalse(TrayMenuModel.shared.isEnabled)
        }
        try "config-version = 2\nauto-reload-config = true\n[mode.main.binding]\n".write(to: file, atomically: true, encoding: .utf8)
        var output = ""
        let corrected = try await reloadConfig(args: args, forceConfigUrl: file, stdout: &output)
        XCTAssertTrue(corrected)
        XCTAssertNil(lastConfigReloadError)
        XCTAssertEqual(configUrl, file)
        XCTAssertNil(activeMode)
        XCTAssertFalse(TrayMenuModel.shared.isEnabled)
        XCTAssertTrue(window.nodeWorkspace === workspace)
    }
}
