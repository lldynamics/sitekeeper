import Foundation

enum FileQuarantineCategory: String, Codable, Sendable {
    case photoOriginal = "photo-original"
    case photoThumbnail = "photo-thumbnail"
    case drawing = "drawing"
    case drawingSidecar = "drawing-sidecar"
    case projectDocument = "project-document"
    case quickNoteAttachment = "quick-note-attachment"
}

struct FileQuarantineEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let category: FileQuarantineCategory
    let originalPath: String
    let originalFileName: String
    let quarantinedRelativePath: String
    let createdAt: Date
    let expiresAt: Date
}

private struct FileQuarantineManifest: Codable {
    var schemaVersion: Int = 1
    var entries: [FileQuarantineEntry] = []
}

enum FileQuarantineStore {
    private static let rootDirectoryName = "FileQuarantine"
    private static let manifestFileName = "manifest.json"
    private static let defaultRetentionDays = 7
    private static let allowedRetentionDays = [3, 7, 14, 30]

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

    @discardableResult
    static func quarantine(
        fileAt sourceURL: URL,
        category: FileQuarantineCategory,
        originalFileName: String? = nil,
        retentionDays: Int? = nil
    ) throws -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: sourceURL.path) else { return false }
        guard let rootURL else {
            throw FileStorageError.deleteFailed(originalFileName ?? sourceURL.lastPathComponent)
        }

        try manager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        _ = purgeExpiredEntries(now: Date())

        let safeOriginalFileName = (originalFileName ?? sourceURL.lastPathComponent)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedOriginalFileName = safeOriginalFileName.isEmpty ? sourceURL.lastPathComponent : safeOriginalFileName

        let now = Date()
        let effectiveRetentionDays = normalizedRetentionDays(retentionDays ?? configuredRetentionDays())
        let expiresAt = Calendar.current.date(byAdding: .day, value: effectiveRetentionDays, to: now)
            ?? now.addingTimeInterval(TimeInterval(effectiveRetentionDays * 24 * 60 * 60))

        let categoryDirectory = rootURL.appendingPathComponent(category.rawValue, isDirectory: true)
        let trashedFileName = "\(UUID().uuidString)-\(resolvedOriginalFileName)"
        let destinationURL = categoryDirectory.appendingPathComponent(trashedFileName)
        let relativePath = category.rawValue + "/" + trashedFileName

        try manager.createDirectory(at: categoryDirectory, withIntermediateDirectories: true)
        try manager.moveItem(at: sourceURL, to: destinationURL)

        let entry = FileQuarantineEntry(
            id: UUID(),
            category: category,
            originalPath: sourceURL.path,
            originalFileName: resolvedOriginalFileName,
            quarantinedRelativePath: relativePath,
            createdAt: now,
            expiresAt: expiresAt
        )

        do {
            var manifest = try loadManifest()
            manifest.entries.append(entry)
            try saveManifest(manifest)
        } catch {
            // 回滚，避免“文件被移走但清单丢失”的隐性数据风险。
            try? manager.createDirectory(
                at: sourceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if manager.fileExists(atPath: destinationURL.path) {
                try? manager.moveItem(at: destinationURL, to: sourceURL)
            }
            StorageIssueLog.recordEvent(
                "quarantine.manifest_write_failed",
                category: .fileStorage,
                details: [
                    "category": category.rawValue,
                    "file": resolvedOriginalFileName
                ],
                error: error
            )
            throw FileStorageError.deleteFailed(resolvedOriginalFileName)
        }

        return true
    }

    static func loadEntries() -> [FileQuarantineEntry] {
        do {
            return try loadManifest().entries.sorted { lhs, rhs in
                lhs.createdAt > rhs.createdAt
            }
        } catch {
            StorageIssueLog.record(
                String(format: String(localized: "隔离文件清单读取失败：%@"), error.localizedDescription)
            )
            return []
        }
    }

    static func restore(_ entry: FileQuarantineEntry) throws {
        guard let quarantinedURL = quarantinedURL(for: entry) else {
            throw FileStorageError.directoryCreationFailed(rootDirectoryName)
        }

        let manager = FileManager.default
        let originalURL = URL(fileURLWithPath: entry.originalPath)
        guard manager.fileExists(atPath: quarantinedURL.path) else {
            if manager.fileExists(atPath: originalURL.path) {
                try removeEntry(entry.id)
                invalidateCache(for: entry)
                return
            }
            throw FileStorageError.readFailed(entry.originalFileName)
        }

        do {
            try manager.createDirectory(
                at: originalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if manager.fileExists(atPath: originalURL.path) {
                _ = try FileOps.removeIfExists(
                    at: quarantinedURL,
                    context: .init(
                        event: "quarantine.restore_cleanup",
                        category: .fileStorage,
                        source: "FileQuarantineStore.restore"
                    )
                )
            } else {
                try manager.moveItem(at: quarantinedURL, to: originalURL)
            }
            invalidateCache(for: entry)
        } catch {
            StorageIssueLog.recordEvent(
                "quarantine.restore_failed",
                category: .fileStorage,
                details: [
                    "category": entry.category.rawValue,
                    "file": entry.originalFileName
                ],
                error: error
            )
            throw FileStorageError.copyFailed(entry.originalFileName)
        }

        try removeEntry(entry.id)
    }

    static func permanentlyDelete(_ entry: FileQuarantineEntry) throws {
        if let quarantinedURL = quarantinedURL(for: entry) {
            do {
                _ = try FileOps.removeIfExists(
                    at: quarantinedURL,
                    context: .init(
                        event: "quarantine.permanent_delete",
                        category: .fileStorage,
                        source: "FileQuarantineStore.permanentlyDelete"
                    )
                )
            } catch {
                throw FileStorageError.deleteFailed(entry.originalFileName)
            }
        }
        try removeEntry(entry.id)
    }

    private static func configuredRetentionDays() -> Int {
        guard let raw = UserPreferencesStore.shared.optionalInt(UserPreferenceKeys.storageCleanupTrashRetentionDays) else {
            return defaultRetentionDays
        }
        return normalizedRetentionDays(raw)
    }

    private static func normalizedRetentionDays(_ days: Int) -> Int {
        allowedRetentionDays.min { lhs, rhs in
            abs(lhs - days) < abs(rhs - days)
        } ?? defaultRetentionDays
    }

    private static func quarantinedURL(for entry: FileQuarantineEntry) -> URL? {
        rootURL?.appendingPathComponent(entry.quarantinedRelativePath)
    }

    private static func removeEntry(_ id: UUID) throws {
        var manifest = try loadManifest()
        manifest.entries.removeAll { $0.id == id }
        try saveManifest(manifest)
    }

    private static func invalidateCache(for entry: FileQuarantineEntry) {
        switch entry.category {
        case .photoOriginal, .photoThumbnail:
            PhotoCache.shared.invalidate(fileName: entry.originalFileName)
        case .drawing, .drawingSidecar, .projectDocument, .quickNoteAttachment:
            break
        }
    }

    private static func loadManifest() throws -> FileQuarantineManifest {
        try RecoverableDeletionStorage.loadManifest(
            rootDirectoryName: rootDirectoryName,
            manifestFileName: manifestFileName,
            default: FileQuarantineManifest()
        )
    }

    private static func saveManifest(_ manifest: FileQuarantineManifest) throws {
        let sorted = FileQuarantineManifest(
            schemaVersion: manifest.schemaVersion,
            entries: manifest.entries.sorted { lhs, rhs in
                lhs.createdAt > rhs.createdAt
            }
        )
        do {
            try RecoverableDeletionStorage.saveManifest(
                sorted,
                rootDirectoryName: rootDirectoryName,
                manifestFileName: manifestFileName
            )
        } catch RecoverableDeletionStorageError.rootUnavailable {
            throw FileStorageError.directoryCreationFailed(rootDirectoryName)
        }
    }
}

