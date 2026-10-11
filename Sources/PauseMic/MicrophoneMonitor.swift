import CoreAudio
import Foundation

struct MicrophoneSample {
    let active: Bool?
    let processCount: Int
}

struct MicrophoneMonitor {
    func sample() -> MicrophoneSample {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            return MicrophoneSample(active: nil, processCount: 0)
        }
        guard size > 0 else { return MicrophoneSample(active: false, processCount: 0) }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let result = processes.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!)
        }
        guard result == noErr else { return MicrophoneSample(active: nil, processCount: 0) }
        var count = 0
        var failed = false
        for process in processes.prefix(Int(size) / MemoryLayout<AudioObjectID>.size) {
            var input = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var length = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(process, &input, 0, nil, &length, &running) == noErr {
                if running != 0 { count += 1 }
            } else { failed = true }
        }
        return MicrophoneSample(active: count > 0 ? true : (failed ? nil : false), processCount: count)
    }
}
