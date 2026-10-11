import XCTest
import PauseMicCore
@testable import PauseMic

final class NativeTests: XCTestCase {
    func testNativeInputStatusDoesNotRequireRecording() throws {
        let sample = MicrophoneMonitor().sample()
        guard sample.active != nil else { throw XCTSkip("Core Audio input status unavailable on this host") }
        XCTAssertGreaterThanOrEqual(sample.processCount, 0)
        XCTAssertEqual(sample.active, sample.processCount > 0)
    }
    func testNativeOutputUIDRoundTripWithoutChangingVolume() throws {
        let controller = SystemVolume()
        let current: OutputVolume
        do {
            guard let value = try controller.currentOutput() else { throw XCTSkip("No default output on this host") }
            current = value
        } catch VolumeFailure.unsupported { throw XCTSkip("Default output has no software volume control") }
        XCTAssertTrue(current.valid)
        let again = try controller.read(uid: current.uid, selector: current.selector)
        XCTAssertEqual(again?.uid, current.uid)
        XCTAssertEqual(again?.selector, current.selector)
        XCTAssertNotNil(again)
    }
    func testRealVolumeRoundTrip() throws {
        guard ProcessInfo.processInfo.environment["PAUSEMIC_HARDWARE_TEST"] == "1" else {
            throw XCTSkip("Opt-in test briefly sets actual system volume to zero and restores it")
        }
        let controller = SystemVolume()
        guard let original = try controller.currentOutput(), original.volume > 0, original.muted != true else {
            throw XCTSkip("Need an adjustable, nonzero, unmuted default output")
        }
        var quiet: OutputVolume?
        defer {
            // Always try to restore on assertion/throw; the setter protects manual changes.
            if let expected = quiet { _ = try? controller.setVolume(original.volume, expected: expected) }
        }
        XCTAssertTrue(try controller.setVolume(0, expected: original))
        quiet = try controller.read(uid: original.uid, selector: original.selector)
        XCTAssertEqual(quiet?.volume, 0)
        guard let muted = quiet else { return XCTFail("Output disappeared") }
        XCTAssertTrue(try controller.setVolume(original.volume, expected: muted))
        let restored = try controller.read(uid: original.uid, selector: original.selector)
        XCTAssertEqual(restored?.volume ?? -1, original.volume, accuracy: 0.0001)
        XCTAssertEqual(restored?.muted, original.muted)
        quiet = nil
    }
}