extension FileQuarantineStore {
    @discardableResult
    static func purgeExpiredEntries(now: Date = Date()) -> Int {
        guard let rootURL else { return 0 }
        let manifest: FileQuarantineManifest
        do {
            manifest = try loadManifest()
        } catch {
            StorageIssueLog.recordEvent(
                "quarantine.manifest_read_failed",
                category: .fileStorage,
                error: error
            )
            return 0
        }

        let purge = RecoverableDeletionStorage.purgeExpiredItems(
            manifest.entries,
            now: now,
            expiresAt: \.expiresAt,
            removeAfterFailure: true
        ) { entry in
            try deleteExpiredEntry(entry, rootURL: rootURL)
        } onDeleteFailure: { entry, error in
            recordExpiredDeleteFailure(entry: entry, error: error)
        }
        guard purge.purgedCount > 0 else { return 0 }

        var nextManifest = manifest
        nextManifest.entries = purge.remaining
        do {
            try saveManifest(nextManifest)
        } catch {
            StorageIssueLog.recordEvent(
                "quarantine.manifest_update_failed",
                category: .fileStorage,
                error: error
            )
        }
        return purge.purgedCount
    }

    private static func deleteExpiredEntry(_ entry: FileQuarantineEntry, rootURL: URL) throws {
        let quarantinedURL = rootURL.appendingPathComponent(entry.quarantinedRelativePath)
        guard FileManager.default.fileExists(atPath: quarantinedURL.path) else { return }
        _ = try FileOps.removeIfExists(
            at: quarantinedURL,
            context: .init(
                event: "quarantine.expired_delete",
                category: .fileStorage,
                source: "FileQuarantineStore.purgeExpiredEntries"
            )
        )
    }

    private static func recordExpiredDeleteFailure(entry: FileQuarantineEntry, error: Error) {
        StorageIssueLog.recordEvent(
            "quarantine.expired_delete_failed",
            category: .fileStorage,
            details: [
                "category": entry.category.rawValue,
                "file": entry.originalFileName
            ],
            error: error
        )
    }
}
