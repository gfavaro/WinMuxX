import AppKit
import Common

/// Operations and process facts used by native windows. MacApp retains ownership of its
/// AX thread; alternate implementations need neither an AX element nor a running process.
protocol WindowApplication: AbstractApp {
    var appId: KnownBundleId? { get }
    var isAccessoryApp: Bool { get }
    var isRetired: Bool { get }
    var isTerminated: Bool { get }
    var isHidden: Bool { get }
    var launchDate: Date? { get }
    /// Presentation-only metadata; window management uses the process facts above.
    var nativeApplication: NSRunningApplication? { get }
    func terminate() -> Bool
    func unregisterDestroyedWindow(_ windowId: UInt32) async throws
    func closeAndUnregisterAxWindow(_ windowId: UInt32)
    func pressCloseButton(_ windowId: UInt32) async throws -> Bool
    func containsAxWindow(_ windowId: UInt32) async throws -> Bool
    func probeAxWindows(limit: Int) async throws -> [AxWindowProbe]
    func axWindowReachability(_ windowId: UInt32) async -> AxWindowReachability
    func getAxSize(_ windowId: UInt32) async throws -> CGSize?
    @MainActor func nativeFocus(_ windowId: UInt32, forceRaise: Bool)
    @MainActor func setAxFrame(_ windowId: UInt32, _ point: CGPoint?, _ size: CGSize?)
    @MainActor func setAnimatedAxFrame(_ windowId: UInt32, _ frame: CGRect, session: UUID)
    @MainActor func setAxFrameBlocking(_ windowId: UInt32, _ point: CGPoint?, _ size: CGSize?, positionFirst: Bool) async throws -> Bool
    func getAxRectForLayoutConfirmation(_ windowId: UInt32) async throws -> Rect?
    func getAxWindowsCount() async throws -> Int?
    func restartWindowIdentities() async throws -> [(UInt32, RestartWindowIdentity)]
    func getRestartWindowIdentity(_ windowId: UInt32) async throws -> RestartWindowIdentity?
    func getAxRect(_ windowId: UInt32) async throws -> Rect?
    func isWindowHeuristic(_ windowId: UInt32, _ level: MacOsWindowLevel?) async throws -> Bool
    func getAxUiElementWindowType(_ windowId: UInt32, _ level: MacOsWindowLevel?) async throws -> AxUiElementWindowType
    func isDialogHeuristic(_ windowId: UInt32, _ level: MacOsWindowLevel?) async throws -> Bool
    func setNativeFullscreen(_ windowId: UInt32, _ value: Bool)
    func setNativeMinimized(_ windowId: UInt32, _ value: Bool)
    func dumpWindowAxInfo(windowId: UInt32) async throws -> [String: Json]
    func dumpAppAxInfo() async throws -> [String: Json]
    func getAxTitle(_ windowId: UInt32) async throws -> String?
    func readNativeState(_ windowId: UInt32) async throws -> (fullscreen: Bool, minimized: Bool)?
    func isMacosNativeFullscreen(_ windowId: UInt32) async throws -> Bool?
    func isMacosNativeMinimized(_ windowId: UInt32) async throws -> Bool?
}

extension MacApp: WindowApplication {
    var nativeApplication: NSRunningApplication? { nsApp }
    var isTerminated: Bool { nsApp.isTerminated }
    var isHidden: Bool { nsApp.isHidden }
    var launchDate: Date? { nsApp.launchDate }
    func terminate() -> Bool { nsApp.terminate() }
}
