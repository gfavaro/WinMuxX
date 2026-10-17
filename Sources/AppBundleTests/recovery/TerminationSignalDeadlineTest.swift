@testable import AppBundle
@testable import Common
import Foundation
import XCTest

private struct SignalCleanupProbe: TerminationHandler {
    let marker: URL
    func beforeTermination() async throws { try Data("cleaned".utf8).write(to: marker) }
}

@MainActor
final class TerminationSignalDeadlineTest: XCTestCase {
    func testSignalExitsEvenWhenMainQueueIsBlocked() async throws {
        if let mode = ProcessInfo.processInfo.environment["WINMUXX_SIGNAL_PROBE"],
           let marker = ProcessInfo.processInfo.environment["WINMUXX_SIGNAL_MARKER"] {
            isCli = true
            terminationHandler = SignalCleanupProbe(marker: URL(fileURLWithPath: marker))
            interceptTermination(SIGTERM, deadline: mode == "blocked" ? .milliseconds(200) : .seconds(2))
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(50)) { kill(getpid(), SIGTERM) }
            if mode == "blocked" { blockMainQueueForProbe() }
            else { try await Task.sleep(for: .seconds(2)) }
            XCTFail("Signal handler did not terminate the child")
            return
        }
        for mode in ["normal", "blocked"] {
            let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: marker) }
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            child.arguments = ["xctest", "-XCTest", "AppBundleTests.TerminationSignalDeadlineTest/testSignalExitsEvenWhenMainQueueIsBlocked", Bundle(for: Self.self).bundlePath]
            var environment = ProcessInfo.processInfo.environment
            environment["WINMUXX_SIGNAL_PROBE"] = mode
            environment["WINMUXX_SIGNAL_MARKER"] = marker.path
            child.environment = environment
            child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
            try child.run()
            let deadline = Date().addingTimeInterval(4)
            waitForChild(child, until: deadline)
            if child.isRunning { kill(child.processIdentifier, SIGKILL); child.waitUntilExit(); XCTFail("Signal was ineffective: \(mode)") }
            XCTAssertEqual(child.terminationReason, .exit)
            XCTAssertEqual(child.terminationStatus, SIGTERM)
            XCTAssertEqual(FileManager.default.fileExists(atPath: marker.path), mode == "normal")
        }
    }
}

// Deliberately block the main thread; Task.sleep would not reproduce the bug.
private func blockMainQueueForProbe() { Thread.sleep(forTimeInterval: 2) }
private func waitForChild(_ child: Process, until deadline: Date) {
    while child.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
}
