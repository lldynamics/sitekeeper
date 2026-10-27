import Foundation

struct StorageCleanupTrashBatch: Identifiable, Codable, Sendable {
    let id: UUID
    let summary: String
    let createdAt: Date
    let expiresAt: Date
    let snapshot: StorageCleanupUndoSnapshot
    let files: [StorageCleanupTrashFile]

    var fileCount: Int { files.count }
}

struct StorageCleanupTrashFile: Identifiable, Codable, Sendable {
    let id: UUID
    let kind: StorageCleanupTrashFileKind
    let originalFileName: String
    let trashedFileName: String
}

enum StorageCleanupTrashFileKind: String, Codable, Sendable {
    case photoOriginal
    case photoThumbnail
    case drawing
    case quickNoteAttachment
    case projectDocument

    func originalURL(for fileName: String) -> URL {
        switch self {
        case .photoOriginal:
            return PhotoStorage.fileURL(for: fileName)
        case .photoThumbnail:
            return PhotoStorage.thumbnailStorageURL(for: fileName)
        case .drawing:
            return DrawingStorage.fileURL(for: fileName)
        case .quickNoteAttachment:
            return QuickNoteAttachmentStorage.fileURL(for: fileName)
        case .projectDocument:
            return ProjectDocumentStorage.fileURL(for: fileName)
        }
    }

    func invalidateCache(for fileName: String) {
        switch self {
        case .photoOriginal, .photoThumbnail:
            PhotoCache.shared.invalidate(fileName: fileName)
        case .drawing, .quickNoteAttachment, .projectDocument:
            break
        }
    }
}

enum StorageCleanupTrashError: LocalizedError {
    case rootUnavailable
    case manifestWriteFailed
    case manifestReadFailed
    case noFilesToTrash
    case moveToTrashFailed(String)
    case restoreFailed(String)
    case permanentDeleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .rootUnavailable:
            return AppLocalization.string("无法访问清理回收站目录。")
        case .manifestWriteFailed:
            return AppLocalization.string("无法保存清理回收站清单。")
        case .manifestReadFailed:
            return AppLocalization.string("清理回收站清单读取失败，已停止修改并保留原文件。请先恢复清单后重试。")
        case .noFilesToTrash:
            return AppLocalization.string("没有可移入清理回收站的文件。")
        case let .moveToTrashFailed(fileName):
            return String(format: AppLocalization.string("无法移入清理回收站：%@"), fileName)
        case let .restoreFailed(fileName):
            return String(format: AppLocalization.string("无法恢复清理回收站文件：%@"), fileName)
        case let .permanentDeleteFailed(fileName):
            return String(format: AppLocalization.string("无法永久删除清理回收站文件：%@"), fileName)
        }
    }
}

enum StorageCleanupTrashStore {
    private final class RollbackFailureState: @unchecked Sendable {
        private let lock = NSLock()
        private var fileNames = Set<String>()

        func replace(with newValue: Set<String>) -> Set<String> {
            lock.lock()
            defer { lock.unlock() }
            let previous = fileNames
            fileNames = newValue
            return previous
        }

        func contains(_ fileName: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return fileNames.contains(fileName)
        }
    }

    private static let rootDirectoryName = "StorageCleanupTrash"
    private static let manifestFileName = "manifest.json"
    static let recoveryFileName = "recovery.json"
    private static let rollbackFailureState = RollbackFailureState()

    static var rootURL: URL? {
        RecoverableDeletionStorage.rootURL(named: rootDirectoryName)
    }

    private static var manifestURL: URL? {
        RecoverableDeletionStorage.manifestURL(
            rootDirectoryName: rootDirectoryName,
            manifestFileName: manifestFileName
        )
    }

    static func withRootURLForTesting<T>(_ rootURL: URL, perform body: () throws -> T) rethrows -> T {
        try RecoverableDeletionStorage.withRootURLForTesting(
            rootURL,
            rootDirectoryName: rootDirectoryName,
            perform: body
        )
    }

    static func rootURLForTesting() throws -> URL {
        try RecoverableDeletionStorage.createRootDirectory(named: rootDirectoryName)
    }

    static func manifestURLForTesting() throws -> URL {
        try rootURLForTesting().appendingPathComponent(manifestFileName)
    }

    static func withRollbackRestoreFailuresForTesting<T>(
        fileNames: Set<String>,
        perform body: () throws -> T
    ) rethrows -> T {
        let previous = rollbackFailureState.replace(with: fileNames)
        defer {
            _ = rollbackFailureState.replace(with: previous)
        }
        return try body()
    }

    static func loadBatches() -> [StorageCleanupTrashBatch] {
        var batches: [StorageCleanupTrashBatch] = []
        do {
            batches = try RecoverableDeletionStorage.loadManifest(
                rootDirectoryName: rootDirectoryName,
                manifestFileName: manifestFileName,
                default: []
            )
        } catch RecoverableDeletionStorageError.rootUnavailable {
            return []
        } catch {
            StorageIssueLog.recordEvent(
                "storage_cleanup.trash_manifest_read_failed",
                category: .dataStore,
                details: [
                    "source": "StorageCleanupTrashStore.loadBatches",
                    "manifest_file": manifestURL?.lastPathComponent ?? manifestFileName
                ],
                error: error
            )
        }
        for recoveredBatch in loadRecoveryBatches() where !batches.contains(where: { $0.id == recoveredBatch.id }) {
            batches.append(recoveredBatch)
        }
        return batches.sorted { lhs, rhs in lhs.createdAt > rhs.createdAt }
    }

