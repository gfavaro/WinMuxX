@testable import AppBundle
import Common
import XCTest

@MainActor
final class HiddenWorkspaceWindowRecoveryTest: XCTestCase {
    func testEventsDuringStateReadDrainInOneFollowupBatch() async {
        var receive: ((UInt32) -> Void)?
        var confirmations: [UInt32] = [], requests: [[UInt32]] = []
        let recovery = HiddenWorkspaceWindowRecovery(dependencies: .init(isHiddenInactive: { _ in true },
            isNativelyParked: { _ in false }, confirmNativeState: { id in
                confirmations.append(id)
                if id == 1 {
                    for _ in 0..<1000 { receive?(2) }
                    await Task.yield()
                    return false
                }
                return true
            }, invalidate: { _ in }, requestRefresh: { requests.append($0) }))
        receive = { [weak recovery] in recovery?.nativeGeometryChanged($0) }
        recovery.nativeGeometryChanged(1)
        await recovery.task?.value
        await recovery.task?.value
        XCTAssertEqual(confirmations, [1, 2])
        XCTAssertEqual(requests, [[2]])
        XCTAssertNil(recovery.task)
    }

    func testOnlyDriftedWindowsFetchNativeStateAndUnsafeStateNeverRepairs() async {
        var confirmations: [UInt32] = [], invalidations: [UInt32] = [], requests: [[UInt32]] = []
        let recovery = HiddenWorkspaceWindowRecovery(dependencies: .init(isHiddenInactive: { _ in true },
            isNativelyParked: { $0 == 1 }, confirmNativeState: { id in
                confirmations.append(id)
                return id == 2 // Unknown cache resolves normal for 2, minimized/fullscreen or failed read for 3.
            }, invalidate: { invalidations.append($0) }, requestRefresh: { requests.append($0) }))
        for id: UInt32 in [1, 2, 3] { recovery.nativeGeometryChanged(id) }
        await recovery.task?.value
        XCTAssertEqual(confirmations, [2, 3])
        XCTAssertEqual(invalidations, [2])
        XCTAssertEqual(requests, [[2]])
    }

    func testWorkspaceBecomingVisibleDuringNativeConfirmationCancelsRepair() async {
        var inactive = true
        let recovery = HiddenWorkspaceWindowRecovery(dependencies: .init(isHiddenInactive: { _ in inactive },
            isNativelyParked: { _ in false }, confirmNativeState: { _ in inactive = false; return true },
            invalidate: { _ in XCTFail("Visible window must not be invalidated") },
            requestRefresh: { _ in XCTFail("Visible window must not be repaired") }))
        recovery.nativeGeometryChanged(1)
        await recovery.task?.value
    }

    func testOnlyCompletedKnownNormalParkingCanUseTheFastRepair() {
        XCTAssertTrue(canRecoverHiddenWorkspaceWindow(completedParking: true, inactive: true, appHidden: false,
            nativeFullscreen: false, nativeMinimized: false))
        for (completed, inactive, appHidden, fullscreen, minimized): (Bool, Bool, Bool, Bool?, Bool?) in [
            (false, true, false, false, false), (true, false, false, false, false),
            (true, true, true, false, false), (true, true, false, true, false),
            (true, true, false, false, true), (true, true, false, nil, false),
            (true, true, false, false, nil)
        ] {
            XCTAssertFalse(canRecoverHiddenWorkspaceWindow(completedParking: completed, inactive: inactive,
                appHidden: appHidden, nativeFullscreen: fullscreen, nativeMinimized: minimized))
        }
    }
    func testNativeNotificationBurstCoalescesAndSkipsConfirmedParking() async {
        var observations = 0, refreshes = 0
        let recovery = HiddenWorkspaceWindowRecovery(dependencies: .init(isHiddenInactive: { _ in true },
            isNativelyParked: { _ in observations += 1; return true },
            invalidate: { _ in XCTFail("Confirmed parking must not invalidate caches") },
            requestRefresh: { _ in refreshes += 1 }))
        for _ in 0..<1000 { recovery.nativeGeometryChanged(1); recovery.nativeGeometryChanged(2) }
        await recovery.task?.value
        XCTAssertEqual(observations, 2)
        XCTAssertEqual(refreshes, 0)
        XCTAssertNil(recovery.task)
    }
    func testNativeDriftRequestsOneRepairWithoutAdoptingVisibleWindow() async {
        var inactive: Set<UInt32> = [1, 2, 3]
        var invalidated: [UInt32] = [], requests: [[UInt32]] = []
        let recovery = HiddenWorkspaceWindowRecovery(dependencies: .init(isHiddenInactive: { inactive.contains($0) },
            isNativelyParked: { $0 == 2 }, invalidate: { invalidated.append($0) }, requestRefresh: { requests.append($0) }))
        for id: UInt32 in [3, 2, 1, 1, 3] { recovery.nativeGeometryChanged(id) }
        // A workspace switch before the coalesced callback must win over recovery.
        inactive.remove(3)
        await recovery.task?.value
        XCTAssertEqual(invalidated, [1])
        XCTAssertEqual(requests, [[1]])
        XCTAssertTrue(RefreshSessionEvent.onWindowParkingDrift.canReuseLastAppliedWindowFrames)
        XCTAssertFalse(RefreshSessionEvent.onWindowParkingDrift.requiresWindowRefreshBarrier)
        XCTAssertFalse(RefreshSessionEvent.onWindowParkingDrift.requiresLayoutReasonNormalization)
        XCTAssertFalse(RefreshSessionEvent.onWindowParkingDrift.requiresHiddenWindowsReassertion)
    }
}
