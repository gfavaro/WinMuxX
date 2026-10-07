@testable import AppBundle
import Foundation
import XCTest
import os

final class DisplayRefreshFrameMailboxTest: XCTestCase {
    func testBusyConsumerReceivesLatestFrameWithOnlyOnePendingDelivery() throws {
        let mailbox = DisplayRefreshFrameMailbox()
        let delivery = try XCTUnwrap(mailbox.enqueue(timestamp: 1))
        for tick in 2...10_000 {
            XCTAssertNil(mailbox.enqueue(timestamp: Double(tick)))
        }
        XCTAssertEqual(mailbox.take(generation: delivery), 10_000)
        XCTAssertNil(mailbox.take(generation: delivery))
        let next = try XCTUnwrap(mailbox.enqueue(timestamp: 10_001))
        XCTAssertEqual(mailbox.take(generation: next), 10_001)
    }

    func testQueuedFrameFromStoppedClockCannotConsumeRestartedClockFrame() throws {
        let mailbox = DisplayRefreshFrameMailbox()
        let oldDelivery = try XCTUnwrap(mailbox.enqueue(timestamp: 1))
        mailbox.reset()
        let newDelivery = try XCTUnwrap(mailbox.enqueue(timestamp: 2))
        XCTAssertNil(mailbox.take(generation: oldDelivery))
        XCTAssertEqual(mailbox.take(generation: newDelivery), 2)
    }

    func testConcurrentDisplayCallbacksScheduleOneDelivery() throws {
        let mailbox = DisplayRefreshFrameMailbox()
        let deliveries = OSAllocatedUnfairLock(initialState: [UInt64]())
        DispatchQueue.concurrentPerform(iterations: 1_000) { tick in
            if let delivery = mailbox.enqueue(timestamp: Double(tick)) {
                deliveries.withLock { $0.append(delivery) }
            }
        }
        let scheduled = deliveries.withLock { $0 }
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertNotNil(mailbox.take(generation: try XCTUnwrap(scheduled.first)))
    }
}
