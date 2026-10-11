import XCTest
@testable import PauseMicCore

final class FakeOutput: VolumeOutput {
    var selected = "speakers"
    var devices: [String: OutputVolume] = [:]
    var writes: [(String, Float)] = []
    var writeError = false
    var readError = false
    var unsupported = false
    var concurrentChange = false
    var beforeWrite: (() -> Void)?
    init() { add("speakers", volume: 0.65) }
    func add(_ uid: String, volume: Float, muted: Bool? = false) {
        devices[uid] = OutputVolume(uid: uid, name: uid, selector: 1, volume: volume, muted: muted)
    }
    func currentOutput() throws -> OutputVolume? {
        if unsupported { throw VolumeFailure.unsupported }; return try read(uid: selected, selector: 1)
    }
    func read(uid: String, selector: UInt32) throws -> OutputVolume? {
        if readError { throw VolumeFailure.read }; return devices[uid]
    }
    func setVolume(_ volume: Float, expected: OutputVolume) throws -> Bool {
        beforeWrite?()
        if writeError { throw VolumeFailure.write }
        if concurrentChange { add(expected.uid, volume: 0.3); return false }
        guard devices[expected.uid]?.matches(expected) == true else { return false }
        writes.append((expected.uid, volume)); devices[expected.uid] = expected.withVolume(volume); return true
    }
}

