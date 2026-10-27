import Foundation

extension StorageCleanupTrashStore {
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

    static func saveRecoveryBatch(_ batch: StorageCleanupTrashBatch) {
        do {
            try writeRecoveryBatch(batch)
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

    static func writeRecoveryBatch(_ batch: StorageCleanupTrashBatch) throws {
        guard let recoveryURL = rootURL?
            .appendingPathComponent(batch.id.uuidString, isDirectory: true)
            .appendingPathComponent(recoveryFileName) else { throw StorageCleanupTrashError.rootUnavailable }
        let data = try JSONEncoder().encode(batch)
        try data.write(to: recoveryURL, options: .atomic)
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

struct StorageCleanupTrashSource {
    let kind: StorageCleanupTrashFileKind
    let fileName: String
}
