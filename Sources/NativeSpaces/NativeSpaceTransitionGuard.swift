import AppKit
import CoreGraphics

/// Current-host Mission Control overlay signature. This is a heuristic, not a
/// documented Mission Control API, and must be validated on each supported OS.
public enum NativeSpaceTransitionGuard {
    public static func isMissionControlVisible(_ windows: [[String: Any]], screenSizes: [CGSize],
                                               bundleIdentifierForPID: (pid_t) -> String?) -> Bool {
        windows.contains { window in
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  bundleIdentifierForPID(pid) == "com.apple.WindowManager",
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 19,
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
        return !isMissionControlVisible(windows, screenSizes: sizes) {
            NSRunningApplication(processIdentifier: $0)?.bundleIdentifier
        }
    }
}
