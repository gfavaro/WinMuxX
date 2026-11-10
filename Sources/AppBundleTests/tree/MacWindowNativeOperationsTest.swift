@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class MacWindowNativeOperationsTest: WorkspaceTestCase {
    private let id: UInt32 = 424242
    private var app: ScriptedWindowApplication!

    override func setUp() async throws {
        try await super.setUp()
        app = ScriptedWindowApplication()
        runtime.windowServer = WindowServerQueries(exists: { _ in true }, frame: { _ in nil })
        TrayMenuModel.shared.isEnabled = true
        config.onWindowDetected = []
    }

    override func tearDown() async throws {
        for window in MacWindow.allWindows { window.garbageCollect(skipClosedWindowsCache: true) }
        app = nil
        try await super.tearDown()
    }

    private func register() async throws -> MacWindow {
        let window = try await MacWindow.getOrRegister(windowId: id, macApp: app)
        return try XCTUnwrap(window)
    }

    func testRegistrationKeepsOneLiveNodeAndDoesNotRereadKnownWindow() async throws {
        let window = try await register()
        XCTAssertTrue(window.app === app)
        XCTAssertTrue(window.nodeWorkspace === focus.workspace)
        XCTAssertEqual(window.lastKnownActualRect, app.rect)
        let reads = app.reads
        let same = try await register()
        XCTAssertTrue(same === window)
        XCTAssertEqual(app.reads, reads)
        XCTAssertTrue(focus.workspace.allLeafWindowsRecursive.contains { $0 === window })
    }

    func testCloseCommandCanQuitTheAppAndRemoveItsRealWindow() async throws {
        let window = try await register()
        let command = CloseCommand(args: CloseCmdArgs(rawArgs: []).copy(\.windowId, id).copy(\.quitIfLastWindow, true))
        let closed = try await command.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(closed.exitCode, 0)
        XCTAssertTrue(app.isTerminated)
        XCTAssertNil(MacWindow.allWindowsMap[id])
        XCTAssertNil(window.parent)
        XCTAssertFalse(Workspace.all.flatMap { $0.allLeafWindowsRecursive }.contains { $0 === window })
    }

    func testMissingNativeWindowIsNotRegistered() async throws {
        runtime.windowServer = .empty
        let result = try await MacWindow.getOrRegister(windowId: id, macApp: app)
        XCTAssertNil(result)
        XCTAssertEqual(app.reads, 0)
        XCTAssertNil(MacWindow.allWindowsMap[id])
    }

    func testUnansweredRegistrationCanRetryWithoutLeavingANode() async throws {
        app.readFailure = .cannotComplete
        do {
            _ = try await register()
            XCTFail("An unanswered read registered a window")
        } catch let failure as AXReadFailure {
            XCTAssertEqual(failure.code, .cannotComplete)
        }
        XCTAssertNil(MacWindow.allWindowsMap[id])
        app.readFailure = nil
        let window = try await register()
        XCTAssertTrue(MacWindow.allWindowsMap[id] === window)
    }

    func testParkingConfirmsNativeGeometryAndAvoidsRedundantWrites() async throws {
        let window = try await register()
        try await window.hideInCorner(.bottomRightCorner)
        XCTAssertTrue(window.isHiddenInCorner)
        XCTAssertTrue(window.hasCompletedNativeParking)
        XCTAssertEqual(app.writes.count, 1)
        let parked = CGRect(origin: app.rect.topLeftCorner, size: app.rect.size)
        runtime.windowServer = WindowServerQueries(exists: { _ in true }, frame: { _ in parked })
        XCTAssertTrue(window.hasConfirmedNativeParkingPosition())
        try await window.hideInCorner(.bottomRightCorner)
        XCTAssertEqual(app.writes.count, 1)
    }

    func testUnansweredParkingDoesNotRecordCompletionAndRetries() async throws {
        let window = try await register()
        app.writeFailure = .cannotComplete
        do {
            try await window.hideInCorner(.bottomRightCorner)
            XCTFail("An unanswered write completed parking")
        } catch let failure as AXReadFailure {
            XCTAssertEqual(failure.code, .cannotComplete)
        }
        XCTAssertFalse(window.hasCompletedNativeParking)
        app.writeFailure = nil
        try await window.hideInCorner(.bottomRightCorner)
        XCTAssertTrue(window.hasCompletedNativeParking)
    }

    func testParkingWithoutAnElementDoesNotRecordCompletion() async throws {
        let window = try await register()
        app.beforeWrite = { [app = app!] in app.hasElement = false }
        try await window.hideInCorner(.bottomRightCorner)
        XCTAssertFalse(window.hasCompletedNativeParking)
        XCTAssertTrue(app.writes.isEmpty)
        app.beforeWrite = nil
        app.hasElement = true
        try await window.hideInCorner(.bottomRightCorner)
        XCTAssertTrue(window.hasCompletedNativeParking)
    }

    func testRevealRequiresReadbackAndCanRetryAfterAnIgnoredWrite() async throws {
        let window = try await register()
        let target = CGRect(x: 100, y: 100, width: 400, height: 300)
        try await window.hideInCorner(.bottomRightCorner)
        app.acceptsWrites = false
        let ignored = try await window.restoreFromCorner(to: target)
        XCTAssertFalse(ignored)
        XCTAssertTrue(window.isHiddenInCorner)
        app.acceptsWrites = true
        let restored = try await window.restoreFromCorner(to: target)
        XCTAssertTrue(restored)
        XCTAssertFalse(window.isHiddenInCorner)
        XCTAssertEqual(app.rect.topLeftCorner, target.origin)
        XCTAssertEqual(app.writes.last?.positionFirst, true)
    }

    func testUnansweredRevealReadbackStaysPendingUntilRetry() async throws {
        let window = try await register()
        try await window.hideInCorner(.bottomRightCorner)
        app.readFailure = .cannotComplete
        do {
            _ = try await window.restoreFromCorner(to: CGRect(x: 100, y: 100, width: 400, height: 300))
            XCTFail("An unanswered readback completed reveal")
        } catch let failure as AXReadFailure {
            XCTAssertEqual(failure.code, .cannotComplete)
        }
        XCTAssertTrue(window.isHiddenInCorner)
        app.readFailure = nil
        let restored = try await window.restoreFromCorner(to: CGRect(x: 100, y: 100, width: 400, height: 300))
        XCTAssertTrue(restored)
    }
}
