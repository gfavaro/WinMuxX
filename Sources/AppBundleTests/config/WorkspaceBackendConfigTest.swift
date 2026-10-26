import XCTest
import Common
@testable import AppBundle

@MainActor
final class WorkspaceBackendConfigTest: WorkspaceTestCase {
    func testOmittedBackendRemainsVirtualAndNativeRequiresExplicitOptIn() {
        XCTAssertEqual(parseConfig("").config.workspaceBackend, .virtual)
        let native = parseConfig("[workspace-backend]\ntype = 'native'")
        XCTAssertTrue(native.errors.isEmpty)
        XCTAssertEqual(native.config.workspaceBackend, .native)
        XCTAssertFalse(parseConfig("[workspace-backend]\ntype = 'automatic'").errors.isEmpty)
        XCTAssertFalse(parseConfig("[workspace-backend]\nunknown = true").errors.isEmpty)
        XCTAssertFalse(parseConfig("workspace-backend = 'native'").errors.isEmpty)
    }

    func testReloadRejectsBackendSwitchWithoutPublishingOrMutatingWorkspace() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".toml")
        defer { try? FileManager.default.removeItem(at: file) }
        try "[workspace-backend]\ntype = 'native'".write(to: file, atomically: true, encoding: .utf8)
        let workspace = Workspace.get(byName: "retained")
        let originalURL = configUrl
        isWinMuxRuntimeReady = true
        var output = ""
        let result = try await reloadConfig(forceConfigUrl: file, stdout: &output)
        XCTAssertFalse(result)
        XCTAssertTrue(output.contains("requires restarting"))
        XCTAssertEqual(config.workspaceBackend, .virtual)
        XCTAssertEqual(runtime.workspaceBackend.kind, .virtual)
        XCTAssertEqual(configUrl, originalURL)
        XCTAssertTrue(Workspace.existing(byName: "retained") === workspace)
    }

    func testDryRunCanValidateFutureBackendWithoutSelectingIt() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".toml")
        defer { try? FileManager.default.removeItem(at: file) }
        try "[workspace-backend]\ntype = 'native'".write(to: file, atomically: true, encoding: .utf8)
        isWinMuxRuntimeReady = true
        var output = ""
        let result = try await reloadConfig(args: ReloadConfigCmdArgs(rawArgs: []).copy(\.dryRun, true),
            forceConfigUrl: file, stdout: &output)
        XCTAssertTrue(result)
        XCTAssertEqual(config.workspaceBackend, .virtual)
        XCTAssertEqual(runtime.workspaceBackend.kind, .virtual)
    }

    func testNativeStartupConfigurationDoesNotMaterializeVirtualWorkspaces() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".toml")
        defer { try? FileManager.default.removeItem(at: file) }
        try "config-version = 2\npersistent-workspaces = ['should-not-exist']\n[workspace-backend]\ntype = 'native'"
            .write(to: file, atomically: true, encoding: .utf8)
        let count = Workspace.all.count
        var output = ""
        XCTAssertFalse(isWinMuxRuntimeReady)
        let result = try await reloadConfig(forceConfigUrl: file, stdout: &output)
        XCTAssertTrue(result)
        XCTAssertEqual(runtime.workspaceBackend.kind, .native)
        XCTAssertEqual(config.workspaceBackend, .native)
        XCTAssertNil(Workspace.existing(byName: "should-not-exist"))
        XCTAssertEqual(Workspace.all.count, count)
        XCTAssertNil(runtime.workspaceBackend.observation)
    }

    func testStartupHookCannotChangeBackendBeforeRuntimeIsReady() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".toml")
        defer { try? FileManager.default.removeItem(at: file) }
        try "[workspace-backend]\ntype = 'native'".write(to: file, atomically: true, encoding: .utf8)
        runtime.workspaceBackend.lockSelection()
        XCTAssertFalse(isWinMuxRuntimeReady)
        var output = ""
        let result = try await reloadConfig(forceConfigUrl: file, stdout: &output)
        XCTAssertFalse(result)
        XCTAssertEqual(runtime.workspaceBackend.kind, .virtual)
        XCTAssertTrue(output.contains("requires restarting"))
    }

    func testNativeReadOnlyCommandsRejectVirtualQueriesAndMutation() async throws {
        runtime.workspaceBackend.selectForStartup(.native)
        let original = Workspace.all.count
        for text in ["workspace 99", "list-workspaces --all", "enable off"] {
            let command = try XCTUnwrap(parseCommand(text).unwrap().0)
            let result = try await command.run(.defaultEnv, .emptyStdin)
            XCTAssertNotEqual(result.exitCode, 0)
            XCTAssertTrue(result.stderr.joined().contains("unsupported"))
        }
        XCTAssertEqual(Workspace.all.count, original)
        XCTAssertTrue(TrayMenuModel.shared.isEnabled)
        let doctor = try XCTUnwrap(parseCommand("doctor").unwrap().0)
        let result = try await doctor.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.joined().contains("Native Spaces"))
        XCTAssertEqual(Workspace.all.count, original)
    }
}
