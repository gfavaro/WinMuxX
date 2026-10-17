import XCTest

/// Pair the legacy workspace fixture replacement even when a test throws.
/// This provides cleanup, not parallel isolation.
@MainActor
class WorkspaceTestCase: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        setUpWorkspacesForTests()
    }

    override func tearDown() async throws {
        setUpWorkspacesForTests()
        try await super.tearDown()
    }
}
