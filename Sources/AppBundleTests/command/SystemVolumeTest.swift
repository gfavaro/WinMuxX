@testable import AppBundle
import Common
import XCTest

final class SystemVolumeTest: XCTestCase {
    func testVolumeStepsClampingAndAutomaticMute() {
        let cases: [(VolumeAction, Float?, Float, Bool)] = [
            (.up, 0.5, 0.5625, false),
            (.down, 0.5, 0.4375, false),
            (.up, 0.99, 1, false),
            (.down, 0.02, 0, true),
            (.down, 0.067, 0.0045, true),
            (.down, 0.069, 0.0065, false),
            (.set(0), 0.5, 0, true),
            (.set(37), 0.5, 0.37, false),
            (.set(100), nil, 1, false),
            (.up, nil, 0.0625, false),
            (.down, nil, 0, true),
        ]
        for (action, initial, expectedVolume, expectedMute) in cases {
            var volume: Float?
            var muted: Bool?
            var writes: [String] = []
            let output = SystemVolume(
                readVolume: { initial },
                writeVolume: { volume = $0; writes.append("volume") },
                readMuted: { false },
                writeMuted: { muted = $0; writes.append("mute") },
            )
            output.apply(action)
            XCTAssertEqual(volume ?? -1, expectedVolume, accuracy: 0.00001, "\(action)")
            XCTAssertEqual(muted, expectedMute, "\(action)")
            XCTAssertEqual(writes, ["volume", "mute"])
        }
    }

    func testMuteCommandsPreserveVolumeAndToggleBothWays() {
        for initial in [true, false] {
            for action in [VolumeAction.muteOn, .muteOff, .muteToggle] {
                var muted: Bool?
                let output = SystemVolume(
                    readVolume: { XCTFail("Mute should not read volume"); return nil },
                    writeVolume: { _ in XCTFail("Mute should not write volume") },
                    readMuted: { initial },
                    writeMuted: { muted = $0 },
                )
                output.apply(action)
                let expected = action == .muteToggle ? !initial : action == .muteOn
                XCTAssertEqual(muted, expected)
            }
        }
    }

    func testFailedVolumeWriteStillAttemptsMute() {
        var muted: Bool?
        let output = SystemVolume(
            readVolume: { nil },
            writeVolume: { _ in /* Hardware rejected the write. */ },
            readMuted: { false },
            writeMuted: { muted = $0 },
        )
        output.apply(.set(0))
        XCTAssertEqual(muted, true)
    }
}
