import Foundation
import PauseMicCore

final class VolumeJournal {
    private let url: URL
    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        url = base.appendingPathComponent("com.hecara.PauseMic/volume-recovery.json")
    }
    func load() -> [VolumeReceipt] {
        guard let data = try? Data(contentsOf: url), let receipts = try? JSONDecoder().decode([VolumeReceipt].self, from: data) else { return [] }
        return receipts.filter(\.valid)
    }
    func save(_ receipts: [VolumeReceipt]) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(receipts).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw VolumeFailure.journal }
    }
}
