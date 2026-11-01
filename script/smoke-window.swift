// Window helper for script/smoke.sh, compiled by it at start. It reads frames from
// WindowServer and moves only the smoke test's own TextEdit window, through TextEdit's
// scripting (no Accessibility needed):
//   frame ID          x y width height
//   shown ID          "shown" when at least half the window is on a display, else "hidden"
//   nudge ID          TextEdit moves the window 60 pt down, as an app moving its own window
//   fight ID SECONDS  nudges again each time WinMuxX puts it back, within milliseconds,
//                     and prints "putbacks=N resting=BOOL"
import AppKit

func frame(_ id: CGWindowID) -> CGRect? {
    let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] ?? []
    return (rows.first?[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
}

/// The same tolerance as WinMuxX's own `windowRestsOnTile`.
func rests(_ frame: CGRect, on tile: CGRect) -> Bool {
    abs(frame.minX - tile.minX) <= 4 && abs(frame.minY - tile.minY) <= 4 &&
        frame.width >= tile.width - 24 && frame.height >= tile.height - 24
}

func nudgeScript(from tile: CGRect) -> NSAppleScript {
    let bounds = [tile.minX, tile.minY + 60, tile.maxX, tile.maxY].map { String(Int($0)) }.joined(separator: ", ")
    let script = NSAppleScript(source: "tell application \"TextEdit\" to set bounds of window 1 to {\(bounds)}")!
    script.compileAndReturnError(nil)
    return script
}

let args = CommandLine.arguments
guard args.count >= 3, let id = CGWindowID(args[2]), let start = frame(id) else { print("unknown"); exit(1) }
switch args[1] {
    case "frame":
        print(Int(start.minX), Int(start.minY), Int(start.width), Int(start.height))
    case "shown":
        let area = start.width * start.height
        let onDisplays = NSScreen.screens.map { screen -> CGFloat in
            let bounds = CGDisplayBounds(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID)
            let overlap = bounds.intersection(start)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }.reduce(0, +)
        print(area > 0 && onDisplays / area >= 0.5 ? "shown" : "hidden")
    case "nudge":
        nudgeScript(from: start).executeAndReturnError(nil)
    case "fight":
        let tile = start
        let nudge = nudgeScript(from: tile)
        let deadline = Date().addingTimeInterval(Double(args.count > 3 ? args[3] : "4") ?? 4)
        var putBacks = 0
        // WindowServer can report the old frame for a moment after TextEdit answers, so a
        // put-back counts only once the window had visibly left its tile.
        var left = false
        nudge.executeAndReturnError(nil)
        while Date() < deadline {
            usleep(5000)
            guard let now = frame(id) else { continue }
            if !rests(now, on: tile) { left = true; continue }
            guard left else { continue }
            putBacks += 1
            left = false
            nudge.executeAndReturnError(nil)
        }
        print("putbacks=\(putBacks) resting=\(frame(id).map { rests($0, on: tile) } ?? false)")
    default:
        exit(1)
}
