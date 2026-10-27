import AppKit
import CoreGraphics
import Darwin
import Foundation

// Switches native Spaces by posting synthetic Dock swipes, the one synthesized-input
// technique this module uses. It works with SIP enabled and needs no Mission Control
// keyboard shortcuts, but it relies on private event fields and an IOHID payload
// layout the Dock reads on macOS 27. Callers must confirm landing from a fresh
// topology read rather than trusting a successful post.
//
// Adapted from Dinky (MIT, Copyright (c) 2026 Mikkel Malmberg),
// Sources/DinkyPrivate/switch.m, itself a port of mimi's dockswipe.m.
public enum NativeDockSwipe {
    /// The augmented payload format is the only one validated here.
    public static var isSupported: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 }

    /// Without Accessibility permission macOS drops posted events silently.
    public static var canPostEvents: Bool { CGPreflightPostEventAccess() }

    /// Posts `steps` swipes toward higher (`towardHigherIndex`) or lower Space indices on
    /// the display. The Dock swipes the display under the pointer, so the pointer is
    /// moved there for the swipe and put back afterwards. Does not wait for landing.
    @MainActor
    public static func post(steps: Int, towardHigherIndex: Bool, displayIdentifier: String) async -> Bool {
        guard isSupported, steps > 0, let displayID = displayID(for: displayIdentifier) else { return false }
        // After a warp macOS drops real mouse events for a quarter second unless the
        // suppression interval is zero; yabai and Dinky set this for the same reason.
        suppressionReset?(0)
        let restore = cursorLocation()
        let warp = !CGDisplayBounds(displayID).contains(restore)
        if warp {
            let bounds = CGDisplayBounds(displayID)
            CGWarpMouseCursorPosition(CGPoint(x: bounds.midX, y: bounds.midY))
            try? await Task.sleep(for: stepDelay)
        }
        // Back to back: pausing between steps would land on each Space on the way and
        // let macOS activate an app there.
        var posted = true
        for _ in 0..<steps where posted { posted = postSwipe(sign: towardHigherIndex ? 1 : -1) }
        if warp {
            try? await Task.sleep(for: stepDelay)
            CGWarpMouseCursorPosition(restore)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        return posted
    }

    /// "Main" is the identifier when displays do not have separate Spaces.
    static func displayID(for identifier: String) -> CGDirectDisplayID? {
        if identifier == "Main" { return CGMainDisplayID() }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { id in
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return false }
            return (CFUUIDCreateString(nil, uuid) as String?) == identifier
        }
    }

    private static let stepDelay: Duration = .milliseconds(30)

    /// CGSetLocalEventsSuppressionInterval is unavailable to Swift but still exported;
    /// without it the pointer stalls briefly after the warp. Absent, the swipe still works.
    private static let suppressionReset: (@convention(c) (Double) -> Int32)? =
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSetLocalEventsSuppressionInterval")
            .map { unsafeBitCast($0, to: (@convention(c) (Double) -> Int32).self) }

    // Private CGEvent field numbers for a synthetic Dock swipe.
    private static let eventTypeField = 55, dockControl: Int64 = 30
    private static let gestureHIDType = 110, dockSwipeHIDType: Int64 = 23
    private static let swipeMask = 115, swipeMotion = 123, motionHorizontal: Int64 = 1
    private static let swipeProgress = 124, swipePositionX = 125, swipePositionY = 126
    private static let swipeVelocityX = 129, swipeVelocityY = 130
    private static let gesturePhase = 132, gesturePhaseAlias = 134
    private static let zoomDeltaY = 138, sourceProcessIDAlias = 169
    private static let phaseBegan: Int64 = 1, phaseChanged: Int64 = 2, phaseEnded: Int64 = 4
    private static let rawPayloadField: UInt16 = 4205, eventDataFormatVersion: UInt8 = 2
    // Empirical values from mimi: required position/zoom, and a velocity high enough
    // to skip the per-step animation.
    private static let positionX = 0.1, zoomDelta = 3.0, velocity = 9999.0

    private static func field(_ raw: Int) -> CGEventField { CGEventField(rawValue: UInt32(raw))! }

    private static func postSwipe(sign: Double) -> Bool {
        // The payload sign runs opposite to Space index direction, and the scroll
        // direction setting reverses synthetic swipes too.
        let natural = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
        let rawSign = natural ? -sign : sign
        for phase in [phaseBegan, phaseChanged, phaseEnded] {
            guard let event = makeEvent(phase: phase, rawSign: rawSign) else { return false }
            event.post(tap: .cgSessionEventTap)
        }
        return true
    }

    private static func makeEvent(phase: Int64, rawSign: Double) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        event.setIntegerValueField(field(eventTypeField), value: dockControl)
        event.setIntegerValueField(field(gestureHIDType), value: dockSwipeHIDType)
        event.setIntegerValueField(field(swipeMotion), value: motionHorizontal)
        event.setIntegerValueField(field(gesturePhase), value: phase)
        event.setIntegerValueField(field(gesturePhaseAlias), value: phase)
        event.setDoubleValueField(field(swipeProgress), value: rawSign)
        event.setDoubleValueField(field(swipePositionX), value: positionX)
        event.setDoubleValueField(field(zoomDeltaY), value: zoomDelta)
        event.setDoubleValueField(field(sourceProcessIDAlias), value: Double(mach_absolute_time()))
        if phase == phaseEnded { event.setDoubleValueField(field(swipeVelocityX), value: rawSign * velocity) }
        return augment(event)
    }

    /// Serialize the event, append the IOHID payload as a trailing raw field, rebuild.
    private static func augment(_ event: CGEvent) -> CGEvent? {
        guard let data = event.data as Data?, data.count >= 4,
              data.prefix(4).elementsEqual([0, 0, 0, eventDataFormatVersion]) else { return nil }
        let payload = iohidPayload(event)
        var bytes = data
        bytes.append(contentsOf: [UInt8(payload.count >> 8 & 0xFF), UInt8(payload.count & 0xFF),
                                  UInt8(rawPayloadField >> 8), UInt8(rawPayloadField & 0xFF)])
        bytes.append(payload)
        return CGEvent(withDataAllocator: nil, data: bytes as CFData)
    }

    /// Little-endian IOHID system-queue element: header, fluid-touch gesture and,
    /// once the fingers lift, velocity. Layout from mimi's dockswipe.m.
    static func iohidPayload(_ event: CGEvent) -> Data {
        let phase = event.getIntegerValueField(field(gesturePhase))
        let velocityX = event.getDoubleValueField(field(swipeVelocityX))
        let velocityY = event.getDoubleValueField(field(swipeVelocityY))
        let includeVelocity = velocityX != 0 || velocityY != 0 || phase == phaseEnded
        var data = Data()
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func base(size: UInt32, type: UInt32, options: UInt32, depth: UInt8) {
            put(size); put(type); put(options); put(depth); put(UInt8(0)); put(UInt8(0)); put(UInt8(0))
        }
        let timestamp = event.timestamp
        put(timestamp != 0 ? timestamp : mach_absolute_time()) // header: timestamp
        put(UInt64(0)); put(UInt32(0)); put(UInt32(0))       // sender, options, attribute length
        put(UInt32(includeVelocity ? 2 : 1))                  // event count
        base(size: 40, type: 23, options: UInt32(truncatingIfNeeded: (phase & 0xFF) << 24), depth: 0)
        put(fixed1616(event.getDoubleValueField(field(swipePositionX))))
        put(fixed1616(event.getDoubleValueField(field(swipePositionY))))
        put(Int32(0))
        put(UInt32(truncatingIfNeeded: event.getIntegerValueField(field(swipeMask))))
        put(UInt16(truncatingIfNeeded: event.getIntegerValueField(field(swipeMotion))))
        put(UInt16(3)) // Dock primary gesture flavor
        put(fixed1616(event.getDoubleValueField(field(swipeProgress))))
        if includeVelocity {
            base(size: 28, type: 9, options: 0, depth: 1)
            put(fixed1616(velocityX)); put(fixed1616(velocityY)); put(Int32(0))
        }
        return data
    }

    static func fixed1616(_ value: Double) -> Int32 {
        let fixed = Int32(clamping: Int64(value * 65536))
        if fixed == 0 && value != 0 { return value > 0 ? 1 : -1 }
        return fixed
    }

    private static func cursorLocation() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }
}
