import AppKit
import CoreGraphics

/// Current-host Mission Control overlay signature. This is a heuristic, not a
/// documented Mission Control API, and must be validated on each supported OS.
public enum NativeSpaceTransitionGuard {
    public static func isMissionControlVisible(_ windows: [[String: Any]], screenSizes: [CGSize],
                                               bundleIdentifierForPID: (pid_t) -> String?) -> Bool {
        windows.contains { window in
            // Layer first: the bundle lookup creates an NSRunningApplication per window.
            guard (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 19,
                  let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  bundleIdentifierForPID(pid) == "com.apple.WindowManager",
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.width > 0, frame.height > 0 else { return false }
            return screenSizes.contains { abs($0.width - frame.width) < 2 && abs($0.height - frame.height) < 2 }
        }
    }

    static func allowsFrameOperations(windows: [[String: Any]]) -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0, count <= 32 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return false }
        let sizes = ids.prefix(Int(count)).map { CGDisplayBounds($0).size }
        guard sizes.allSatisfy({ $0.width > 0 && $0.height > 0 }) else { return false }
        return !isMissionControlVisible(windows, screenSizes: sizes, bundleIdentifierForPID: windowManagerBundleIdentifier)
    }

    static let windowManagerPath = "/System/Library/CoreServices/WindowManager.app/Contents/MacOS/WindowManager"

    /// `com.apple.WindowManager` for the process that draws Mission Control, otherwise nil.
    /// The only bundle these checks ask about, answered from the process's executable path:
    /// a system call rather than a synchronous LaunchServices request per process.
    public static func windowManagerBundleIdentifier(_ pid: pid_t) -> String? {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        return String(cString: path) == windowManagerPath ? "com.apple.WindowManager" : nil
    }
}
