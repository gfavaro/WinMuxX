import Common
import XCTest
@testable import AppBundle

@MainActor
final class NativeMouseReleaseTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.defaultRootContainerOrientation = .auto
    }

    private func layout() async throws -> (TestWindow, TestWindow) {
        let root = focus.workspace.rootTilingContainer
        root.layout = .dwindle
        let first = TestWindow.new(id: 31001, parent: root)
        let second = TestWindow.new(id: 31002, parent: root)
        try await focus.workspace.layoutWorkspace()
        return (first, second)
    }

    func testResizedTileKeepsItsNewSizeAfterLayout() async throws {
        let (first, _) = try await layout()
        let original = try XCTUnwrap(first.lastAppliedLayoutPhysicalRect)
        let wider = Rect(topLeftX: original.minX, topLeftY: original.minY, width: original.width + 120, height: original.height)
        XCTAssertEqual(adoptNativeMouseRelease(first, actual: wider, pointer: wider.center), .resized)
        try await focus.workspace.layoutWorkspace()
        XCTAssertEqual(first.lastAppliedLayoutPhysicalRect?.width ?? 0, wider.width, accuracy: 1)
    }

    func testDropOntoAnotherTileSwapsThem() async throws {
        let (first, second) = try await layout()
        let root = focus.workspace.rootTilingContainer
        let target = try XCTUnwrap(second.lastAppliedLayoutPhysicalRect)
        let original = try XCTUnwrap(first.lastAppliedLayoutPhysicalRect)
        let dropped = Rect(topLeftX: target.minX, topLeftY: target.minY, width: original.width, height: original.height)
        XCTAssertEqual(adoptNativeMouseRelease(first, actual: dropped, pointer: target.center), .swapped(with: 31002))
        XCTAssertEqual(root.children.compactMap { ($0 as? Window)?.windowId }, [31002, 31001])
    }

    func testClickAndDropOnEmptySpaceChangeNothing() async throws {
        let (first, _) = try await layout()
        let root = focus.workspace.rootTilingContainer
        let original = try XCTUnwrap(first.lastAppliedLayoutPhysicalRect)
        XCTAssertEqual(adoptNativeMouseRelease(first, actual: original, pointer: original.center), .none)
        let offscreen = CGPoint(x: -500, y: -500)
        let moved = Rect(topLeftX: original.minX + 60, topLeftY: original.minY + 60, width: original.width, height: original.height)
        XCTAssertEqual(adoptNativeMouseRelease(first, actual: moved, pointer: offscreen), .none)
        XCTAssertEqual(root.children.compactMap { ($0 as? Window)?.windowId }, [31001, 31002])
    }
}
