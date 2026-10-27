import Foundation

/// Drafts are independent of production attachments and are never swept by photo cleanup.
/// Each write replaces one complete metadata file; photo blobs are committed first.
struct BusinessDraftStore {
    enum Key: Equatable {
        case daily(projectID: UUID?)
        case dailyEdit(UUID)
        case finance(projectID: UUID)
        case financeEdit(UUID)
        case todo(projectID: UUID?)
        case todoEdit(UUID)

        var fileName: String {
            switch self {
            case .daily(let id): return "daily-\(id?.uuidString ?? "unassigned")"
            case .dailyEdit(let id): return "daily-edit-\(id.uuidString)"
            case .finance(let id): return "finance-\(id.uuidString)"
            case .financeEdit(let id): return "finance-edit-\(id.uuidString)"
            case .todo(let id): return "todo-\(id?.uuidString ?? "unassigned")"
            case .todoEdit(let id): return "todo-edit-\(id.uuidString)"
            }
        }
    }

    static func scoped(to storeURL: URL) -> BusinessDraftStore {
        BusinessDraftStore(root: storeURL.deletingLastPathComponent().appendingPathComponent("BusinessDrafts", isDirectory: true))
    }

    func removeAll() throws {
        _ = try FileOps.removeIfExists(at: root, context: .init(event: "business_draft.clear_all", category: .fileStorage, source: "BusinessDraftStore.removeAll"))
    }

    let root: URL

    private func directory(_ key: Key) -> URL { root.appendingPathComponent(key.fileName, isDirectory: true) }
    private func metadata(_ key: Key) -> URL { directory(key).appendingPathComponent("draft.json") }

    func load<Value: Decodable>(_ type: Value.Type, key: Key) throws -> Value? {
        let url = metadata(key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    func save<Value: Encodable>(_ value: Value, key: Key) throws {
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at: directory(key), withIntermediateDirectories: true)
        try data.write(to: metadata(key), options: .atomic)
        BackupArchiveSecurity.applyDataProtection(to: metadata(key))
    }

    func savePhoto(_ data: Data, id: UUID, key: Key) throws {
        try FileManager.default.createDirectory(at: directory(key), withIntermediateDirectories: true)
        let url = directory(key).appendingPathComponent(id.uuidString + ".photo")
        // PhotoDraft IDs identify immutable imported bytes. Notes/tags live in metadata.
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
            BackupArchiveSecurity.applyDataProtection(to: url)
        }
    }

    func registerPhotoAttempt(id: UUID, count: Int, key: Key) throws {
        let names = (0..<count).map { index in id.uuidString + (index == 0 ? "" : "-\(index)") + ".jpg" }
        let previous = try pendingPhotoFiles(key: key)
        try FileManager.default.createDirectory(at: directory(key), withIntermediateDirectories: true)
        let url = directory(key).appendingPathComponent("pending-photos.json")
        try JSONEncoder().encode(Array(Set(previous + names)).sorted()).write(to: url, options: .atomic)
        BackupArchiveSecurity.applyDataProtection(to: url)
    }

    func pendingPhotoFiles(key: Key) throws -> [String] {
        let url = directory(key).appendingPathComponent("pending-photos.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
    }

    func photo(id: UUID, key: Key) throws -> Data {
        try Data(contentsOf: directory(key).appendingPathComponent(id.uuidString + ".photo"))
    }

    @MainActor
    func complete(key: Key, persist: () async throws -> Void) async throws {
        try await persist()
        try discard(key: key)
    }

    static func fingerprint<Value: Encodable>(_ value: Value) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(value)
    }

    func discard(key: Key) throws {
        let url = directory(key)
        _ = try FileOps.removeIfExists(at: url, context: .init(event: "business_draft.discard", category: .fileStorage, source: "BusinessDraftStore.discard"))
    }
}

extension BusinessDraftStore {
    /// Commit a new record once. A retained draft can never overwrite a saved record.
    @MainActor
    func commitNewFinancialRecord(
        _ record: ProjectFinancialRecord,
        in store: DataStore,
        persist: (() async throws -> Void)? = nil
    ) async throws {
        await store.awaitInitialLoad()
        guard store.loadState == .ready, !store.isApplyingBackup,
              !store.projectFinancialRecords.contains(where: { $0.id == record.id }) else {
            throw DataStore.PersistenceBlockedError(message: AppLocalization.string("原记录已变化，草稿仍保留。请关闭后重新打开并核对。"))
        }
        var committed = false
        store.appendProjectFinancialRecord(record)
        do {
            try await complete(key: .finance(projectID: record.projectId)) {
                if let persist { try await persist() } else { try await store.flushSaveOrThrow() }
                committed = true
            }
        } catch {
            if !committed,
               let live = store.projectFinancialRecords.first(where: { $0.id == record.id }),
               Self.fingerprint(live) == Self.fingerprint(record) {
                store.removeProjectFinancialRecords(ids: [record.id])
            }
            throw error
        }
    }
}

extension BusinessDraftStore {
    @MainActor
    func commitNewDailyLog(
        _ log: DailyLog,
        in store: DataStore,
        persist: (() async throws -> Void)? = nil
    ) async throws {
        await store.awaitInitialLoad()
        guard store.loadState == .ready, !store.isApplyingBackup,
              !store.dailyLogs.contains(where: { $0.id == log.id }) else {
            throw DataStore.PersistenceBlockedError(message: AppLocalization.string("原记录已变化，草稿仍保留。请关闭后重新打开并核对。"))
        }
        var committed = false
        store.insertDailyLogAtTop(log)
        do {
            try await complete(key: .daily(projectID: log.projectId)) {
                if let persist { try await persist() } else { try await store.flushSaveOrThrow() }
                committed = true
            }
        } catch {
            if !committed, let live = store.dailyLogs.first(where: { $0.id == log.id }),
               Self.fingerprint(live) == Self.fingerprint(log) {
                store.removeDailyLogs(ids: [log.id])
            }
            throw error
        }
    }
}
