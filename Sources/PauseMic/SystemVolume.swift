import AudioToolbox
import CoreAudio
import Foundation
import PauseMicCore

final class SystemVolume: VolumeOutput {
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private func address(_ selector: AudioObjectPropertySelector, output: Bool = true) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
            mScope: output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }
    private func uint(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, output: Bool = true) throws -> UInt32 {
        var property = address(selector, output: output), value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value) == noErr else { throw VolumeFailure.read }
        return value
    }
    private func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var property = address(selector, output: false)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value) == noErr, let value else { throw VolumeFailure.read }
        return value.takeRetainedValue() as String
    }
    private func writable(_ device: AudioDeviceID, _ selector: UInt32) -> Bool {
        var property = address(selector), settable = DarwinBoolean(false)
        return AudioObjectHasProperty(device, &property) &&
            AudioObjectIsPropertySettable(device, &property, &settable) == noErr && settable.boolValue
    }
    private func device(uid: String) throws -> AudioDeviceID? {
        // UID lookup also allows a disconnected device to reconnect under a new numeric object ID.
        var property = address(kAudioHardwarePropertyTranslateUIDToDevice, output: false)
        var value: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let uidString = uid as CFString
        var qualifier = Unmanaged.passUnretained(uidString)
        let result = withExtendedLifetime(uidString) {
            AudioObjectGetPropertyData(system, &property, UInt32(MemoryLayout<Unmanaged<CFString>>.size), &qualifier, &size, &value)
        }
        guard result == noErr else { throw VolumeFailure.read }
        return value == kAudioObjectUnknown ? nil : value
    }
    func currentOutput() throws -> OutputVolume? {
        let device = try uint(system, kAudioHardwarePropertyDefaultOutputDevice, output: false)
        guard device != kAudioObjectUnknown else { return nil }
        // Virtual main volume preserves relative channel balance on stereo devices.
        let choices = [kAudioDevicePropertyVolumeScalar, kAudioHardwareServiceDeviceProperty_VirtualMainVolume]
        guard let selector = choices.first(where: { writable(device, $0) }) else { throw VolumeFailure.unsupported }
        return try snapshot(device: device, selector: selector)
    }
    func read(uid: String, selector: UInt32) throws -> OutputVolume? {
        guard let device = try device(uid: uid) else { return nil }
        return try snapshot(device: device, selector: selector)
    }
    private func snapshot(device: AudioDeviceID, selector: UInt32) throws -> OutputVolume {
        guard [kAudioDevicePropertyVolumeScalar, kAudioHardwareServiceDeviceProperty_VirtualMainVolume].contains(selector),
              writable(device, selector) else { throw VolumeFailure.unsupported }
        var property = address(selector), volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &volume) == noErr,
              volume.isFinite, (0...1).contains(volume) else { throw VolumeFailure.read }
        var muteProperty = address(kAudioDevicePropertyMute)
        let muted: Bool? = AudioObjectHasProperty(device, &muteProperty) ? try uint(device, kAudioDevicePropertyMute) != 0 : nil
        return OutputVolume(uid: try string(device, kAudioDevicePropertyDeviceUID),
            name: try string(device, kAudioObjectPropertyName), selector: selector, volume: volume, muted: muted)
    }
    func setVolume(_ volume: Float, expected: OutputVolume) throws -> Bool {
        guard volume.isFinite, (0...1).contains(volume), let device = try device(uid: expected.uid),
              try snapshot(device: device, selector: expected.selector).matches(expected) else { return false }
        var property = address(expected.selector), value = volume
        guard AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr else {
            throw VolumeFailure.write
        }
        return true
    }
}
