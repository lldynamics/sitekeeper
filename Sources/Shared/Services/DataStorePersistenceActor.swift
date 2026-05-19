import Foundation

actor DataStorePersistenceActor {
    private let storeURL: URL

    private static func recordIssue(
        _ event: String,
        details: [String: String] = [:],
        error: Error? = nil
    ) {
        StorageIssueLog.recordEvent(
            event,
            category: .dataStore,
            details: details,
            error: error
        )
    }

    struct LoadDecodeError: Error {
        let rawData: Data
    }

    init(storeURL: URL) {
        self.storeURL = storeURL
    }

    func loadSnapshot(primaryStoreURL: URL, legacyStoreURL: URL) throws -> BackupSnapshot? {
        let fileManager = FileManager.default
        let sourceURL: URL
        if fileManager.fileExists(atPath: primaryStoreURL.path) {
            sourceURL = primaryStoreURL
        } else if fileManager.fileExists(atPath: legacyStoreURL.path) {
            sourceURL = legacyStoreURL
        } else {
            return nil
        }

        let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        let snapshot: BackupSnapshot
        do {
            snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: data)
        } catch {
            throw LoadDecodeError(rawData: data)
        }

        if sourceURL == legacyStoreURL {
            do {
                try data.write(to: primaryStoreURL, options: .atomic)
                do {
                    _ = try FileOps.removeIfExists(
                        at: legacyStoreURL,
                        context: .init(
                            event: "datastore.legacy_store_cleanup",
                            category: .dataStore,
                            source: "DataStore.loadSnapshotFromDisk"
                        )
                    )
                } catch {
                    Self.recordIssue(
                        "datastore.legacy_store_cleanup_failed",
                        details: [
                            "file": legacyStoreURL.lastPathComponent,
                            "target": primaryStoreURL.lastPathComponent
                        ],
                        error: error
                    )
                }
            } catch {
                Self.recordIssue(
                    "datastore.legacy_store_migration_failed",
                    details: [
                        "source": legacyStoreURL.lastPathComponent,
                        "target": primaryStoreURL.lastPathComponent
                    ],
                    error: error
                )
            }
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
