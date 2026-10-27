import Common
import XCTest
@testable import AppBundle
@testable import NativeSpaces

@MainActor
final class NativeSpaceNavigatorTest: WorkspaceTestCase {
    private var active = "1"
    private var posts: [NativeSpaceSwitchPlan] = []

    private func topology() -> [NativeSpaceDisplay] {
        [NativeSpaceDisplay(identifier: "display-a", activeSpaceID: active, spaces: [
            NativeSpace(id: "1", uuid: "a", type: 0), NativeSpace(id: "2", uuid: "b", type: 0),
            NativeSpace(id: "3", uuid: "c", type: 0),
        ])]
    }

    private func navigator(landing: @escaping (NativeSpaceSwitchPlan) -> String?) -> NativeSpaceNavigator {
        let navigator = NativeSpaceNavigator()
        navigator.isSupported = { true }
        navigator.canPostEvents = { true }
        navigator.landingTimeout = .milliseconds(100)
        navigator.pollInterval = .milliseconds(5)
        navigator.topology = { [unowned self] in topology() }
        navigator.post = { [unowned self] plan in
            posts.append(plan)
            if let landed = landing(plan) { active = landed }
            return true
        }
        return navigator
    }

    private func run(_ navigator: NativeSpaceNavigator, _ command: String) async throws -> CmdResult {
        let args = try XCTUnwrap(parseCommand(command).cmdOrDie as? WorkspaceCommand).args
        let io = CmdIo(stdin: .emptyStdin)
        let ok = await navigator.run(args, io: io)
        return CmdResult(stdout: io.stdout, stderr: io.stderr, exitCode: ok ? 0 : 1)
    }

    func testSwitchSucceedsOnlyAfterTopologyConfirmsTheLanding() async throws {
        let result = try await run(navigator { $0.targetSpaceID }, "workspace 3")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(posts, [NativeSpaceSwitchPlan(displayIdentifier: "display-a", fromIndex: 0, toIndex: 2, targetSpaceID: "3")])
        XCTAssertEqual(active, "3")
    }

    func testPartialLandingIsRetriedOnceFromTheObservedSpace() async throws {
        // The first swipe only gets one Space along; the retry starts from there.
        let result = try await run(navigator { _ in self.active == "1" ? "2" : "3" }, "workspace 3")
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(posts.map { [$0.fromIndex, $0.toIndex] }, [[0, 2], [1, 2]])
    }

    func testUnlandedSwitchIsReportedAfterOneRetry() async throws {
        let result = try await run(navigator { _ in nil }, "workspace next")
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(posts.count, 2)
        XCTAssertTrue(result.stderr.joined().contains("did not land"))
    }

    func testNoopUnknownDesktopAndEndOfDisplayPostNothing() async throws {
        let nav = navigator { $0.targetSpaceID }
        var codes: [Int32] = []
        for command in ["workspace 1", "workspace --fail-if-noop 1", "workspace 7", "workspace prev"] {
            codes.append(try await run(nav, command).exitCode)
        }
        XCTAssertEqual(codes, [0, 1, 1, 1])
        XCTAssertTrue(posts.isEmpty)
        let wrapped = try await run(nav, "workspace --wrap-around prev")
        XCTAssertEqual(wrapped.exitCode, 0)
        XCTAssertEqual(active, "3")
    }

    func testUnsupportedHostReportsInsteadOfPosting() async throws {
        let nav = navigator { $0.targetSpaceID }
        nav.isSupported = { false }
        let result = try await run(nav, "workspace 2")
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(posts.isEmpty)
    }

    func testOnlyNumberedAndRelativeTargetsAreNativeNavigation() throws {
        func supported(_ command: String) throws -> Bool {
            try NativeSpaceNavigator.supports(XCTUnwrap(parseCommand(command).cmdOrDie as? WorkspaceCommand).args)
        }
        XCTAssertTrue(try supported("workspace 2"))
        XCTAssertTrue(try supported("workspace next --wrap-around"))
        XCTAssertFalse(try supported("workspace web"))
        XCTAssertFalse(try supported("workspace --auto-back-and-forth 2"))
    }
}
