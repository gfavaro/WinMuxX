@testable import AppBundle
import AppKit
import Common

/// No native process or AX elements. Tests script only the calls relevant to their scenario.
final class ScriptedWindowApplication: WindowApplication {
    let pid: Int32 = 424242
    let rawAppBundleId: String? = nil
    let name: String? = "Scripted app"
    let execPath: String? = nil
    let bundlePath: String? = nil
    let appId: KnownBundleId? = nil
    let isAccessoryApp = false
    var isRetired = false
    var isTerminated = false
    var isHidden = false
    let launchDate: Date? = nil
    let nativeApplication: NSRunningApplication? = nil
    var rect = Rect(topLeftX: 100, topLeftY: 100, width: 400, height: 300)
    var readFailure: AXError?
    var writeFailure: AXError?
    var acceptsWrites = true
    var hasElement = true
    var beforeWrite: (() -> Void)?
    var writes: [(point: CGPoint?, size: CGSize?, positionFirst: Bool)] = []
    var reads = 0

    func unregisterDestroyedWindow(_ windowId: UInt32) async throws { hasElement = false }
    func terminate() -> Bool { isTerminated = true; return true }
    func getFocusedWindow() async throws -> Window? { nil }
    func closeAndUnregisterAxWindow(_ windowId: UInt32) { hasElement = false }
    func pressCloseButton(_ windowId: UInt32) async throws -> Bool { hasElement = false; return true }
    func containsAxWindow(_ windowId: UInt32) async throws -> Bool { hasElement }
    func axWindowReachability(_ windowId: UInt32) async -> AxWindowReachability { .reachable }
    func probeAxWindows(limit: Int) async throws -> [AxWindowProbe] { [] }
    func getAxSize(_ windowId: UInt32) async throws -> CGSize? { try await getAxRect(windowId)?.size }
    func nativeFocus(_ windowId: UInt32, forceRaise: Bool) {}
    func setAxFrame(_ windowId: UInt32, _ point: CGPoint?, _ size: CGSize?) { apply(point, size, positionFirst: false) }
    func setAnimatedAxFrame(_ windowId: UInt32, _ frame: CGRect, session: UUID) { apply(frame.origin, frame.size, positionFirst: false) }
    func setAxFrameBlocking(_ windowId: UInt32, _ point: CGPoint?, _ size: CGSize?, positionFirst: Bool) async throws -> Bool {
        beforeWrite?()
        if let writeFailure { throw AXReadFailure(code: writeFailure) }
        guard hasElement else { return false }
        apply(point, size, positionFirst: positionFirst)
        return true
    }
    private func apply(_ point: CGPoint?, _ size: CGSize?, positionFirst: Bool) {
        writes.append((point, size, positionFirst))
        guard acceptsWrites else { return }
        rect = Rect(topLeftX: point?.x ?? rect.topLeftX, topLeftY: point?.y ?? rect.topLeftY,
                    width: size?.width ?? rect.width, height: size?.height ?? rect.height)
    }
    func getAxRect(_ windowId: UInt32) async throws -> Rect? {
        reads += 1
        if let readFailure { throw AXReadFailure(code: readFailure) }
        return hasElement ? rect : nil
    }
    func getAxRectForLayoutConfirmation(_ windowId: UInt32) async throws -> Rect? { try await getAxRect(windowId) }
    func getAxWindowsCount() async throws -> Int? { hasElement ? 1 : 0 }
    func restartWindowIdentities() async throws -> [(UInt32, RestartWindowIdentity)] { [] }
    func getRestartWindowIdentity(_ windowId: UInt32) async throws -> RestartWindowIdentity? { nil }
    func isWindowHeuristic(_ windowId: UInt32, _ level: MacOsWindowLevel?) async throws -> Bool { true }
    func getAxUiElementWindowType(_ windowId: UInt32, _ level: MacOsWindowLevel?) async throws -> AxUiElementWindowType { .window }
    func isDialogHeuristic(_ windowId: UInt32, _ level: MacOsWindowLevel?) async throws -> Bool { false }
    func setNativeFullscreen(_ windowId: UInt32, _ value: Bool) {}
    func setNativeMinimized(_ windowId: UInt32, _ value: Bool) {}
    func dumpWindowAxInfo(windowId: UInt32) async throws -> [String: Json] { [:] }
    func dumpAppAxInfo() async throws -> [String: Json] { [:] }
    func getAxTitle(_ windowId: UInt32) async throws -> String? { "Scripted window" }
    func readNativeState(_ windowId: UInt32) async throws -> (fullscreen: Bool, minimized: Bool)? {
        if let readFailure { throw AXReadFailure(code: readFailure) }
        return (false, false)
    }
    func isMacosNativeFullscreen(_ windowId: UInt32) async throws -> Bool? { false }
    func isMacosNativeMinimized(_ windowId: UInt32) async throws -> Bool? { false }
}
