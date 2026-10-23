import AppKit
import CoreGraphics
import PrivateApi

enum PrivateFrameVerdict: Equatable {
    case inconclusive(String)
    case failed(String)
    case verified
}

func comparePrivateWindowFrame(_ privateFrame: CGRect?, publicFrame: CGRect?) -> PrivateFrameVerdict {
    guard let publicFrame else { return .inconclusive("no public window-list witness") }
    guard let privateFrame else { return .failed("private frame query returned no frame") }
    let agrees = abs(privateFrame.minX - publicFrame.minX) <= 1
        && abs(privateFrame.minY - publicFrame.minY) <= 1
        && abs(privateFrame.width - publicFrame.width) <= 1
        && abs(privateFrame.height - publicFrame.height) <= 1
    return agrees ? .verified : .failed("private frame disagrees with public bounds")
}

@MainActor
func privateWindowFrameDiagnostic(_ windowId: UInt32) -> PrivateFrameVerdict {
    let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let publicFrame = windows.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowId }
        .flatMap { ($0[kCGWindowBounds as String] as? NSDictionary).flatMap(CGRect.init(dictionaryRepresentation:)) }
    var privateFrame: CGRect?
    var frame = CGRect.zero
    if winmux_window_frame(windowId, &frame) { privateFrame = frame }
    return comparePrivateWindowFrame(privateFrame, publicFrame: publicFrame)
}
