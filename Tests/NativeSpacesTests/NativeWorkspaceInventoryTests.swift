import Foundation
import XCTest
@testable import NativeSpaces

final class NativeWorkspaceInventoryTests: XCTestCase {
    private func snapshot(id: String = "4", uuid: String? = "desktop-a") -> NativeSpacesSnapshot {
        NativeSpacesSnapshot(displays: [NativeSpaceDisplay(identifier: "display-a", activeSpaceID: id,
            spaces: [NativeSpace(id: id, uuid: uuid, type: 0)])], windows: [],
            readMilliseconds: 0, capturedAt: .now)
    }

    func testInvalidationRevokesCurrentObservationBeforeReadCompletes() {
        var inventory = NativeWorkspaceInventory()
        let first = inventory.invalidate()
        XCTAssertTrue(inventory.publish(snapshot(), for: first))
        XCTAssertNotNil(inventory.currentSnapshot)
        let next = inventory.invalidate()
        XCTAssertNil(inventory.currentSnapshot)
        XCTAssertEqual(inventory.records.count, 1)
        inventory.fail("read unavailable", for: next)
        XCTAssertNil(inventory.currentSnapshot)
        XCTAssertEqual(inventory.status, .unavailable("read unavailable"))
    }

    func testOldCompletionCannotPublishFailOrReviveStoppedInventory() {
        var inventory = NativeWorkspaceInventory()
        let old = inventory.invalidate()
        let current = inventory.invalidate()
        XCTAssertFalse(inventory.publish(snapshot(id: "1"), for: old))
        inventory.fail("old failure", for: old)
        XCTAssertTrue(inventory.publish(snapshot(id: "2"), for: current))
        XCTAssertEqual(inventory.records.first?.space.id, "2")
        inventory.stop()
        XCTAssertFalse(inventory.publish(snapshot(), for: current))
        XCTAssertNil(inventory.currentSnapshot)
        XCTAssertEqual(inventory.status, .stopped)
    }

    func testTokensCannotBeUsedByAnotherRuntime() {
        var first = NativeWorkspaceInventory()
        var second = NativeWorkspaceInventory()
        let token = first.invalidate()
        second.invalidate()
        XCTAssertFalse(second.publish(snapshot(), for: token))
    }

    func testRecoveryIdentitySurvivesNumericIDChangeAndIsAbsentWithoutUUID() {
        var inventory = NativeWorkspaceInventory()
        XCTAssertTrue(inventory.publish(snapshot(), for: inventory.invalidate()))
        let identity = inventory.records.first?.persistenceKey
        XCTAssertEqual(identity, "native:desktop-a")
        XCTAssertTrue(inventory.publish(snapshot(id: "5088"), for: inventory.invalidate()))
        XCTAssertEqual(inventory.records.first?.persistenceKey, identity)
        XCTAssertTrue(inventory.publish(snapshot(uuid: nil), for: inventory.invalidate()))
        XCTAssertNil(inventory.records.first?.persistenceKey)
    }

    func testDuplicateUUIDDoesNotPublishAmbiguousRecoveryIdentity() {
        var inventory = NativeWorkspaceInventory()
        let invalid = NativeSpacesSnapshot(displays: [
            NativeSpaceDisplay(identifier: "display-a", activeSpaceID: "1", spaces: [
                NativeSpace(id: "1", uuid: "same", type: 0),
                NativeSpace(id: "2", uuid: "same", type: 0),
            ]),
        ], windows: [], readMilliseconds: 0, capturedAt: .now)
        XCTAssertFalse(inventory.publish(invalid, for: inventory.invalidate()))
        XCTAssertNil(inventory.currentSnapshot)
        XCTAssertTrue(inventory.records.isEmpty)
    }

    func testSharedDesktopIsObservedWithoutInventingIndependentLayoutOwners() {
        var inventory = NativeWorkspaceInventory()
        let shared = NativeSpace(id: "1", uuid: "shared", type: 0)
        let value = NativeSpacesSnapshot(displays: [
            NativeSpaceDisplay(identifier: "a", activeSpaceID: "1", spaces: [shared]),
            NativeSpaceDisplay(identifier: "b", activeSpaceID: "1", spaces: [shared]),
        ], windows: [], readMilliseconds: 0, capturedAt: .now)
        XCTAssertTrue(inventory.publish(value, for: inventory.invalidate()))
        XCTAssertNotNil(inventory.currentSnapshot)
        XCTAssertTrue(inventory.records.isEmpty)
    }
}
