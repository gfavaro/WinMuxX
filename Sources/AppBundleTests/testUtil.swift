@testable import AppBundle
import Common
import Foundation
import HotKey
import XCTest

struct TestMonitor: Monitor {
    var hardwareIdentity: MonitorHardwareIdentity? = nil
    var displayUUID: String? = nil
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool

    var width: CGFloat { rect.width }
    var height: CGFloat { rect.height }
}

let projectRoot: URL = {
    var url = URL(filePath: #filePath).absoluteURL
    check(FileManager.default.fileExists(atPath: url.path))
    while !FileManager.default.fileExists(atPath: url.appending(component: ".git").path) {
        url.deleteLastPathComponent()
    }
    return url
}()

@MainActor
func setUpWorkspacesForTests() {
    layoutForNextDetectedWindow = nil
    LayoutUndoHistory.shared.reset()
    for workspace in Workspace.all {
        for child in workspace.children {
            child.unbindFromParent()
        }
    }
    // These roots have process lifetimes and are outside every workspace/runtime.
    // Otherwise a minimized or popup test window survives into later fixtures.
    for child in macosMinimizedWindowsContainer.children + macosPopupWindowsContainer.children {
        child.unbindFromParent()
    }

    WinMuxRuntime.replaceForTests()
    resetCachedWindowTitles()
    config.enableNormalizationFlattenContainers = false // Make layout tests more predictable
    config.enableNormalizationOppositeOrientationForNestedContainers = false // Make layout tests more predictable
    config.defaultRootContainerOrientation = .horizontal // Make default layout predictable
    config.defaultRootContainerLayout = .tiles // Keep tree tests focused on their explicit layout behavior

    // Don't create any bindings and workspaces for tests
    config.modes = [mainModeId: Mode(bindings: [:], tapBindings: [:])]
    config.persistentWorkspaces = []

    check(Workspace.get(byName: "setUpWorkspacesForTests").focusWorkspace())
    Workspace.reconcileWorkspaceState()
    check(focus.workspace.isEffectivelyEmpty)
    check(focus.workspace === Workspace.all.singleOrNil(), Workspace.all.map(\.description).joined(separator: ", "))
    check(mainMonitor.setActiveWorkspace(focus.workspace))

    fullscreenContentDisplays = []
    setScheduledRefreshOverrideForTests(nil)
    setBlockingRefreshOverridesForTests()
    cancelManipulatedWithMouseState()
    clearPendingWindowDragIntent()
    TestApp.shared.focusedWindow = nil
    TestApp.shared.windows = []
}

extension ParsedCmd {
    var errorOrNil: String? {
        if case .failure(let e) = self {
            return e
        } else {
            return nil
        }
    }

    var cmdOrDie: T { cmdOrNil ?? dieT() }
}

func testParseCommandFail(_ command: String, msg expected: String, file: StaticString = #filePath, line: UInt = #line) {
    let parsed = parseCommand(command)
    switch parsed {
        case .cmd(let command): XCTFail("\(command) isn't supposed to be parseable", file: file, line: line)
        case .failure(let msg): assertEquals(msg, expected, file: file, line: line)
        case .help: XCTFail("Expected parse failure, got help", file: file, line: line)
    }
}

extension WorkspaceCmdArgs {
    init(target: WorkspaceTarget, autoBackAndForth: Bool? = nil, wrapAround: Bool? = nil) {
        self = WorkspaceCmdArgs(rawArgs: [])
        self.target = .initialized(target)
        self._autoBackAndForth = autoBackAndForth
        self._wrapAround = wrapAround
    }
}

extension MoveNodeToWorkspaceCmdArgs {
    init(target: WorkspaceTarget, wrapAround: Bool? = nil) {
        self = MoveNodeToWorkspaceCmdArgs(rawArgs: [])
        self.target = .initialized(target)
        self._wrapAround = wrapAround
    }

    init(workspace: String) {
        self = MoveNodeToWorkspaceCmdArgs(rawArgs: [])
        self.target = .initialized(.direct(.parse(workspace).getOrDie()))
    }
}

extension HotkeyBinding {
    init(_ modifiers: NSEvent.ModifierFlags, _ keyCode: Key, _ commands: [any Command]) {
        let descriptionWithKeyNotation = modifiers.isEmpty
            ? keyCode.toString()
            : modifiers.toString() + "-" + keyCode.toString()
        self.init(modifiers, keyCode, commands, descriptionWithKeyNotation: descriptionWithKeyNotation)
    }
}

/// A paired workspace world for navigation tests. Call cleanUp from teardown.
@MainActor
final class WorkspaceNavigationFixture {
    private(set) var displays: [TestMonitor] = []
    private(set) var spaces: [Workspace] = []

    init() {
        setUpWorkspacesForTests()
        displays = (0..<3).map { index in
            let rect = Rect(topLeftX: Double(index * 1920), topLeftY: 0, width: 1920, height: 1080)
            return TestMonitor(monitorAppKitNsScreenScreensId: index + 1, name: "Display\(index + 1)",
                               rect: rect, visibleRect: rect, isMain: index == 0)
        }
        setMonitorsForTests(displays)
        spaces = (1...5).map { index in
            let workspace = Workspace.get(byName: String(index))
            TestWindow.new(id: UInt32(900 + index), parent: workspace.rootTilingContainer).markAsMostRecentChild()
            return workspace
        }
        XCTAssertTrue(displays[0].setActiveWorkspace(spaces[0]))
        XCTAssertTrue(displays[1].setActiveWorkspace(spaces[1]))
        XCTAssertTrue(displays[2].setActiveWorkspace(spaces[4]))
        XCTAssertTrue(spaces[0].focusWorkspace())
    }

    func cleanUp() {
        setUpWorkspacesForTests()
        spaces.removeAll()
        displays.removeAll()
    }
}
