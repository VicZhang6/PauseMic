import Foundation

public struct OutputVolume: Codable, Equatable {
    public let uid: String
    public let name: String
    public let selector: UInt32
    public let volume: Float
    public let muted: Bool?
    public init(uid: String, name: String, selector: UInt32, volume: Float, muted: Bool?) {
        self.uid = uid; self.name = name; self.selector = selector; self.volume = volume; self.muted = muted
    }
    public var valid: Bool { !uid.isEmpty && volume.isFinite && (0...1).contains(volume) }
    public func withVolume(_ value: Float) -> OutputVolume {
        OutputVolume(uid: uid, name: name, selector: selector, volume: value, muted: muted)
    }
    public func matches(_ other: OutputVolume) -> Bool {
        uid == other.uid && selector == other.selector && abs(volume - other.volume) < 0.0001 && muted == other.muted
    }
}

public struct VolumeReceipt: Codable {
    public let original: OutputVolume
    public let quiet: OutputVolume
    public init(original: OutputVolume, quiet: OutputVolume) { self.original = original; self.quiet = quiet }
    public var valid: Bool {
        original.valid && quiet.valid && original.uid == quiet.uid && original.selector == quiet.selector &&
        original.volume > 0.0001 && quiet.volume == 0
    }
}

public enum VolumeFailure: Error { case unsupported, unavailable, read, write, journal }

public protocol VolumeOutput: AnyObject {
    func currentOutput() throws -> OutputVolume?
    /// nil means the device is disconnected. Resolve by UID, never by a stale numeric device ID.
    func read(uid: String, selector: UInt32) throws -> OutputVolume?
    /// Re-check the exact expected state before changing volume. Never change the hardware mute flag.
    func setVolume(_ volume: Float, expected: OutputVolume) throws -> Bool
}

/// All calls run on one serial queue. Persist the original volume before modifying hardware.
public final class VolumeEngine {
    private let output: VolumeOutput
    private let save: ([VolumeReceipt]) throws -> Void
    private var receipts: [String: VolumeReceipt] = [:]
    private var attempted: Set<String> = []
    private var episode = false
    private var idleSince: TimeInterval?
    private let delay: TimeInterval
    public private(set) var failure: VolumeFailure?
    public var quietCount: Int { receipts.count }
    public var savedVolume: Float? { receipts.values.first?.original.volume }

    public init(output: VolumeOutput, restoreDelay: TimeInterval = 1.5, recovered: [VolumeReceipt] = [],
                save: @escaping ([VolumeReceipt]) throws -> Void = { _ in }) {
        self.output = output; self.delay = restoreDelay; self.save = save
        for receipt in recovered where receipt.valid { receipts[receipt.original.uid] = receipt }
        attempted = Set(receipts.keys); episode = !receipts.isEmpty
    }
    private func persist() throws { try save(Array(receipts.values)) }
    private func recordFailure(_ error: Error) { failure = (error as? VolumeFailure) ?? .write }
    private func remove(_ uid: String) {
        receipts.removeValue(forKey: uid)
        do { try persist() } catch { failure = .journal }
    }
    private func reconcile() {
        for (uid, receipt) in receipts {
            do {
                guard let current = try output.read(uid: uid, selector: receipt.quiet.selector) else { continue }
                // User volume/mute changes take precedence; do not set it back to zero in this episode.
                if !current.matches(receipt.quiet) { remove(uid) }
            } catch { recordFailure(error) }
        }
    }
    public func tick(microphoneActive: Bool?, enabled: Bool, now: TimeInterval,
                     canRestore: () -> Bool = { true }) {
        failure = nil
        reconcile()
        if !enabled { restoreOwned(); attempted.removeAll(); episode = !receipts.isEmpty; idleSince = nil; return }
        guard let active = microphoneActive else { idleSince = nil; return }
        if active {
            episode = true; idleSince = nil
            do {
                if let before = try output.currentOutput(), before.valid, !attempted.contains(before.uid) {
                    attempted.insert(before.uid)
                    if before.volume > 0.0001 && before.muted != true {
                        let receipt = VolumeReceipt(original: before, quiet: before.withVolume(0))
                        receipts[before.uid] = receipt
                        // No volume mutation if the recovery journal cannot be written.
                        do { try persist() }
                        catch { receipts.removeValue(forKey: before.uid); throw VolumeFailure.journal }
                        if try output.setVolume(0, expected: before) {
                            if let after = try output.read(uid: before.uid, selector: before.selector), after.volume == 0 {
                                receipts[before.uid] = VolumeReceipt(original: before, quiet: after)
                                try persist()
                            }
                        } else { remove(before.uid) }
                    }
                }
            } catch { recordFailure(error) }
            return
        }
        if idleSince == nil { idleSince = now }
        guard episode, now - idleSince! >= delay else { return }
        guard canRestore() else { idleSince = nil; return }
        restoreOwned(canRestore: canRestore)
        if receipts.isEmpty { attempted.removeAll(); episode = false; idleSince = nil }
    }
    private func restoreOwned(canRestore: () -> Bool = { true }) {
        for (uid, receipt) in receipts {
            guard canRestore() else { idleSince = nil; return }
            do {
                guard let current = try output.read(uid: uid, selector: receipt.quiet.selector) else { continue }
                guard current.matches(receipt.quiet) else { remove(uid); continue }
                if try output.setVolume(receipt.original.volume, expected: current) { remove(uid) }
                else { remove(uid) } // Concurrent manual change: relinquish ownership.
            } catch { recordFailure(error) }
        }
    }
    /// Explicit user intent: disabling or quitting restores any volume still owned by PauseMic.
    public func stop() { failure = nil; reconcile(); restoreOwned() }
    public func keepQuiet() {
        for uid in receipts.keys { attempted.insert(uid) }
        receipts.removeAll()
        do { try persist() } catch { failure = .journal }
    }
    public func retry() { attempted = Set(receipts.keys) }
}
