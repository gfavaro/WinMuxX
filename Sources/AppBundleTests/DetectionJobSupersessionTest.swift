@testable import AppBundle
import XCTest

final class DetectionJobSupersessionTest: XCTestCase {
    @MainActor
    func testReusedWindowIDCancelsOlderDetectionJob() async throws {
        setUpWorkspacesForTests()
        defer { setUpWorkspacesForTests() }
        let operations = WindowDetectionOperations(isCurrent: { _ in true })
        defer { operations.cancelAll() }

        let original = TestWindow.new(id: 8123, parent: focus.workspace.rootTilingContainer)
        let started = expectation(description: "Original detection started")
        let oldJob = Task { @MainActor in
            try await operations.run(original) {
                started.fulfill()
                try await Task.sleep(for: .seconds(30))
            }
        }
        await fulfillment(of: [started], timeout: 2)

        // WindowServer IDs are reused; a new owner must replace the old job.
        let replacement = TestWindow.new(id: 8123, parent: focus.workspace.rootTilingContainer)
        var replacementCompleted = false
        try await operations.run(replacement) { replacementCompleted = true }
        XCTAssertTrue(replacementCompleted)
        do {
            try await oldJob.value
            XCTFail("The superseded detection should be cancelled")
        } catch is CancellationError {
            // Expected: the newer owner won.
        }
    }
}
