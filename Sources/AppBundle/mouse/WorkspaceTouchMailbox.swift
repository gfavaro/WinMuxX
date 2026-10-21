import Foundation
import os

/// Driver threads copy scalar summaries into a bounded queue. Repeated movement
/// coalesces, but the first frame, contact changes and lifts retain their order.
final class WorkspaceTouchMailbox: @unchecked Sendable {
    private struct State {
        var generation: UInt64 = 0
        var frames: [WorkspaceTouchFrame] = []
        var scheduled = false
        var received = 0
        var lastContactByDevice: [UInt64: WorkspaceTouchFrame] = [:]
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func activate(_ generation: UInt64) {
        state.withLock { $0 = State(generation: generation) }
    }

    func offer(_ frame: WorkspaceTouchFrame, generation: UInt64) -> Bool {
        state.withLock { value in
            guard generation != 0, value.generation == generation else { return false }
            value.received += 1
            let previous = value.lastContactByDevice.updateValue(frame, forKey: frame.device)
            // One/two-finger motion belongs to apps; avoid a main-queue hop per frame.
            if (0..<3).contains(frame.fingers), let previous,
               previous.fingers == frame.fingers, previous.contacts == frame.contacts { return false }
            let sameContact: (WorkspaceTouchFrame) -> Bool = {
                $0.device == frame.device && $0.fingers == frame.fingers && $0.contacts == frame.contacts
            }
            if value.frames.count >= 2,
               sameContact(value.frames[value.frames.count - 1]),
               sameContact(value.frames[value.frames.count - 2]) {
                value.frames[value.frames.count - 1] = frame
            } else if value.frames.count >= 32 {
                value.frames = [WorkspaceTouchFrame(device: frame.device, fingers: -1, x: 0, y: 0,
                                                    timestamp: frame.timestamp, contacts: 0), frame]
            } else { value.frames.append(frame) }
            guard !value.scheduled else { return false }
            value.scheduled = true
            return true
        }
    }

    func take() -> (generation: UInt64, frames: [WorkspaceTouchFrame], received: Int) {
        state.withLock { value in
            let frames = value.frames
            value.frames.removeAll(keepingCapacity: true)
            value.scheduled = false
            return (value.generation, frames, value.received)
        }
    }
}

