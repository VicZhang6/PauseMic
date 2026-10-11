import Darwin
import Foundation

/// Prevent two copies of PauseMic from capturing each other's temporary zero volume.
final class InstanceLock {
    private var descriptor: Int32 = -1
    func acquire() -> Bool {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("com.hecara.PauseMic")
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { return false }
        descriptor = open(directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
        return descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0
    }
    deinit { if descriptor >= 0 { close(descriptor) } }
}
