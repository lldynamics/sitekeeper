import Foundation

actor DataStorePersistenceActor {
    private let storeURL: URL

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
        let snapshot: BackupSnapshot
        do {
            snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: data)
        } catch {
            throw LoadDecodeError(rawData: data)
        }
        return snapshot
    }

    func persist(snapshot: BackupSnapshot) throws {
        guard !Task.isCancelled else { return }
        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        guard !Task.isCancelled else { return }
        try data.write(to: storeURL, options: .atomic)
    }
}
