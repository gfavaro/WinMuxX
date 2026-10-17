import AudioToolbox
import Common
import CoreAudio

/// The volume command's small hardware boundary also allows tests without changing audio.
struct SystemVolume {
    var readVolume: () -> Float?
    var writeVolume: (Float) -> Void
    var readMuted: () -> Bool
    var writeMuted: (Bool) -> Void

    static var native: SystemVolume {
        SystemVolume(
            readVolume: { CoreAudioOutput.readVolume() },
            writeVolume: { CoreAudioOutput.writeVolume($0) },
            readMuted: { CoreAudioOutput.readMuted() },
            writeMuted: { CoreAudioOutput.writeMuted($0) },
        )
    }

    func apply(_ action: VolumeAction) {
        switch action {
            case .up: setVolume((readVolume() ?? 0) + 0.0625)
            case .down: setVolume((readVolume() ?? 0) - 0.0625)
            case .set(let percent): setVolume(Float(percent) / 100)
            case .muteToggle: writeMuted(!readMuted())
            case .muteOn: writeMuted(true)
            case .muteOff: writeMuted(false)
        }
    }

    private func setVolume(_ value: Float) {
        writeVolume(min(max(value, 0), 1))
        // Preserve the previous command behavior, including best-effort mute after a failed write.
        writeMuted(value <= 0.005)
    }
}

private enum CoreAudioOutput {
    static func readVolume() -> Float? {
        read(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, initial: Float32(0))
            .map { min(max($0, 0), 1) }
    }

    static func writeVolume(_ value: Float) {
        write(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, value: value)
    }

    static func readMuted() -> Bool {
        read(kAudioDevicePropertyMute, initial: UInt32(0)) == 1
    }

    static func writeMuted(_ value: Bool) {
        // CoreAudio's mute property is UInt32, including on 64-bit processes.
        write(kAudioDevicePropertyMute, value: UInt32(value ? 1 : 0))
    }

    private static func device() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain,
        )
        var result = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &result,
        ) == noErr, result != kAudioObjectUnknown else { return nil }
        return result
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain,
        )
    }

    private static func read<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, initial: T) -> T? {
        guard let device = device() else { return nil }
        var address = address(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              size == MemoryLayout<T>.size else { return nil }
        return value
    }

    private static func write<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, value: T) {
        guard let device = device() else { return }
        var address = address(selector)
        guard AudioObjectHasProperty(device, &address) else { return }
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return }
        var value = value
        _ = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }
}