final class VolumeEngineTests: XCTestCase {
    func idle(_ engine: VolumeEngine, enabled: Bool = true, start: Double = 1) {
        engine.tick(microphoneActive: false, enabled: enabled, now: start)
        engine.tick(microphoneActive: false, enabled: enabled, now: start + 1.5)
    }
    func testZeroThenExactOriginalVolumeAfterStableIdle() {
        let output = FakeOutput(); let engine = VolumeEngine(output: output)
        engine.tick(microphoneActive: true, enabled: true, now: 0)
        XCTAssertEqual(output.devices["speakers"]?.volume, 0)
        engine.tick(microphoneActive: true, enabled: true, now: 1)
        XCTAssertEqual(output.writes.count, 1)
        engine.tick(microphoneActive: false, enabled: true, now: 2)
        engine.tick(microphoneActive: false, enabled: true, now: 3.4)
        XCTAssertEqual(output.devices["speakers"]?.volume, 0)
        engine.tick(microphoneActive: false, enabled: true, now: 3.5)
        XCTAssertEqual(output.devices["speakers"]?.volume, 0.65)
        XCTAssertEqual(engine.quietCount, 0)
    }
    func testOverlappingInputAndShortGapRestartDelay() {
        let output = FakeOutput(); let engine = VolumeEngine(output: output)
        engine.tick(microphoneActive: true, enabled: true, now: 0)
        engine.tick(microphoneActive: false, enabled: true, now: 1)
        engine.tick(microphoneActive: true, enabled: true, now: 2)
        engine.tick(microphoneActive: false, enabled: true, now: 3)
        engine.tick(microphoneActive: false, enabled: true, now: 4)
        XCTAssertEqual(output.devices["speakers"]?.volume, 0)
        engine.tick(microphoneActive: false, enabled: true, now: 4.5)
        XCTAssertEqual(output.devices["speakers"]?.volume, 0.65)
    }
    func testAlreadyZeroOrHardwareMutedIsUntouched() {
        for muted in [false, true] {
            let output = FakeOutput(); output.add("speakers", volume: muted ? 0.65 : 0, muted: muted)
            let original = output.devices["speakers"]
            let engine = VolumeEngine(output: output)
            engine.tick(microphoneActive: true, enabled: true, now: 0); idle(engine)
            XCTAssertEqual(output.writes.count, 0); XCTAssertEqual(output.devices["speakers"], original)
        }
    }
    func testManualVolumeOrMuteChangeWins() {
        for changeMute in [false, true] {
            let output = FakeOutput(); let engine = VolumeEngine(output: output)
            engine.tick(microphoneActive: true, enabled: true, now: 0)
            output.add("speakers", volume: changeMute ? 0 : 0.25, muted: changeMute)
            let manual = output.devices["speakers"]
            engine.tick(microphoneActive: true, enabled: true, now: 1); idle(engine, start: 2)
            XCTAssertEqual(output.writes.count, 1); XCTAssertEqual(output.devices["speakers"], manual)
            XCTAssertEqual(engine.quietCount, 0)
        }
    }
    func testOutputSwitchKeepsSeparateOriginalVolumes() {
        let output = FakeOutput(); output.add("headphones", volume: 0.4)
        let engine = VolumeEngine(output: output)
        engine.tick(microphoneActive: true, enabled: true, now: 0)
        output.selected = "headphones"
        engine.tick(microphoneActive: true, enabled: true, now: 1)
        XCTAssertEqual(engine.quietCount, 2)
        XCTAssertEqual(output.devices["headphones"]?.volume, 0)
        idle(engine, start: 2)
        XCTAssertEqual(output.devices["speakers"]?.volume, 0.65)
        XCTAssertEqual(output.devices["headphones"]?.volume, 0.4)
    }
    func testDisconnectedDeviceRetainsReceiptUntilReconnect() {
        let output = FakeOutput(); var journal: [VolumeReceipt] = []
        let engine = VolumeEngine(output: output, save: { journal = $0 })
        engine.tick(microphoneActive: true, enabled: true, now: 0)
        output.devices.removeValue(forKey: "speakers")
        idle(engine)
        XCTAssertEqual(engine.quietCount, 1); XCTAssertEqual(journal.count, 1)
        output.add("speakers", volume: 0)
        engine.tick(microphoneActive: false, enabled: true, now: 3)
        XCTAssertEqual(output.devices["speakers"]?.volume, 0.65); XCTAssertTrue(journal.isEmpty)
    }
    func testJournalIsSavedBeforeHardwareMutation() {
        let output = FakeOutput(); var journal: [VolumeReceipt] = []
        let engine = VolumeEngine(output: output, save: { journal = $0 })
        output.beforeWrite = { XCTAssertEqual(journal.first?.original.volume, 0.65) }
        engine.tick(microphoneActive: true, enabled: true, now: 0)
        XCTAssertEqual(journal.first?.quiet.volume, 0)
        output.beforeWrite = nil; idle(engine)
        XCTAssertTrue(journal.isEmpty)
    }
    func testJournalFailurePreventsNewMuting() {
        let output = FakeOutput(); let engine = VolumeEngine(output: output, save: { _ in throw VolumeFailure.journal })
        engine.tick(microphoneActive: true, enabled: true, now: 0)
        XCTAssertEqual(output.writes.count, 0); XCTAssertEqual(engine.quietCount, 0)
        guard case .journal = engine.failure else { return XCTFail("Missing journal failure") }
    }
    func testCrashRecoveryRestoresOnlyOwnedZeroVolume() {
        let output = FakeOutput(); let original = output.devices["speakers"]!
        let receipt = VolumeReceipt(original: original, quiet: original.withVolume(0))
        output.add("speakers", volume: 0)
        let engine = VolumeEngine(output: output, recovered: [receipt])
        engine.tick(microphoneActive: true, enabled: true, now: 0)
        XCTAssertEqual(output.writes.count, 0)
        idle(engine)
        XCTAssertEqual(output.devices["speakers"]?.volume, 0.65)
        output.add("speakers", volume: 0.2)
        let manualEngine = VolumeEngine(output: output, recovered: [receipt]); idle(manualEngine)
        XCTAssertEqual(output.devices["speakers"]?.volume, 0.2)
    }
    func testUnknownMicStateAndFinalRecheckPreventRestoration() {
        let output = FakeOutput(); let engine = VolumeEngine(output: output)
        engine.tick(microphoneActive: true, enabled: true, now: 0)
        engine.tick(microphoneActive: false, enabled: true, now: 1)
        engine.tick(microphoneActive: nil, enabled: true, now: 3)
        engine.tick(microphoneActive: false, enabled: true, now: 4)
        engine.tick(microphoneActive: false, enabled: true, now: 6, canRestore: { false })
        XCTAssertEqual(output.devices["speakers"]?.volume, 0)
        idle(engine, start: 7)
        XCTAssertEqual(output.devices["speakers"]?.volume, 0.65)
    }
    func testDisablingAndQuittingRestoreEvenDuringInput() {
        for quit in [false, true] {
            let output = FakeOutput(); let engine = VolumeEngine(output: output)
            engine.tick(microphoneActive: true, enabled: true, now: 0)
            if quit { engine.stop() } else { engine.tick(microphoneActive: true, enabled: false, now: 1) }
            XCTAssertEqual(output.devices["speakers"]?.volume, 0.65)
            XCTAssertEqual(engine.quietCount, 0)
        }
    }
    func testKeepQuietRelinquishesRestorationAndJournal() {
        let output = FakeOutput(); var journal: [VolumeReceipt] = []
        let engine = VolumeEngine(output: output, save: { journal = $0 })
        engine.tick(microphoneActive: true, enabled: true, now: 0)
        engine.keepQuiet(); engine.tick(microphoneActive: true, enabled: true, now: 1); idle(engine, start: 2)
        XCTAssertEqual(output.writes.count, 1); XCTAssertEqual(output.devices["speakers"]?.volume, 0)
        XCTAssertTrue(journal.isEmpty)
    }
    func testUnsupportedOutputAndWriteFailureAreReported() {
        let output = FakeOutput(); output.unsupported = true
        let engine = VolumeEngine(output: output)
        engine.tick(microphoneActive: true, enabled: true, now: 0)
        guard case .unsupported = engine.failure else { return XCTFail("Missing unsupported error") }
        XCTAssertEqual(output.writes.count, 0)
        output.unsupported = false; output.writeError = true; engine.retry()
        engine.tick(microphoneActive: true, enabled: true, now: 1)
        guard case .write = engine.failure else { return XCTFail("Missing write error") }
        output.writeError = false; idle(engine, start: 2)
        XCTAssertEqual(output.devices["speakers"]?.volume, 0.65)
    }
    func testRestoreReadOrWriteFailureRetainsRecoveryData() {
        let output = FakeOutput(); var journal: [VolumeReceipt] = []
        let engine = VolumeEngine(output: output, save: { journal = $0 })
        engine.tick(microphoneActive: true, enabled: true, now: 0)
        output.readError = true; idle(engine)
        XCTAssertEqual(engine.quietCount, 1); XCTAssertFalse(journal.isEmpty)
        output.readError = false; output.writeError = true
        engine.tick(microphoneActive: false, enabled: true, now: 3)
        XCTAssertEqual(engine.quietCount, 1)
        output.writeError = false
        engine.tick(microphoneActive: false, enabled: true, now: 4)
        XCTAssertEqual(output.devices["speakers"]?.volume, 0.65); XCTAssertTrue(journal.isEmpty)
    }
    func testConcurrentUserChangeAtSetterIsPreserved() {
        let output = FakeOutput(); let engine = VolumeEngine(output: output)
        engine.tick(microphoneActive: true, enabled: true, now: 0)
        engine.tick(microphoneActive: false, enabled: true, now: 1)
        output.concurrentChange = true
        engine.tick(microphoneActive: false, enabled: true, now: 3)
        XCTAssertEqual(output.devices["speakers"]?.volume, 0.3)
        XCTAssertEqual(engine.quietCount, 0)
    }
    func testInvalidRecoveryDataIsIgnored() {
        let output = FakeOutput(); let original = output.devices["speakers"]!.withVolume(2)
        let engine = VolumeEngine(output: output, recovered: [VolumeReceipt(original: original, quiet: original.withVolume(0))])
        XCTAssertEqual(engine.quietCount, 0)
    }
    func testDisabledModeAndAbsentOutputDoNotMutateVolume() {
        let output = FakeOutput(); let engine = VolumeEngine(output: output)
        engine.tick(microphoneActive: true, enabled: false, now: 0)
        output.devices.removeAll()
        engine.tick(microphoneActive: true, enabled: true, now: 1)
        XCTAssertTrue(output.writes.isEmpty)
    }
}
