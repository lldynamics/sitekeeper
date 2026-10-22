import Foundation

actor DataStorePersistenceActor {
    private let storeURL: URL
    private var lastPersistedData: Data?
    private let writeMigrationBackup: @Sendable (Data, URL) throws -> Void

    struct LoadDecodeError: Error {
        let rawData: Data
    }

    init(storeURL: URL, writeMigrationBackup: @escaping @Sendable (Data, URL) throws -> Void = {
        try $0.write(to: $1, options: .atomic)
    }) {
        self.storeURL = storeURL
        self.writeMigrationBackup = writeMigrationBackup
    }

    func loadSnapshot() throws -> BackupSnapshot? {
        // A retry may encounter a replaced, missing, or unreadable file.
        // Only a successful load can establish a valid no-op cache.
        lastPersistedData = nil
        try BackupArchiveRestoreJournal.recoverPending(storeURL: storeURL)
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
        let data = try BackupArchiveRestoreJournal.encodeMetadata(snapshot)
        return try persistPreparedBackup(data: data, preservingExistingFile: preservingExistingFile)
    }

    @discardableResult
    func persistPreparedBackup(data: Data, preservingExistingFile: Bool = false) throws -> Bool {
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
        // Preserve the exact v2 bytes before the first v3 write. A copy failure blocks saving.
        if FileManager.default.fileExists(atPath: storeURL.path) {
            let previous = try Data(contentsOf: storeURL)
            if let header = try? JSONDecoder().decode(BackupSchemaHeader.self, from: previous),
               header.schemaVersion == 2 {
                let preservedURL = storeURL.deletingLastPathComponent()
                    .appendingPathComponent("sitekeeper_before_schema3_\(UUID().uuidString).json")
                try writeMigrationBackup(previous, preservedURL)
                BackupArchiveSecurity.applyDataProtection(to: preservedURL)
            }
        }
        try data.write(to: storeURL, options: .atomic)
        BackupArchiveSecurity.applyDataProtection(to: storeURL)
        lastPersistedData = data
        return true
    }
}
