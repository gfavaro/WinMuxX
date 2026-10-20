import AppKit
import Common
import os

/// A repair requires confirmed normal state, including after an invalidated cache.
func canRecoverHiddenWorkspaceWindow(completedParking: Bool, inactive: Bool, appHidden: Bool,
                                     nativeFullscreen: Bool?, nativeMinimized: Bool?) -> Bool {
    completedParking && inactive && !appHidden && nativeFullscreen == false && nativeMinimized == false
}

@MainActor
struct HiddenWorkspaceWindowRecoveryDependencies {
    var isHiddenInactive: (UInt32) -> Bool
    var isNativelyParked: (UInt32) -> Bool
    var confirmNativeState: (UInt32) async -> Bool = { _ in true }
    var invalidate: (UInt32) -> Void
    var requestRefresh: ([UInt32]) -> Void
    static var live: Self {
        Self(isHiddenInactive: { id in
            guard TrayMenuModel.shared.isEnabled, !WindowBorderController.shared.isMissionControlActive,
                  !WindowRecoveryController.shared.suppressAutomaticFrameWrites,
                  currentlyManipulatedWithMouseWindowId != id,
                  let window = MacWindow.allWindowsMap[id] else { return false }
            return window.isHiddenInCorner && window.layoutReason == .standard &&
                window.hasCompletedNativeParking && window.nodeWorkspace?.isVisible == false && !window.macApp.nsApp.isHidden &&
                window.lastKnownNativeFullscreen != true && window.lastKnownNativeMinimized != true
        }, isNativelyParked: { MacWindow.allWindowsMap[$0]?.hasConfirmedNativeParkingPosition() == true },
        confirmNativeState: { id in
            guard let window = MacWindow.allWindowsMap[id] else { return false }
            let token = window.nativeStateObservationToken()
            guard let state = try? await window.readNativeState(),
                  window.nativeStateObservationToken() == token, MacWindow.allWindowsMap[id] === window else { return false }
            window.recordObservedNativeState(fullscreen: state.fullscreen, minimized: state.minimized, token: token)
            return canRecoverHiddenWorkspaceWindow(completedParking: window.hasCompletedNativeParking,
                inactive: window.nodeWorkspace?.isVisible == false, appHidden: window.macApp.nsApp.isHidden,
                nativeFullscreen: state.fullscreen, nativeMinimized: state.minimized)
        },
        invalidate: { MacWindow.allWindowsMap[$0]?.invalidateLastKnownNativeState() }, requestRefresh: { ids in
            logger.notice("Repairing native drift of parked windows: \(String(describing: ids), privacy: .public)")
            scheduleRefreshSession(.onWindowParkingDrift)
        })
    }
    private static let logger = Logger(subsystem: "com.gfavaro.winmuxx", category: "workspace-parking-recovery")
}

/// Reuse native notifications; no polling and no focus/workspace mutations.
@MainActor
final class HiddenWorkspaceWindowRecovery {
    static let shared = HiddenWorkspaceWindowRecovery()
    private let dependencies: HiddenWorkspaceWindowRecoveryDependencies
    private var pending = Set<UInt32>()
    private(set) var task: Task<Void, Never>?
    init(dependencies: HiddenWorkspaceWindowRecoveryDependencies = .live) { self.dependencies = dependencies }
    func nativeGeometryChanged(_ id: UInt32) {
        guard dependencies.isHiddenInactive(id) else { return }
        pending.insert(id)
        scheduleBatch()
    }
    private func scheduleBatch() {
        guard task == nil, !pending.isEmpty else { return }
        task = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            let candidates = self.pending.sorted()
            self.pending.removeAll()
            var drifted: [UInt32] = []
            for id in candidates {
                guard self.dependencies.isHiddenInactive(id), !self.dependencies.isNativelyParked(id),
                      await self.dependencies.confirmNativeState(id), self.dependencies.isHiddenInactive(id),
                      !self.dependencies.isNativelyParked(id) else { continue }
                drifted.append(id)
            }
            self.task = nil
            // Notifications arriving during an AX observation need one follow-up
            // batch. Keeping task non-nil above bounds concurrent observations.
            self.scheduleBatch()
            drifted = drifted.filter { self.dependencies.isHiddenInactive($0) && !self.dependencies.isNativelyParked($0) }
            guard !drifted.isEmpty else { return }
            for id in drifted { self.dependencies.invalidate(id) }
            self.dependencies.requestRefresh(drifted)
        }
    }
}
