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
    case noFilesToTrash
    case moveToTrashFailed(String)
    case restoreFailed(String)
    case permanentDeleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .rootUnavailable:
            return String(localized: "无法访问清理回收站目录。")
        case .manifestWriteFailed:
            return String(localized: "无法保存清理回收站清单。")
        case .noFilesToTrash:
            return String(localized: "没有可移入清理回收站的文件。")
        case let .moveToTrashFailed(fileName):
            return String(format: String(localized: "无法移入清理回收站：%@"), fileName)
        case let .restoreFailed(fileName):
            return String(format: String(localized: "无法恢复清理回收站文件：%@"), fileName)
        case let .permanentDeleteFailed(fileName):
            return String(format: String(localized: "无法永久删除清理回收站文件：%@"), fileName)
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
    private static let recoveryFileName = "recovery.json"
    private static let rollbackFailureState = RollbackFailureState()

    private static var rootURL: URL? {
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
            var batches = loadBatches()
            batches.removeAll { $0.id == batch.id }
            batches.append(batch)
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
        for file in batch.files {
            try restore(file: file, batchID: batch.id)
        }
        try removeBatchDirectory(batch.id)
        var batches = loadBatches()
        batches.removeAll { $0.id == batch.id }
        try saveBatches(batches)
    }

    static func permanentlyDelete(_ batch: StorageCleanupTrashBatch) throws {
        do {
            try removeBatchDirectory(batch.id)
            var batches = loadBatches()
            batches.removeAll { $0.id == batch.id }
            try saveBatches(batches)
        } catch {
            throw StorageCleanupTrashError.permanentDeleteFailed(batch.summary)
        }
    }

    static func purgeExpiredBatches(now: Date) -> Int {
        let batches = loadBatches()
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

private extension StorageCleanupTrashStore {
    static func trashSources(for plan: DeferredProjectFileCleanupPlan) -> [StorageCleanupTrashSource] {
        var sources: [StorageCleanupTrashSource] = []
        sources += plan.photoFileNames.sorted().flatMap { fileName in
            [
                StorageCleanupTrashSource(kind: .photoOriginal, fileName: fileName),
                StorageCleanupTrashSource(kind: .photoThumbnail, fileName: fileName)
            ]
        }
        sources += plan.quickNoteAttachmentFileNames.sorted().map {
            StorageCleanupTrashSource(kind: .quickNoteAttachment, fileName: $0)
        }
        sources += plan.projectDocumentFileNames.sorted().map {
            StorageCleanupTrashSource(kind: .projectDocument, fileName: $0)
        }
        sources += plan.drawingFileNames.sorted().map { fileName in
            StorageCleanupTrashSource(kind: .drawing, fileName: fileName)
        }
        return sources
    }

    static func moveToTrash(
        _ source: StorageCleanupTrashSource,
        batchID: UUID
    ) throws -> StorageCleanupTrashFile? {
        let sourceURL = source.kind.originalURL(for: source.fileName)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }

        guard let destinationURL = trashURL(
            batchID: batchID,
            kind: source.kind,
            trashedFileName: "\(UUID().uuidString)-\(source.fileName)"
        ) else {
            throw StorageCleanupTrashError.rootUnavailable
        }

        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            source.kind.invalidateCache(for: source.fileName)
            return StorageCleanupTrashFile(
                id: UUID(),
                kind: source.kind,
                originalFileName: source.fileName,
                trashedFileName: destinationURL.lastPathComponent
            )
        } catch {
            throw StorageCleanupTrashError.moveToTrashFailed(source.fileName)
        }
    }

    static func restore(file: StorageCleanupTrashFile, batchID: UUID) throws {
        guard let trashedURL = trashURL(
            batchID: batchID,
            kind: file.kind,
            trashedFileName: file.trashedFileName
        ) else {
            throw StorageCleanupTrashError.rootUnavailable
        }

        let originalURL = file.kind.originalURL(for: file.originalFileName)
        let manager = FileManager.default
        guard manager.fileExists(atPath: trashedURL.path) else {
            if manager.fileExists(atPath: originalURL.path) {
                file.kind.invalidateCache(for: file.originalFileName)
                return
            }
            throw StorageCleanupTrashError.restoreFailed(file.originalFileName)
        }

        do {
            try manager.createDirectory(
                at: originalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if manager.fileExists(atPath: originalURL.path) {
                _ = try FileOps.removeIfExists(
                    at: trashedURL,
                    context: .init(
                        event: "storage_cleanup.trash_restore_cleanup",
                        category: .fileStorage,
                        source: "StorageCleanupTrashStore.restore"
                    )
                )
            } else {
                try manager.moveItem(at: trashedURL, to: originalURL)
            }
            file.kind.invalidateCache(for: file.originalFileName)
        } catch {
            throw StorageCleanupTrashError.restoreFailed(file.originalFileName)
        }
    }

    static func rollback(batch: StorageCleanupTrashBatch) {
        var restoredAllFiles = true
        for file in batch.files.reversed() {
            do {
                if shouldFailRollbackRestoreForTesting(file.originalFileName) {
                    throw StorageCleanupTrashError.restoreFailed(file.originalFileName)
                }
                try restore(file: file, batchID: batch.id)
            } catch {
                restoredAllFiles = false
                StorageIssueLog.recordEvent(
                    "storage_cleanup.trash_rollback_restore_failed",
                    category: .dataStore,
                    details: [
                        "source": "StorageCleanupTrashStore.rollback",
                        "batch_id": batch.id.uuidString,
                        "file": file.originalFileName
                    ],
                    error: error
                )
            }
        }
        // A failed restore means the trash batch may hold the only remaining
        // copy. Keep it intact so the operation can be retried safely.
        guard restoredAllFiles else {
            saveRecoveryBatch(batch)
            return
        }
        try? removeBatchDirectory(batch.id)
    }

    static func shouldFailRollbackRestoreForTesting(_ fileName: String) -> Bool {
        rollbackFailureState.contains(fileName)
    }

    static func saveRecoveryBatch(_ batch: StorageCleanupTrashBatch) {
        guard let recoveryURL = rootURL?
            .appendingPathComponent(batch.id.uuidString, isDirectory: true)
            .appendingPathComponent(recoveryFileName) else { return }
        do {
            let data = try JSONEncoder().encode(batch)
            try data.write(to: recoveryURL, options: .atomic)
        } catch {
            StorageIssueLog.recordEvent(
                "storage_cleanup.trash_recovery_manifest_write_failed",
                category: .dataStore,
                details: [
                    "source": "StorageCleanupTrashStore.saveRecoveryBatch",
                    "batch_id": batch.id.uuidString
                ],
                error: error
            )
        }
    }

    static func loadRecoveryBatches() -> [StorageCleanupTrashBatch] {
        guard let rootURL else { return [] }
        let directories: [URL]
        do {
            directories = try FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        return directories.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            let recoveryURL = directory.appendingPathComponent(recoveryFileName)
            guard let data = try? Data(contentsOf: recoveryURL) else { return nil }
            return try? JSONDecoder().decode(StorageCleanupTrashBatch.self, from: data)
        }
    }

    static func trashURL(
        batchID: UUID,
        kind: StorageCleanupTrashFileKind,
        trashedFileName: String
    ) -> URL? {
        rootURL?
            .appendingPathComponent(batchID.uuidString, isDirectory: true)
            .appendingPathComponent(kind.rawValue, isDirectory: true)
            .appendingPathComponent(trashedFileName)
    }

    static func removeBatchDirectory(_ batchID: UUID) throws {
        guard let batchURL = rootURL?.appendingPathComponent(batchID.uuidString, isDirectory: true) else {
            throw StorageCleanupTrashError.rootUnavailable
        }
        guard FileManager.default.fileExists(atPath: batchURL.path) else { return }
        do {
            _ = try FileOps.removeIfExists(
                at: batchURL,
                context: .init(
                    event: "storage_cleanup.trash_batch_remove",
                    category: .fileStorage,
                    source: "StorageCleanupTrashStore.removeBatchDirectory"
                )
            )
        } catch {
            throw StorageCleanupTrashError.permanentDeleteFailed(batchID.uuidString)
        }
    }
}

private struct StorageCleanupTrashSource {
    let kind: StorageCleanupTrashFileKind
    let fileName: String
}
