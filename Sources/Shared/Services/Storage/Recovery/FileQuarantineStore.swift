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
    // Atomic manifest writes do not protect a read-modify-write transaction. Keep
    // the file move and its manifest update together, including nested expiry cleanup.
    static let transactionLock = NSRecursiveLock()
    // Test scopes may dispatch concurrent file operations, so this must be a
    // separate lock rather than holding transactionLock for the entire test body.
    private static let testingRootScopeLock = NSRecursiveLock()

    static var rootURL: URL? {
        RecoverableDeletionStorage.rootURL(named: rootDirectoryName)
    }

    static func withRootURLForTesting<T>(_ rootURL: URL, perform body: () throws -> T) rethrows -> T {
        testingRootScopeLock.lock()
        defer { testingRootScopeLock.unlock() }
        return try RecoverableDeletionStorage.withRootURLForTesting(
            rootURL,
            rootDirectoryName: rootDirectoryName,
            perform: body
        )
    }

    @discardableResult
    static func quarantine(
        fileAt sourceURL: URL,
        category: FileQuarantineCategory,
        originalFileName: String? = nil,
        retentionDays: Int? = nil
    ) throws -> Bool {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let manager = FileManager.default
        _ = try validatedOriginalURL(path: sourceURL.path,
            fileName: originalFileName ?? sourceURL.lastPathComponent, category: category)
        guard manager.fileExists(atPath: sourceURL.path) else { return false }
        if exportProtection.leases.values.contains(where: { $0.contains(sourceURL.standardizedFileURL.path) }) {
            exportProtection.requests[sourceURL.standardizedFileURL.path] = DeferredQuarantine(
                sourceURL: sourceURL, category: category, originalFileName: originalFileName,
                retentionDays: retentionDays, identity: try FileIdentity(url: sourceURL), quarantineRoot: rootURL
            )
            return true
        }
        guard let rootURL else {
            throw FileStorageError.deleteFailed(originalFileName ?? sourceURL.lastPathComponent)
        }

        try AttachmentStoragePath.validateDirectory(rootURL)
        try manager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        _ = purgeExpiredEntries(now: Date())

        let resolvedOriginalFileName = originalFileName ?? sourceURL.lastPathComponent

        let now = Date()
        let effectiveRetentionDays = normalizedRetentionDays(retentionDays ?? configuredRetentionDays())
        let expiresAt = Calendar.current.date(byAdding: .day, value: effectiveRetentionDays, to: now)
            ?? now.addingTimeInterval(TimeInterval(effectiveRetentionDays * 24 * 60 * 60))

        let categoryDirectory = rootURL.appendingPathComponent(category.rawValue, isDirectory: true)
        let trashedFileName = "\(UUID().uuidString)-\(resolvedOriginalFileName)"
        let destinationURL = try AttachmentStoragePath.fileURL(for: trashedFileName, in: categoryDirectory)
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

        defer { invalidateCache(for: entry) }
        try recordQuarantinedEntry(entry, sourceURL: sourceURL, destinationURL: destinationURL)

        return true
    }

    private static func recordQuarantinedEntry(_ entry: FileQuarantineEntry, sourceURL: URL, destinationURL: URL) throws {
        let manager = FileManager.default
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
                    "category": entry.category.rawValue,
                    "file": entry.originalFileName
                ],
                error: error
            )
            throw FileStorageError.deleteFailed(entry.originalFileName)
        }
    }

    static func loadEntries() -> [FileQuarantineEntry] {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        do {
            return try loadManifest().entries.sorted { lhs, rhs in
                lhs.createdAt > rhs.createdAt
            }
        } catch {
            StorageIssueLog.record(
                String(format: AppLocalization.string("隔离文件清单读取失败：%@"), error.localizedDescription)
            )
            return []
        }
    }

    static func restore(_ entry: FileQuarantineEntry) throws {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        guard let quarantinedURL = quarantinedURL(for: entry) else {
            throw FileStorageError.directoryCreationFailed(rootDirectoryName)
        }

        let manager = FileManager.default
        let originalURL = try validatedOriginalURL(path: entry.originalPath,
            fileName: entry.originalFileName, category: entry.category)
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
        transactionLock.lock()
        defer { transactionLock.unlock() }
        _ = try validatedOriginalURL(path: entry.originalPath, fileName: entry.originalFileName, category: entry.category)
        guard let quarantinedURL = quarantinedURL(for: entry) else {
            throw FileStorageError.unsafeAttachmentPath(entry.originalFileName)
        }
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

    /// A legacy manifest cannot redirect recovery outside the owning storage family.
    /// Unrecognized historic paths remain on disk and in the manifest for manual recovery.
    private static func validatedOriginalURL(path: String, fileName: String, category: FileQuarantineCategory) throws -> URL {
        try AttachmentStoragePath.validateLeaf(fileName)
        guard path.hasPrefix("/"), !path.contains("\0"),
              !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw FileStorageError.unsafeAttachmentPath(fileName)
        }
        let original = URL(fileURLWithPath: path)
        let originalLeaf = original.lastPathComponent
        try AttachmentStoragePath.validateLeaf(originalLeaf)
        // Older manifests trimmed the display name but retained the original path verbatim.
        guard originalLeaf == fileName || originalLeaf.trimmingCharacters(in: .whitespacesAndNewlines) == fileName else {
            throw FileStorageError.unsafeAttachmentPath(fileName)
        }
        let expected: URL
        switch category {
        case .photoOriginal: expected = try PhotoStorage.validatedFileURL(for: originalLeaf)
        case .photoThumbnail: expected = try PhotoStorage.validatedThumbnailFileURL(for: originalLeaf)
        case .drawing, .drawingSidecar: expected = try DrawingStorage.validatedFileURL(for: originalLeaf)
        case .projectDocument: expected = try ProjectDocumentStorage.validatedFileURL(for: originalLeaf)
        case .quickNoteAttachment: expected = try QuickNoteAttachmentStorage.validatedFileURL(for: originalLeaf)
        }
        if let relocated = relocatedContainerTarget(originalPath: path, expected: expected) {
            return relocated
        }
        try AttachmentStoragePath.validateFile(original)
        if original.resolvingSymlinksInPath().standardizedFileURL == expected.resolvingSymlinksInPath().standardizedFileURL {
            return original
        }
        // Only the explicit test-root API enables synthetic fixture origins. The bound is
        // the fixture directory beside that root, never the system temporary directory.
        if let override = RecoverableDeletionStorage.rootOverrideForTesting(named: rootDirectoryName) {
            let bound = override.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            let candidate = original.resolvingSymlinksInPath().standardizedFileURL
            let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
            if bound != temporary, bound.path != "/", candidate.path.hasPrefix(bound.path + "/") {
                return original
            }
        }
        throw FileStorageError.unsafeAttachmentPath(fileName)
    }

    /// iOS rotates `/Containers/Data/Application/<UUID>` across app updates and device restores.
    /// Map a historic container path onto the current validated family URL only when its
    /// `Documents/<family>/<leaf>` suffix matches `expected` verbatim.
    private static func relocatedContainerTarget(originalPath: String, expected: URL) -> URL? {
        let parts = originalPath.split(separator: "/").map(String.init)
        guard parts.count >= 7 else { return nil }
        for index in 0...(parts.count - 7) {
            guard parts[index] == "Containers",
                  parts[index + 1] == "Data",
                  parts[index + 2] == "Application",
                  UUID(uuidString: parts[index + 3]) != nil,
                  parts[index + 4] == "Documents" else {
                continue
            }
            let suffix = "/" + parts[(index + 4)...].joined(separator: "/")
            let expectedStandardized = expected.standardizedFileURL.path
            let expectedResolved = expected.resolvingSymlinksInPath().standardizedFileURL.path
            if expectedStandardized.hasSuffix(suffix) || expectedResolved.hasSuffix(suffix) {
                return expected
            }
        }
        return nil
    }

    private static func quarantinedURL(for entry: FileQuarantineEntry) -> URL? {
        guard let rootURL else { return nil }
        let prefix = entry.category.rawValue + "/"
        guard entry.quarantinedRelativePath.hasPrefix(prefix) else { return nil }
        let name = String(entry.quarantinedRelativePath.dropFirst(prefix.count))
        return try? AttachmentStoragePath.fileURL(for: name, in: rootURL.appendingPathComponent(entry.category.rawValue))
    }

    private static func removeEntry(_ id: UUID) throws {
        var manifest = try loadManifest()
        manifest.entries.removeAll { $0.id == id }
        try saveManifest(manifest)
    }

    private static func invalidateCache(for entry: FileQuarantineEntry) {
        switch entry.category {
        case .photoOriginal, .photoThumbnail:
            PhotoCache.shared.invalidate(fileName: URL(fileURLWithPath: entry.originalPath).lastPathComponent)
        case .quickNoteAttachment:
            let leaf = URL(fileURLWithPath: entry.originalPath).lastPathComponent
            let target = (try? QuickNoteAttachmentStorage.validatedFileURL(for: leaf))
                ?? URL(fileURLWithPath: entry.originalPath)
            StorageThumbnailCache.invalidate(resourceURL: target)
        case .drawing, .drawingSidecar, .projectDocument:
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
        transactionLock.lock()
        defer { transactionLock.unlock() }
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
            removeAfterFailure: false
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
        _ = try validatedOriginalURL(path: entry.originalPath, fileName: entry.originalFileName, category: entry.category)
        guard let quarantinedURL = quarantinedURL(for: entry) else {
            throw FileStorageError.unsafeAttachmentPath(entry.originalFileName)
        }
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
