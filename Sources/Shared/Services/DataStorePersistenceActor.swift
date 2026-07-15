import Foundation

actor DataStorePersistenceActor {
    private let storeURL: URL
    private var lastPersistedData: Data?

    struct LoadDecodeError: Error {
        let rawData: Data
    }

    init(storeURL: URL) {
        self.storeURL = storeURL
    }

    func loadSnapshot() throws -> BackupSnapshot? {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: storeURL, options: [.mappedIfSafe])
        lastPersistedData = data
        let snapshot: BackupSnapshot
        do {
            snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: data)
        } catch {
            throw LoadDecodeError(rawData: data)
        }
        return snapshot
    }

    @discardableResult
    func persist(snapshot: BackupSnapshot) throws -> Bool {
        guard !Task.isCancelled else { return false }
        let encoder = JSONEncoder()
        // Stable key ordering makes byte equality a reliable no-op detector.
        // JSONEncoder otherwise may emit keyed containers in a different order.
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        guard !Task.isCancelled else { return false }
        guard data != lastPersistedData else { return false }
        try data.write(to: storeURL, options: .atomic)
        BackupArchiveSecurity.applyDataProtection(to: storeURL)
        lastPersistedData = data
        return true
    }
}
