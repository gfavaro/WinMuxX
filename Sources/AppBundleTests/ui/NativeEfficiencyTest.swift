@testable import AppBundle
import AppKit
import XCTest

private actor EfficiencyGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let current = waiters
        waiters = []
        current.forEach { $0.resume() }
    }
}

@MainActor
final class NativeEfficiencyTest: XCTestCase {
    func testNativeNotificationBurstProducesOneScanAndCanRestartAfterIdle() async {
        let gate = EfficiencyGate()
        let scheduler = NativeWindowRefreshScheduler(sleep: { await gate.wait() })
        let first = expectation(description: "one scan")
        var scans = 0
        for _ in 0..<1_000 { scheduler.request { scans += 1; first.fulfill() } }
        XCTAssertEqual(scans, 0)
        await gate.open()
        await fulfillment(of: [first], timeout: 2)
        XCTAssertEqual(scans, 1)
        let next = expectation(description: "next scan")
        scheduler.request { scans += 1; next.fulfill() }
        await fulfillment(of: [next], timeout: 2)
        XCTAssertEqual(scans, 2)
    }

    func testSlowSubscriberIsBoundedWithoutDelayingAnotherSubscriber() async {
        let gate = EfficiencyGate()
        let started = expectation(description: "send blocked")
        var disconnects = 0
        let slow = SubscriberEventWriter(maxEvents: 4, send: { _ in
            started.fulfill()
            await gate.wait()
            return true
        }, disconnect: { disconnects += 1 })
        slow.enqueue(Data([0]))
        await fulfillment(of: [started], timeout: 2)
        for byte: UInt8 in 1...3 { slow.enqueue(Data([byte])) }
        XCTAssertEqual(slow.bufferedEventCount, 4)
        slow.enqueue(Data([4]))
        XCTAssertTrue(slow.isClosed)
        XCTAssertEqual(slow.bufferedBytes, 0)
        XCTAssertEqual(disconnects, 1)

        let delivered = expectation(description: "other client remains responsive")
        delivered.expectedFulfillmentCount = 3
        var received: [UInt8] = []
        let fast = SubscriberEventWriter(send: { payload in
            received.append(payload[0])
            await Task.yield()
            delivered.fulfill()
            return true
        }, disconnect: { XCTFail("Healthy subscriber disconnected") })
        for byte: UInt8 in 1...3 { fast.enqueue(Data([byte])) }
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertEqual(received, [1, 2, 3])
        await gate.open()
        await Task.yield()
        XCTAssertEqual(disconnects, 1)
    }

    func testSubscriberByteLimitRejectsOversizedBacklog() {
        let writer = SubscriberEventWriter(maxBytes: 4, send: { _ in true }, disconnect: {})
        writer.enqueue(Data(repeating: 0, count: 3))
        writer.enqueue(Data(repeating: 0, count: 2))
        XCTAssertTrue(writer.isClosed)
        XCTAssertEqual(writer.bufferedBytes, 0)
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try XCTUnwrap(context.makeImage())
    }
}
