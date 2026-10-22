import AppKit
import Common

private let sideFilteredCallback: CGEventTapCallBack = { _, type, event, _ in
    nonisolated(unsafe) let borrowedEvent = event
    let consumed = MainActor.assumeIsolated {
        SideFilteredHotkeys.shared.handle(type, borrowedEvent)
    }
    return consumed ? nil : Unmanaged.passUnretained(event)
}

/// Restricted chords never register with Carbon, which would consume both modifier sides.
@MainActor final class SideFilteredHotkeys {
    static let shared = SideFilteredHotkeys()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var consumedKeys = Set<Int64>()

    func install() -> Bool {
        if tap != nil { return true }
        if isUnitTest { return true }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: sideFilteredCallback, userInfo: nil),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            consumedKeys.removeAll()
            finishUnboundKeyPassThrough(keyCode: nil)
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            finishUnboundKeyPassThrough(keyCode: key)
            return consumedKeys.remove(key) != nil
        }
        guard type == .keyDown else { return false }
        if consumedKeys.contains(key), event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        if exitModeForUnboundKey(keyCode: key, flags: flags) { return false }
        let consumed = handleSideFilteredKeyDown(keyCode: key, flags: flags)
        if consumed { consumedKeys.insert(key) }
        // Keep the rest of an accepted key press consumed if its command changed mode.
        return consumed || (consumedKeys.contains(key) && event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
    }
}
