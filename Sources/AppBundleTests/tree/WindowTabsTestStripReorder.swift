@testable import AppBundle
import XCTest

@MainActor extension WindowTabsTest {
    func testStripReorderMovesDirectWindowTab() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let group = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let first = TestWindow.new(id: 1, parent: group)
        let second = TestWindow.new(id: 2, parent: group)
        let third = TestWindow.new(id: 3, parent: group)

        XCTAssertTrue(reorderTabGroupChild(showing: third, stripId: ObjectIdentifier(group), toIndex: 1))
        XCTAssertEqual(group.children, [first, third, second])
    }

    func testStripReorderMovesNestedContainerTabAsAUnit() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let outer = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let solo = TestWindow.new(id: 1, parent: outer)
        let nested = TilingContainer(parent: outer, adaptiveWeight: WEIGHT_AUTO, .h, .tiles, index: INDEX_BIND_LAST)
        let left = TestWindow.new(id: 2, parent: nested)
        let right = TestWindow.new(id: 3, parent: nested)

        // The strip shows the nested container through one of its windows; the container moves, its layout stays.
        XCTAssertTrue(reorderTabGroupChild(showing: right, stripId: ObjectIdentifier(outer), toIndex: 0))
        XCTAssertEqual(outer.children, [nested, solo])
        XCTAssertEqual(nested.children, [left, right])
    }

    func testStripReorderUsesTheStripsOwnTabGroupWhenTabGroupsNest() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let outer = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let solo = TestWindow.new(id: 1, parent: outer)
        let inner = TilingContainer(parent: outer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let innerFirst = TestWindow.new(id: 2, parent: inner)
        let innerSecond = TestWindow.new(id: 3, parent: inner)

        XCTAssertTrue(reorderTabGroupChild(showing: innerFirst, stripId: ObjectIdentifier(inner), toIndex: 1))
        XCTAssertEqual(inner.children, [innerSecond, innerFirst])
        XCTAssertEqual(outer.children, [solo, inner])

        XCTAssertTrue(reorderTabGroupChild(showing: innerFirst, stripId: ObjectIdentifier(outer), toIndex: 0))
        XCTAssertEqual(outer.children, [inner, solo])
        XCTAssertEqual(inner.children, [innerSecond, innerFirst])
    }

    func testStripReorderIgnoresWindowsOutsideTheStrip() {
        setUpWorkspacesForTests()
        let workspace = Workspace.get(byName: "tabs")
        let group = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, .v, .tabGroup, index: INDEX_BIND_LAST)
        let first = TestWindow.new(id: 1, parent: group)
        let second = TestWindow.new(id: 2, parent: group)
        let outsider = TestWindow.new(id: 3, parent: workspace.rootTilingContainer)

        XCTAssertFalse(reorderTabGroupChild(showing: outsider, stripId: ObjectIdentifier(group), toIndex: 0))
        XCTAssertEqual(group.children, [first, second])
    }
}
