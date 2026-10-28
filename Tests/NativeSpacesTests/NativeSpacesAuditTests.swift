import Foundation
import XCTest
@testable import NativeSpaces

private actor AuditSource {
    var active = "1"
    var snapshotReads = 0
    var topologyReads = 0
    var failTopology = false
    func setActive(_ value: String) { active = value }
    func setFailure(_ value: Bool) { failTopology = value }
    func counts() -> (Int, Int) { (snapshotReads, topologyReads) }
    func displays() -> [NativeSpaceDisplay] {
        [NativeSpaceDisplay(identifier: "display", activeSpaceID: active, spaces: [
            NativeSpace(id: "1", uuid: "one", type: 0), NativeSpace(id: "2", uuid: "two", type: 0),
        ])]
    }
    func topology() throws -> [NativeSpaceDisplay] {
        topologyReads += 1
        if failTopology { throw NativeSpacesError.unavailable("injected topology failure") }
        return displays()
    }
    func snapshot() -> NativeSpacesSnapshot {
        snapshotReads += 1
        return NativeSpacesSnapshot(displays: displays(), windows: [NativeWindowMembership(windowID: 10, spaceIDs: ["1"])],
            readMilliseconds: 0, capturedAt: .now)
    }
}

@MainActor
final class NativeSpacesAuditTests: XCTestCase {
    func testUnchangedAuditDoesNotEnumerateWindowsAndMissedSwitchIsReconciled() async {
        let source = AuditSource()
        let initial = expectation(description: "initial"), changed = expectation(description: "changed")
        let observer = NativeSpacesObservation(read: { _, _ in await source.snapshot() }, topology: { try await source.topology() })
        observer.onChange = { inventory, _ in
            guard let snapshot = inventory.currentSnapshot else { return }
            if snapshot.displays.first?.activeSpaceID == "1" { initial.fulfill() }
            else { changed.fulfill() }
        }
        observer.start()
        await fulfillment(of: [initial], timeout: 2)
        await observer.auditTopology()
        let idle = await source.counts()
        XCTAssertEqual(idle.0, 1)
        XCTAssertEqual(idle.1, 1)
        await source.setActive("2") // No system notification is delivered.
        await observer.auditTopology()
        await fulfillment(of: [changed], timeout: 2)
        let after = await source.counts()
        XCTAssertEqual(after.0, 2)
        XCTAssertEqual(observer.inventory.currentSnapshot?.eligibility(windowID: 10, on: "display"), .excluded(.inactiveSpace))
        observer.stop()
        await observer.auditTopology()
        let stopped = await source.counts()
        XCTAssertEqual(stopped.1, 2)
    }

    func testAuditFailuresSuspendAuthorityAndStopAutomaticRetryUntilRealEvent() async {
        let source = AuditSource()
        let initial = expectation(description: "initial"), refreshed = expectation(description: "manual recovery")
        var publications = 0
        let observer = NativeSpacesObservation(read: { _, _ in await source.snapshot() }, topology: { try await source.topology() })
        observer.onChange = { inventory, _ in
            if inventory.currentSnapshot != nil {
                publications += 1
                if publications == 1 { initial.fulfill() } else { refreshed.fulfill() }
            }
        }
        observer.start()
        await fulfillment(of: [initial], timeout: 2)
        await source.setFailure(true)
        for _ in 0..<4 { await observer.auditTopology() }
        XCTAssertNil(observer.inventory.currentSnapshot)
        let failed = await source.counts()
        XCTAssertEqual(failed.0, 1)
        XCTAssertEqual(failed.1, 3)
        observer.requestRead(event: "manual")
        await fulfillment(of: [refreshed], timeout: 2)
        await observer.auditTopology()
        let rearmed = await source.counts()
        XCTAssertEqual(rearmed.1, 4)
        observer.stop()
    }

    func testAuditSlowsOnlyWhenIdleAndWindowServerEventsCover() {
        let idle = NativeSpacesObservation(read: { _, _ in throw CancellationError() }, topology: nil, secondsSinceInput: { 60 })
        XCTAssertEqual(idle.nextAuditDelay(active: .milliseconds(500)), .milliseconds(500), "No events: keep polling")
        idle.windowEventsAvailable = true
        XCTAssertEqual(idle.nextAuditDelay(active: .milliseconds(500)), NativeSpacesObservation.idleAuditInterval)
        let busy = NativeSpacesObservation(read: { _, _ in throw CancellationError() }, topology: nil, secondsSinceInput: { 2 })
        busy.windowEventsAvailable = true
        XCTAssertEqual(busy.nextAuditDelay(active: .milliseconds(500)), .milliseconds(500))
    }
}
