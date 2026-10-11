import Foundation
import PauseMicCore

struct VolumeStatus {
    let microphone: MicrophoneSample
    let quietCount: Int
    let savedVolume: Float?
    let failure: VolumeFailure?
}

final class VolumeCoordinator {
    private let queue = DispatchQueue(label: "com.hecara.PauseMic.volume", qos: .userInitiated)
    private let journal = VolumeJournal()
    private lazy var engine = VolumeEngine(output: SystemVolume(), recovered: journal.load(), save: journal.save)
    private let monitor = MicrophoneMonitor()
    private var timer: DispatchSourceTimer?
    private var enabled = true
    var onStatus: ((VolumeStatus) -> Void)?

    func start(enabled: Bool) {
        queue.async { [self] in
            self.enabled = enabled
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: .milliseconds(300), leeway: .milliseconds(50))
            timer.setEventHandler { [weak self] in self?.poll() }
            self.timer = timer; timer.resume()
        }
    }
    func setEnabled(_ value: Bool) {
        queue.async {
            if value && !self.enabled { self.engine.retry() }
            self.enabled = value; self.poll()
        }
    }
    func keepQuiet() { queue.async { self.engine.keepQuiet(); self.publish(self.monitor.sample()) } }
    func stop(completion: @escaping () -> Void) {
        queue.async {
            self.timer?.cancel(); self.timer = nil
            self.engine.stop()
            DispatchQueue.main.async(execute: completion)
        }
    }
    private func poll() {
        let sample = monitor.sample()
        engine.tick(microphoneActive: sample.active, enabled: enabled, now: ProcessInfo.processInfo.systemUptime,
                    canRestore: { self.monitor.sample().active == false })
        publish(sample)
    }
    private func publish(_ sample: MicrophoneSample) {
        let status = VolumeStatus(microphone: sample, quietCount: engine.quietCount,
                                 savedVolume: engine.savedVolume, failure: engine.failure)
        DispatchQueue.main.async { [weak self] in self?.onStatus?(status) }
    }
}
