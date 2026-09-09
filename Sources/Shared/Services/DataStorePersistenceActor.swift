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
        // A retry may encounter a replaced, missing, or unreadable file.
        // Only a successful load can establish a valid no-op cache.
        lastPersistedData = nil
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
        lastPersistedData = data
        return snapshot
    }

    @discardableResult
    func persist(snapshot: BackupSnapshot, preservingExistingFile: Bool = false) throws -> Bool {
        try Task.checkCancellation()
        let encoder = JSONEncoder()
        // Stable key ordering makes byte equality a reliable no-op detector.
        // JSONEncoder otherwise may emit keyed containers in a different order.
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try Task.checkCancellation()
        if !preservingExistingFile, data == lastPersistedData,
           FileManager.default.fileExists(atPath: storeURL.path) {
            // Cached equality alone cannot prove the target still contains these bytes.
            let currentData = try Data(contentsOf: storeURL, options: [.mappedIfSafe])
            if currentData == data { return false }
        }
        if preservingExistingFile, FileManager.default.fileExists(atPath: storeURL.path) {
            let preservedURL = storeURL.deletingLastPathComponent()
                .appendingPathComponent("sitekeeper_before_recovery_\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: storeURL, to: preservedURL)
            BackupArchiveSecurity.applyDataProtection(to: preservedURL)
        }
        try data.write(to: storeURL, options: .atomic)
        BackupArchiveSecurity.applyDataProtection(to: storeURL)
        lastPersistedData = data
        return true
    }
}
