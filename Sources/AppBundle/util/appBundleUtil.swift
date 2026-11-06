import AppKit
import Common
import Foundation
import os

let signposter = OSSignposter(subsystem: winMuxAppId, category: .pointsOfInterest)

let myPid = NSRunningApplication.current.processIdentifier
let lockScreenAppBundleId = "com.apple.loginwindow"
private let lockScreenExecutablePath = "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"

/// Answered from the process's executable path. `bundleIdentifier` is a synchronous
/// LaunchServices request whenever AppKit has dropped its cached answer, which it does after
/// every app activation, and these checks run on every refresh and app notification.
/// The answer is kept on the app object: AppKit also fetches `processIdentifier` again
/// after an activation, and the same objects are asked about on every refresh.
func isLockScreenApp(_ app: NSRunningApplication?) -> Bool {
    guard let app else { return false }
    if let known = objc_getAssociatedObject(app, &lockScreenAnswerKey) as? Bool { return known }
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard proc_pidpath(app.processIdentifier, &path, UInt32(path.count)) > 0 else { return false }
    let answer = String(cString: path) == lockScreenExecutablePath
    objc_setAssociatedObject(app, &lockScreenAnswerKey, answer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return answer
}
nonisolated(unsafe) private var lockScreenAnswerKey: UInt8 = 0

@MainActor
private let terminationCoordinator = WindowTerminationCoordinator()
@MainActor
private var terminationSignals: [DispatchSourceSignal] = []

@MainActor
func interceptTermination(_ number: Int32, deadline: DispatchTimeInterval = .seconds(10)) {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: DispatchQueue(label: "\(winMuxAppId).termination"))
    source.setEventHandler(handler: terminationSignalHandler(number, deadline: deadline))
    terminationSignals.append(source)
    source.resume()
}

// Construct outside MainActor: Dispatch invokes this on the independent signal queue.
private func terminationSignalHandler(_ number: Int32, deadline: DispatchTimeInterval) -> @Sendable () -> Void {
    return {
        let completed = DispatchSemaphore(value: 0)
        Task { @MainActor in
            defer { completed.signal() }
            do { try await terminationHandler.performTerminationCleanup() }
            catch { NSLog("WinMux termination: %@", String(describing: error)) }
        }
        if completed.wait(timeout: .now() + deadline) == .timedOut {
            NSLog("WinMuxX: termination cleanup exceeded deadline; recovery will run at next launch")
            _exit(number)
        }
        exit(number)
    }
}

@MainActor
func initTerminationHandler() {
    terminationHandler = AppServerTerminationHandler()
    interceptTermination(SIGINT)
    interceptTermination(SIGTERM)
}

private struct AppServerTerminationHandler: TerminationHandler {
    func beforeTermination() async throws {
        await terminationCoordinator.run {
            MacApp.registrationRetries.cancelAll()
            WindowDetectionOperations.shared.cancelAll()
            WindowRecoveryController.shared.beginTermination()
            MacApp.cancelPendingFocus()
            persistFrozenWorldForRestartIfPossible()
            for app in MacApp.allAppsMap.values { app.cancelPendingFrameWrites() }
            let pending = await WindowRecoveryController.shared.restoreManagedWindows()
            WindowRecoveryController.shared.finishCleanly(preserving: pending)
            await toggleReleaseServerIfDebug(.on)
        }
    }
}

func terminationFrame(visibleFrame: CGRect, floatingSize: CGSize?) -> CGRect {
    let proposed = floatingSize ?? visibleFrame.size
    let size = CGSize(
        width: proposed.width.isFinite && proposed.width > 0 ? min(proposed.width, visibleFrame.width) : visibleFrame.width,
        height: proposed.height.isFinite && proposed.height > 0 ? min(proposed.height, visibleFrame.height) : visibleFrame.height
    )
    return CGRect(x: visibleFrame.minX + (visibleFrame.width - size.width) / 2,
                  y: visibleFrame.minY + (visibleFrame.height - size.height) / 2,
                  width: size.width, height: size.height)
}

@MainActor
public final class WinMuxApplicationDelegate: NSObject, NSApplicationDelegate {
    public func applicationShouldRestoreState(_ app: NSApplication) -> Bool {
        false
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        SideFilteredHotkeys.shared.stopRecovery()
        Task { @MainActor in
            do { try await terminationHandler.performTerminationCleanup() }
            catch { NSLog("WinMux termination: %@", String(describing: error)) }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@MainActor
func terminateApp() {
    NSApplication.shared.terminate(nil)
}

extension String {
    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(self, forType: .string)
    }
}

func - (a: CGPoint, b: CGPoint) -> CGPoint {
    CGPoint(x: a.x - b.x, y: a.y - b.y)
}

func + (a: CGPoint, b: CGPoint) -> CGPoint {
    CGPoint(x: a.x + b.x, y: a.y + b.y)
}

extension CGPoint: ConvenienceCopyable {}

extension CGPoint {
    func distance(toOuterFrame rect: Rect) -> CGFloat {
        if rect.contains(self) {
            return 0
        }
        let list: [CGFloat] =
            (rect.minY.until(excl: rect.maxY)?.contains(y) == true ? [abs(rect.minX - x), abs(rect.maxX - x)] : []) +
            (rect.minX.until(excl: rect.maxX)?.contains(x) == true ? [abs(rect.minY - y), abs(rect.maxY - y)] : []) +
            [
                distance(to: rect.topLeftCorner),
                distance(to: rect.bottomRightCorner),
                distance(to: rect.topRightCorner),
                distance(to: rect.bottomLeftCorner),
            ]
        return list.minOrDie()
    }

    func coerce(in rect: Rect) -> CGPoint? {
        guard let xRange = rect.minX.until(incl: rect.maxX - 1) else { return nil }
        guard let yRange = rect.minY.until(incl: rect.maxY - 1) else { return nil }
        return CGPoint(x: x.coerce(in: xRange), y: y.coerce(in: yRange))
    }

    func getProjection(_ orientation: Orientation) -> Double { orientation == .h ? x : y }

    var vectorLength: CGFloat { sqrt(x * x + y * y) }

    func distance(to point: CGPoint) -> Double { (self - point).vectorLength }

    var monitorApproximation: Monitor {
        monitors.first { $0.rect.contains(self) } ?? monitors.minByOrDie { distance(toOuterFrame: $0.rect) }
    }
}

extension CGFloat {
    func div(_ denominator: Int) -> CGFloat? {
        denominator == 0 ? nil : self / CGFloat(denominator)
    }

    func coerce(in range: ClosedRange<CGFloat>) -> CGFloat {
        switch true {
            case self > range.upperBound: range.upperBound
            case self < range.lowerBound: range.lowerBound
            default: self
        }
    }
}

extension CGPoint: @retroactive Hashable { // todo migrate to self written Point
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }
}

#if DEBUG
    let isDebug = true
#else
    let isDebug = false
#endif

enum DebugLogCategory: String {
    case focus, sidebarRename, sidebarHover, sidebarEdgeTrap, sidebarProject
}

/// Debug builds only. `log stream --level debug --predicate 'subsystem == "com.gfavaro.winmuxx.debug"'`
/// shows them; add `AND category == "focus"` for one category.
func debugLog(_ category: DebugLogCategory, _ message: @autoclosure () -> String) {
    guard isDebug else { return }
    let text = message()
    Logger(subsystem: winMuxAppId, category: category.rawValue).debug("\(text, privacy: .public)")
}

@inlinable
func checkCancellation() throws(CancellationError) {
    if Task.isCancelled {
        throw CancellationError()
    }
}