    private static func loadBatchesForMutation() throws -> [StorageCleanupTrashBatch] {
        do {
            let batches: [StorageCleanupTrashBatch] = try RecoverableDeletionStorage.loadManifest(
                rootDirectoryName: rootDirectoryName, manifestFileName: manifestFileName, default: []
            )
            let ids = Set(batches.map(\.id))
            return batches + loadRecoveryBatches().filter { !ids.contains($0.id) }
        } catch {
            throw StorageCleanupTrashError.manifestReadFailed
        }
    }

    static func quarantine(
        plan: DeferredProjectFileCleanupPlan,
        snapshot: StorageCleanupUndoSnapshot,
        summary: String,
        retentionDays: Int
    ) throws -> StorageCleanupTrashBatch {
        do {
            try RecoverableDeletionStorage.createRootDirectory(named: rootDirectoryName)
        } catch {
            throw StorageCleanupTrashError.rootUnavailable
        }

        let batchID = UUID()
        let createdAt = Date()
        let expiresAt = Calendar.current.date(
            byAdding: .day,
            value: max(retentionDays, 1),
            to: createdAt
        ) ?? createdAt.addingTimeInterval(TimeInterval(max(retentionDays, 1) * 24 * 60 * 60))

        var movedFiles: [StorageCleanupTrashFile] = []
        do {
            for source in trashSources(for: plan) {
                if let file = try moveToTrash(source, batchID: batchID) {
                    movedFiles.append(file)
                }
            }
            guard !movedFiles.isEmpty else {
                throw StorageCleanupTrashError.noFilesToTrash
            }

            let batch = StorageCleanupTrashBatch(
                id: batchID,
                summary: summary,
                createdAt: createdAt,
                expiresAt: expiresAt,
                snapshot: snapshot,
                files: movedFiles
            )
            var batches = try loadBatchesForMutation()
            batches.removeAll { $0.id == batch.id }
            batches.append(batch)
            try writeRecoveryBatch(batch)
            try saveBatches(batches)
            return batch
        } catch {
            rollback(
                batch: StorageCleanupTrashBatch(
                    id: batchID,
                    summary: summary,
                    createdAt: createdAt,
                    expiresAt: expiresAt,
                    snapshot: snapshot,
                    files: movedFiles
                )
            )
            throw error
        }
    }

    static func restore(_ batch: StorageCleanupTrashBatch) throws {
        var batches = try loadBatchesForMutation()
        for file in batch.files {
            try restore(file: file, batchID: batch.id)
        }
        try removeBatchDirectory(batch.id)
        batches.removeAll { $0.id == batch.id }
        try saveBatches(batches)
    }

    static func permanentlyDelete(_ batch: StorageCleanupTrashBatch) throws {
        var batches = try loadBatchesForMutation()
        do {
            try removeBatchDirectory(batch.id)
            batches.removeAll { $0.id == batch.id }
            try saveBatches(batches)
        } catch {
            throw StorageCleanupTrashError.permanentDeleteFailed(batch.summary)
        }
    }

    static func purgeExpiredBatches(now: Date) -> Int {
        let batches: [StorageCleanupTrashBatch]
        do {
            batches = try loadBatchesForMutation()
        } catch {
            StorageIssueLog.recordEvent("storage_cleanup.trash_manifest_read_failed", category: .dataStore, error: error)
            return 0
        }
        let purge = RecoverableDeletionStorage.purgeExpiredItems(
            batches,
            now: now,
            expiresAt: \.expiresAt
        ) { batch in
            try removeBatchDirectory(batch.id)
        } onDeleteFailure: { batch, error in
            StorageIssueLog.recordEvent(
                "storage_cleanup.trash_expired_delete_failed",
                category: .dataStore,
                details: [
                    "source": "StorageCleanupTrashStore.purgeExpiredBatches",
                    "batch_id": batch.id.uuidString,
                    "summary": batch.summary
                ],
                error: error
            )
        }
        guard purge.purgedCount > 0 else { return 0 }

        do {
            try saveBatches(purge.remaining)
        } catch {
            StorageIssueLog.recordEvent(
                "storage_cleanup.trash_manifest_update_failed",
                category: .dataStore,
                details: [
                    "source": "StorageCleanupTrashStore.purgeExpiredBatches",
                    "expired_count": "\(purge.purgedCount)"
                ],
                error: error
            )
        }
        return purge.purgedCount
    }

    private static func saveBatches(_ batches: [StorageCleanupTrashBatch]) throws {
        let sorted = batches.sorted { lhs, rhs in lhs.createdAt > rhs.createdAt }
        do {
            try RecoverableDeletionStorage.saveManifest(
                sorted,
                rootDirectoryName: rootDirectoryName,
                manifestFileName: manifestFileName
            )
        } catch RecoverableDeletionStorageError.rootUnavailable {
            throw StorageCleanupTrashError.rootUnavailable
        } catch {
            throw StorageCleanupTrashError.manifestWriteFailed
        }
    }
}

extension StorageCleanupTrashStore {
    static func shouldFailRollbackRestoreForTesting(_ fileName: String) -> Bool {
        rollbackFailureState.contains(fileName)
    }
}
