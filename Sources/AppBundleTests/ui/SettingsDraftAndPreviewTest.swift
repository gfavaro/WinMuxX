@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class SettingsDraftAndPreviewTest: XCTestCase {
    func testReloadKeepsDraftAndAcknowledgementDoesNotClearNewerEdit() {
        let store = SettingsDraftStore()
        store.set(12, for: "gaps.outer.left")
        let submitted = store.entries
        store.set(18, for: "gaps.outer.left")
        store.refreshSavedValues()
        store.acknowledge(submitted)
        XCTAssertEqual(store.value(for: "gaps.outer.left", fallback: { 0 }), 18)
        store.acknowledge(store.entries)
        XCTAssertEqual(store.value(for: "gaps.outer.left", fallback: { 12 }), 12)
    }

    func testUnchangedDraftValueDoesNotCreateAnUnsavedEntry() {
        let id = "test.unchanged-settings-draft"
        let draft = SettingsDraft(id, load: { 7 })
        draft.wrappedValue = 7
        XCTAssertNil(SettingsDraftStore.shared.entries[id])
        draft.wrappedValue = 8
        XCTAssertEqual(draft.wrappedValue, 8)
        SettingsDraftStore.shared.acknowledge(SettingsDraftStore.shared.entries.filter { $0.key == id })
    }

    func testPreviewUsesAllSixGapsAndUniformScale() {
        let values = SettingsGapPreviewValues(horizontal: 20, vertical: 30, left: 10, right: 40, top: 50, bottom: 60)
        let frames = values.frames(in: CGSize(width: 800, height: 500))
        XCTAssertEqual(frames[0], CGRect(x: 10, y: 50, width: 365, height: 180))
        XCTAssertEqual(frames[1].minX - frames[0].maxX, 20)
        XCTAssertEqual(frames[2].minY - frames[0].maxY, 30)
        XCTAssertEqual(800 - frames[1].maxX, 40)
        XCTAssertEqual(500 - frames[2].maxY, 60)
        let smaller = values.frames(in: CGSize(width: 400, height: 250))
        XCTAssertEqual(smaller[0], CGRect(x: 5, y: 25, width: 182.5, height: 90))
    }

    func testOversizedGapsDoNotProduceNegativePreviewFrames() {
        let values = SettingsGapPreviewValues(horizontal: 1000, vertical: 1000, left: 1000, right: 1000, top: 1000, bottom: 1000)
        XCTAssertTrue(values.frames(in: CGSize(width: 400, height: 250)).allSatisfy { $0.width >= 0 && $0.height >= 0 })
    }
}
