import Foundation
import XCTest
@testable import NativeSpaces

private actor SuspendedReads {
    var requests: [CheckedContinuation<NativeSpacesSnapshot, Error>] = []
    let started: @Sendable (Int) -> Void

    init(started: @escaping @Sendable (Int) -> Void) { self.started = started }

    func read() async throws -> NativeSpacesSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            requests.append(continuation)
            started(requests.count)
        }
    }

    func finish(_ index: Int, id: String) {
        requests[index].resume(returning: NativeSpacesSnapshot(displays: [
            NativeSpaceDisplay(identifier: "display", activeSpaceID: id,
                spaces: [NativeSpace(id: id, uuid: "desktop-\(id)", type: 0)]),
        ], windows: [], readMilliseconds: 0, capturedAt: .now))
    }
}

@MainActor
final class NativeSpacesObservationTests: XCTestCase {
    func testSpaceEventCannotDiscardInFlightWindowReconciliationOnAnotherDisplay() async {
        let first = expectation(description: "first read"), window = expectation(description: "window read")
        let replacement = expectation(description: "replacement read"), initial = expectation(description: "initial published")
        let final = expectation(description: "replacement published")
        let reads = SuspendedReads { index in
            if index == 1 { first.fulfill() }
            else if index == 2 { window.fulfill() }
            else if index == 3 { replacement.fulfill() }
            else { XCTFail("Unexpected extra read") }
        }
        let observation = NativeSpacesObservation(read: { _, allCurrent in
            XCTAssertTrue(allCurrent, "A Space event must retain a superseded window refresh's wider scope")
            return try await reads.read()
        }, topology: nil)
        observation.onChange = { inventory, _ in
            if let snapshot = inventory.currentSnapshot {
                if snapshot.displays.first?.activeSpaceID == "1" { initial.fulfill() }
                else { final.fulfill() }
            }
        }
        observation.start()
        await fulfillment(of: [first], timeout: 2)
        await reads.finish(0, id: "1")
        await fulfillment(of: [initial], timeout: 2)
        observation.requestRead(event: "windowServerWindowChange")
        await fulfillment(of: [window], timeout: 2)
        observation.requestRead(event: "activeSpaceDidChange")
        await reads.finish(1, id: "2")
        await fulfillment(of: [replacement], timeout: 2)
        await reads.finish(2, id: "2")
        await fulfillment(of: [final], timeout: 2)
        observation.stop()
    }

    func testEventBurstUsesOnePendingReadAndDiscardsOldCompletion() async {
        let first = expectation(description: "first read")
        let second = expectation(description: "one replacement read")
        let published = expectation(description: "latest observation published")
        let reads = SuspendedReads { index in
            switch index {
                case 1: first.fulfill()
                case 2: second.fulfill()
                default: XCTFail("Unbounded read queue")
            }
        }
        let observation = NativeSpacesObservation { try await reads.read() }
        observation.onChange = { inventory, _ in
            if let snapshot = inventory.currentSnapshot {
                XCTAssertEqual(snapshot.displays.first?.activeSpaceID, "2")
                published.fulfill()
            }
        }
        observation.start()
        await fulfillment(of: [first], timeout: 2)
        for _ in 0..<100 { observation.requestRead(event: "Space changed") }
        XCTAssertNil(observation.inventory.currentSnapshot)
        await reads.finish(0, id: "1")
        await fulfillment(of: [second], timeout: 2)
        XCTAssertNil(observation.inventory.currentSnapshot)
        await reads.finish(1, id: "2")
        await fulfillment(of: [published], timeout: 2)
        observation.stop()
    }

    func testStopRevokesInFlightReadAndRestartDoesNotOverlapIt() async {
        let first = expectation(description: "first read")
        let second = expectation(description: "read after restart")
        let published = expectation(description: "restart published")
        let reads = SuspendedReads { index in
            if index == 1 { first.fulfill() }
            else if index == 2 { second.fulfill() }
            else { XCTFail("Unexpected read") }
        }
        let observation = NativeSpacesObservation { try await reads.read() }
        observation.onChange = { inventory, _ in
            if let snapshot = inventory.currentSnapshot {
                XCTAssertEqual(snapshot.displays.first?.activeSpaceID, "2")
                published.fulfill()
            }
        }
        observation.start()
        await fulfillment(of: [first], timeout: 2)
        observation.stop()
        observation.start()
        await reads.finish(0, id: "1")
        await fulfillment(of: [second], timeout: 2)
        await reads.finish(1, id: "2")
        await fulfillment(of: [published], timeout: 2)
        observation.stop()
        XCTAssertNil(observation.inventory.currentSnapshot)
    }
}
