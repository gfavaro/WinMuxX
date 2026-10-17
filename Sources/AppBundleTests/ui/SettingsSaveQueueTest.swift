@testable import AppBundle
import Common
import XCTest

@MainActor
final class SettingsSaveQueueTest: WorkspaceTestCase {
    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false
        func wait() async {
            guard !released else { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func open() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }

    func testScalarRawAndShortcutSavesShareOneOrderedQueue() async throws {
        let gate = Gate()
        defer { gate.open() }
        let started = expectation(description: "first reload started")
        let completed = expectation(description: "all queued saves completed")
        var text = "config-version = 2\n"
        var events: [String] = []
        var reloadCount = 0
        let access = SettingsConfigAccess(edit: { transform in
            text = try transform(text)
            XCTAssertTrue(parseConfig(text).errors.isEmpty)
            events.append("write")
            return URL(filePath: "/unused-test-config")
        }, reload: { _ in
            reloadCount += 1
            events.append("reload\(reloadCount)")
            if reloadCount == 1 { started.fulfill(); await gate.wait() }
            config = parseConfig(text).config
            return true
        })
        let model = ShortcutSettingsModel(configAccess: access, drafts: SettingsDraftStore())
        persistSettingsConfig(section: nil, key: "start-at-login", renderedValue: "true", model: model) { events.append("scalar-complete") }
        // The raw editor uses this queue while retaining its own baseline/error UI.
        model.saveQueue.enqueue { events.append("raw") }
        model.persistBindings(["focus-left": "alt-h"])
        model.saveQueue.enqueue { completed.fulfill() }
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(events, ["write", "reload1"])
        XCTAssertEqual(model.savingSettingIDs, ["start-at-login"])
        gate.open()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(events, ["write", "reload1", "scalar-complete", "raw", "write", "reload2"])
        XCTAssertTrue(model.savingSettingIDs.isEmpty)
        XCTAssertEqual(model.assignments["focus-left"], "alt-h")
        XCTAssertEqual(model.bindingsDraftRevision, model.savedBindingsRevision)
    }

    func testReloadFailureRetainsDraftAndRetryDoesNotClearNewerEdit() async {
        let completed = expectation(description: "failed save completed")
        let retried = expectation(description: "retry completed")
        let drafts = SettingsDraftStore()
        drafts.set(12, for: "gaps.outer.left")
        var text = "config-version = 2\n"
        var reloadCount = 0
        let access = SettingsConfigAccess(edit: { transform in
            text = try transform(text)
            return URL(filePath: "/unused-test-config")
        }, reload: { _ in
            reloadCount += 1
            if reloadCount == 1 { return false }
            config = parseConfig(text).config
            return true
        })
        let model = ShortcutSettingsModel(configAccess: access, drafts: drafts)
        model.activeSettingTitle = "Left gap"
        persistSettingsConfig(section: "gaps.outer", key: "left", renderedValue: "12", model: model) { retried.fulfill() }
        model.saveQueue.enqueue { completed.fulfill() }
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.failedSettingID, "gaps.outer.left")
        XCTAssertEqual(model.failedSettingTitle, "Left gap")
        XCTAssertEqual(model.failedSaveRevision, 1)
        XCTAssertFalse(drafts.entries.isEmpty)
        drafts.set(18, for: "gaps.outer.left")
        model.retrySettingsSave?()
        await fulfillment(of: [retried], timeout: 1)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.retrySettingsSave)
        XCTAssertEqual(drafts.value(for: "gaps.outer.left", fallback: { 0 }), 18)
        XCTAssertEqual(parseConfig(text).config.gaps.outer.left, .constant(12))
    }

    func testFailureDoesNotBlockFollowingSaveOrLeakAcrossModels() async {
        let failed = expectation(description: "first model finished")
        let succeeded = expectation(description: "second model finished")
        let first = ShortcutSettingsModel(configAccess: .init(edit: { _ in
            throw SettingsDisplayError("Test write failure")
        }, reload: { _ in XCTFail("Failed writes must not reload"); return true }), drafts: SettingsDraftStore())
        let second = ShortcutSettingsModel(configAccess: .init(edit: { transform in
            _ = try transform("config-version = 2")
            return URL(filePath: "/unused-test-config")
        }, reload: { _ in true }), drafts: SettingsDraftStore())
        first.drafts.set("first", for: "test")
        second.drafts.set("second", for: "test")
        persistSettingsConfig(section: nil, key: "start-at-login", renderedValue: "true", model: first)
        first.saveQueue.enqueue { failed.fulfill() }
        persistSettingsConfig(section: nil, key: "start-at-login", renderedValue: "false", model: second) { succeeded.fulfill() }
        await fulfillment(of: [failed, succeeded], timeout: 1)
        XCTAssertNotNil(first.errorMessage)
        XCTAssertNil(second.errorMessage)
        XCTAssertEqual(first.drafts.value(for: "test", fallback: { "" }), "first")
        XCTAssertEqual(second.drafts.value(for: "test", fallback: { "" }), "second")
        let following = expectation(description: "following operation ran despite failure")
        first.enqueueSettingsSave(ids: ["later"], title: "Later", retry: {}) { following.fulfill() }
        await fulfillment(of: [following], timeout: 1)
        XCTAssertNil(first.errorMessage)
    }

    func testShortcutRetryUsesLatestAssignments() async {
        var attempts = 0
        var text = "config-version = 2\n"
        let firstFinished = expectation(description: "first attempt completed")
        let retryFinished = expectation(description: "retry completed")
        let model = ShortcutSettingsModel(configAccess: .init(edit: { transform in
            attempts += 1
            if attempts == 1 { throw SettingsDisplayError("Test failure") }
            text = try transform(text)
            return URL(filePath: "/unused-test-config")
        }, reload: { _ in config = parseConfig(text).config; return true }), drafts: SettingsDraftStore())
        model.persistBindings(["focus-left": "alt-h"])
        model.saveQueue.enqueue { firstFinished.fulfill() }
        await fulfillment(of: [firstFinished], timeout: 1)
        XCTAssertNotNil(model.retrySettingsSave)
        model.assignments = ["focus-right": "alt-l"]
        model.retrySettingsSave?()
        model.saveQueue.enqueue { retryFinished.fulfill() }
        await fulfillment(of: [retryFinished], timeout: 1)
        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(text.contains("focus right"))
        XCTAssertFalse(text.contains("focus left"))
        XCTAssertEqual(model.bindingsDraftRevision, model.savedBindingsRevision)
    }

    func testCommittedSaveSurvivesCancelledSubmitter() async {
        let saved = expectation(description: "committed save completed")
        var wrote = false
        let model = ShortcutSettingsModel(configAccess: .init(edit: { transform in
            XCTAssertFalse(Task.isCancelled)
            _ = try transform("config-version = 2")
            wrote = true
            return URL(filePath: "/unused-test-config")
        }, reload: { _ in try Task.checkCancellation(); return true }), drafts: SettingsDraftStore())
        let submitter = Task { @MainActor in
            XCTAssertTrue(Task.isCancelled)
            persistSettingsConfig(section: nil, key: "start-at-login", renderedValue: "true", model: model) { saved.fulfill() }
        }
        submitter.cancel()
        await fulfillment(of: [saved], timeout: 1)
        XCTAssertTrue(wrote)
        XCTAssertNil(model.errorMessage)
    }

    func testCompletedFailedSaveDoesNotRetainItsModelThroughRetry() async {
        let completed = expectation(description: "failed save drained")
        var model: ShortcutSettingsModel? = ShortcutSettingsModel(configAccess: .init(edit: { _ in
            throw SettingsDisplayError("Test failure")
        }, reload: { _ in true }), drafts: SettingsDraftStore())
        weak let observed = model
        persistSettingsConfig(section: nil, key: "start-at-login", renderedValue: "true", model: model!)
        model?.saveQueue.enqueue { completed.fulfill() }
        model = nil
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertNil(observed)
    }
}
