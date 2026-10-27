import Foundation

actor DataStorePersistenceActor {
    private let storeURL: URL
    private var lastPersistedData: Data?
    private var sectionEncoder = SnapshotSectionEncoder()
    /// Reuse a successful schema check only while the same file identity remains.
    private var storeMayHoldSchema2: Bool?
    private var schemaCheckedFileIdentity: FileIdentity?
    private let writeMigrationBackup: @Sendable (Data, URL) throws -> Void
    private let writeDateProvenance: @Sendable (Data, URL) throws -> Void
    private let now: @Sendable () -> Date
    /// Entries the audit file should hold. `auditFileIsCurrent` is false until they are written.
    private var auditEntries: [DateProvenanceAuditFile.Entry] = []
    private var auditFileIsCurrent = false
    private var auditPreservationFailed = false

    struct LoadDecodeError: Error {
        let rawData: Data
    }

    init(
        storeURL: URL,
        writeMigrationBackup: @escaping @Sendable (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: .atomic)
        },
        writeDateProvenance: @escaping @Sendable (Data, URL) throws -> Void = {
            try $0.write(to: $1, options: .atomic)
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storeURL = storeURL
        self.writeMigrationBackup = writeMigrationBackup
        self.writeDateProvenance = writeDateProvenance
        self.now = now
    }

    private var auditURL: URL { DateProvenanceAuditFile.fileURL(forStore: storeURL) }

    func loadSnapshot() throws -> BackupSnapshot? {
        // A retry may encounter a replaced, missing, or unreadable file.
        // Only a successful load can establish a valid no-op cache.
        lastPersistedData = nil
        sectionEncoder = SnapshotSectionEncoder()
        storeMayHoldSchema2 = nil
        schemaCheckedFileIdentity = nil
        // Read first so a restore after a failed load still merges with the existing audit.
        let fileEntries = loadAuditEntries()
        auditEntries = fileEntries
        auditFileIsCurrent = true
        try BackupArchiveRestoreJournal.recoverPending(storeURL: storeURL)
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            storeMayHoldSchema2 = false
            return nil
        }

        let data = try Data(contentsOf: storeURL, options: [.mappedIfSafe])
        var snapshot: BackupSnapshot
        do {
            snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: data)
        } catch {
            throw LoadDecodeError(rawData: data)
        }
        lastPersistedData = data
        // Loading never writes. The next save stores the reconciled audit and drops the
        // copy that older v3 stores embedded in sitekeeper.json.
        if !fileEntries.isEmpty || !snapshot.legacyDateProvenance.isEmpty {
            auditEntries = DateProvenanceAuditFile.reconciled(
                file: fileEntries,
                inline: snapshot.legacyDateProvenance,
                liveRecordIDs: snapshot.liveRecordIDs,
                now: now()
            )
        }
        auditFileIsCurrent = auditEntries == fileEntries
        snapshot.legacyDateProvenance = auditEntries.map(\.provenance)
        return snapshot
    }

    @discardableResult
    func persist(snapshot: BackupSnapshot, versions: [String: UInt64]? = nil, preservingExistingFile: Bool = false) throws -> Bool {
        try Task.checkCancellation()
        var storeSnapshot = snapshot
        // Keep the audit inline only while its own file cannot be written, so it is never lost.
        if persistAuditIfNeeded(snapshot.legacyDateProvenance) {
            storeSnapshot.legacyDateProvenance = []
        }
        var nextEncoder = sectionEncoder
        let data: Data
        if let versions {
            data = try nextEncoder.encode(storeSnapshot, versions: versions)
        } else {
            nextEncoder = SnapshotSectionEncoder()
            data = try BackupArchiveRestoreJournal.encodeMetadata(storeSnapshot)
        }
        let didWrite = try persistPreparedBackup(data: data, preservingExistingFile: preservingExistingFile)
        sectionEncoder = nextEncoder
        return didWrite
    }

    /// A restore adds `dateProvenance` to the audit instead of replacing it: until the restore
    /// finalizes, a rollback on the next launch can still need the previous entries. Entries
    /// for records that stay absent age out; the next ordinary save writes the live list and
    /// moves any copy embedded in the prepared bytes out of the store.
    @discardableResult
    func persistPreparedBackup(
        data: Data,
        preservingExistingFile: Bool = false,
        dateProvenance: [LegacyDateProvenance]? = nil
    ) throws -> Bool {
        try Task.checkCancellation()
        // Prepared restore bytes have no relation to previous live-store generations.
        sectionEncoder = SnapshotSectionEncoder()
        if let dateProvenance {
            var seen = Set(auditEntries.map(\.provenance))
            persistAuditIfNeeded(auditEntries.map(\.provenance) + dateProvenance.filter { seen.insert($0).inserted })
        }
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
        try preserveSchema2StoreIfNeeded()
        try data.write(to: storeURL, options: .atomic)
        BackupArchiveSecurity.applyDataProtection(to: storeURL)
        lastPersistedData = data
        storeMayHoldSchema2 = false
        schemaCheckedFileIdentity = try? FileIdentity(url: storeURL)
        return true
    }

    /// Preserve the exact v2 bytes before the first v3 write. A copy failure blocks saving.
    /// Recheck a replaced or changed file; ordinary autosaves only inspect metadata.
    private func preserveSchema2StoreIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            storeMayHoldSchema2 = false
            schemaCheckedFileIdentity = nil
            return
        }
        let identity = try FileIdentity(url: storeURL)
        if storeMayHoldSchema2 == false, schemaCheckedFileIdentity == identity { return }
        let previous = try Data(contentsOf: storeURL)
        if let header = try? JSONDecoder().decode(BackupSchemaHeader.self, from: previous),
           header.schemaVersion == 2 {
            let preservedURL = storeURL.deletingLastPathComponent()
                .appendingPathComponent("sitekeeper_before_schema3_\(UUID().uuidString).json")
            try writeMigrationBackup(previous, preservedURL)
            BackupArchiveSecurity.applyDataProtection(to: preservedURL)
        }
        storeMayHoldSchema2 = false
        schemaCheckedFileIdentity = identity
    }

    private struct FileIdentity: Equatable {
        let inode: UInt64
        let bytes: UInt64
        let modifiedAt: Date

        init(url: URL) throws {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let inode = attributes[.systemFileNumber] as? NSNumber,
                  let bytes = attributes[.size] as? NSNumber,
                  let modifiedAt = attributes[.modificationDate] as? Date else {
                throw FileStorageError.readFailed(url.lastPathComponent)
            }
            self.inode = inode.uint64Value
            self.bytes = bytes.uint64Value
            self.modifiedAt = modifiedAt
        }
    }

    /// An unreadable audit is set aside rather than overwritten; business data never waits on it.
    private func loadAuditEntries() -> [DateProvenanceAuditFile.Entry] {
        auditPreservationFailed = false
        guard FileManager.default.fileExists(atPath: auditURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: auditURL)
            return try JSONDecoder().decode(DateProvenanceAuditFile.self, from: data).entries
        } catch {
            let preservedName = "sitekeeper_date_provenance_unreadable_\(UUID().uuidString).json"
            let preservedURL = auditURL.deletingLastPathComponent().appendingPathComponent(preservedName)
            do {
                try FileManager.default.moveItem(at: auditURL, to: preservedURL)
            } catch {
                auditPreservationFailed = true
                StorageIssueLog.recordEvent(
                    "datastore.date_provenance_preserve_failed",
                    category: .dataStore,
                    details: ["file": preservedName],
                    error: error
                )
            }
            StorageIssueLog.recordEvent(
                "datastore.date_provenance_unreadable",
                category: .dataStore,
                details: ["file": preservedName],
                error: error
            )
            return []
        }
    }

    /// Returns true when the audit file holds exactly these entries.
    @discardableResult
    private func persistAuditIfNeeded(_ provenance: [LegacyDateProvenance]) -> Bool {
        // Never overwrite unreadable original bytes if setting them aside failed.
        guard !auditPreservationFailed else { return false }
        var missingSince: [LegacyDateProvenance: Date] = [:]
        for entry in auditEntries {
            if let date = entry.missingSince { missingSince[entry.provenance] = date }
        }
        let entries = provenance.map {
            DateProvenanceAuditFile.Entry(provenance: $0, missingSince: missingSince[$0])
        }
        if auditFileIsCurrent, entries == auditEntries,
           FileManager.default.fileExists(atPath: auditURL.path) {
            // The file can be removed or replaced outside this actor. Only drop the inline
            // copy when the current bytes still decode to exactly the expected audit.
            guard let data = try? Data(contentsOf: auditURL),
                  let current = try? JSONDecoder().decode(DateProvenanceAuditFile.self, from: data),
                  current == DateProvenanceAuditFile(entries: entries) else { return false }
            return true
        }
        if entries.isEmpty, !FileManager.default.fileExists(atPath: auditURL.path) {
            auditEntries = []
            auditFileIsCurrent = true
            return true
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(DateProvenanceAuditFile(entries: entries))
            try writeDateProvenance(data, auditURL)
            BackupArchiveSecurity.applyDataProtection(to: auditURL)
            auditEntries = entries
            auditFileIsCurrent = true
            return true
        } catch {
            StorageIssueLog.recordEvent(
                "datastore.date_provenance_write_failed",
                category: .dataStore,
                details: ["entries": "\(entries.count)"],
                error: error
            )
            return false
        }
    }
}
