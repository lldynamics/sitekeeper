import Foundation

enum FileQuarantineCategory: String, Codable {
    case photoOriginal = "photo-original"
    case photoThumbnail = "photo-thumbnail"
    case drawing = "drawing"
    case drawingSidecar = "drawing-sidecar"
    case projectDocument = "project-document"
    case quickNoteAttachment = "quick-note-attachment"
}

struct FileQuarantineEntry: Identifiable, Codable {
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
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
    }

    private static var manifestURL: URL? {
        rootURL?.appendingPathComponent(manifestFileName)
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

    @discardableResult
    static func purgeExpiredEntries(now: Date = Date()) -> Int {
        guard let rootURL else { return 0 }
        let manager = FileManager.default
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

        let expired = manifest.entries.filter { $0.expiresAt <= now }
        guard !expired.isEmpty else { return 0 }

        for entry in expired {
            let quarantinedURL = rootURL.appendingPathComponent(entry.quarantinedRelativePath)
            guard manager.fileExists(atPath: quarantinedURL.path) else { continue }
            do {
                _ = try FileOps.removeIfExists(
                    at: quarantinedURL,
                    context: .init(
                        event: "quarantine.expired_delete",
                        category: .fileStorage,
                        source: "FileQuarantineStore.purgeExpiredEntries"
                    )
                )
            } catch {
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

        var nextManifest = manifest
        nextManifest.entries.removeAll { $0.expiresAt <= now }
        do {
            try saveManifest(nextManifest)
        } catch {
            StorageIssueLog.recordEvent(
                "quarantine.manifest_update_failed",
                category: .fileStorage,
                error: error
            )
        }
        return expired.count
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
        guard let manifestURL else {
            throw FileStorageError.directoryCreationFailed(rootDirectoryName)
        }
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return FileQuarantineManifest()
        }
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(FileQuarantineManifest.self, from: data)
    }

    private static func saveManifest(_ manifest: FileQuarantineManifest) throws {
        guard let rootURL, let manifestURL else {
            throw FileStorageError.directoryCreationFailed(rootDirectoryName)
        }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sorted = FileQuarantineManifest(
            schemaVersion: manifest.schemaVersion,
            entries: manifest.entries.sorted { lhs, rhs in
                lhs.createdAt > rhs.createdAt
            }
        )
        let data = try JSONEncoder().encode(sorted)
        try data.write(to: manifestURL, options: .atomic)
    }
}
