import Foundation

extension BackupArchiveService {
    static func decodeJSONSnapshot(from data: Data) throws -> BackupSnapshot {
        let header = try JSONDecoder().decode(BackupSchemaHeader.self, from: data)
        try validateSupportedSchemaVersion(header.schemaVersion)
        let snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: data)
        try snapshot.validateAttachmentReferences()
        return snapshot
    }

    static func decodeManifest(from data: Data) throws -> BackupArchiveManifest {
        let manifest = try JSONDecoder().decode(BackupArchiveManifest.self, from: data)
        try validateSupportedSchemaVersion(manifest.schemaVersion)
        guard manifest.metadataPath == metadataPath else {
            throw BackupArchiveError.invalidBackup
        }
        return manifest
    }

    static func encodeManifest(from snapshot: BackupSnapshot, cloudBackupScope: CloudBackupScope? = nil) throws -> Data {
        let manifest = BackupArchiveManifest(
            schemaVersion: snapshot.schemaVersion,
            appVersion: snapshot.appVersion,
            appBuild: snapshot.appBuild,
            appName: AppBrand.displayName,
            exportedAt: snapshot.backupCreatedAt,
            metadataPath: metadataPath,
            cloudBackupScope: cloudBackupScope
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(manifest)
        } catch {
            throw BackupArchiveError.encodingFailed
        }
    }

    static func encodeMetadata(_ snapshot: BackupSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(snapshot)
        } catch {
            throw BackupArchiveError.encodingFailed
        }
    }

    static func leafFileName(for path: String, prefix: String) -> String? {
        guard path.hasPrefix(prefix) else { return nil }
        let fileName = String(path.dropFirst(prefix.count))
        guard AttachmentStoragePath.isSafeLeaf(fileName) else { return nil }
        return fileName
    }
}

extension BackupSnapshot {
    /// Import/export boundary only: local decoding preserves malformed historical metadata for recovery.
    /// Empty references are intentional in metadata-only cloud backups; embedded files cannot be empty.
    func validateAttachmentReferences() throws {
        func validate(_ names: [String], target: (String) throws -> URL, allowsEmpty: Bool = true) throws {
            for name in names {
                if name.isEmpty && allowsEmpty { continue }
                _ = try target(name)
            }
        }

        let photos = dailyLogs.flatMap(\.allPhotoFileNames)
            + siteTodos.compactMap(\.rectificationBeforePhotoFileName)
            + siteTodos.compactMap(\.rectificationAfterPhotoFileName)
        try validate(photos, target: PhotoStorage.validatedFileURL(for:))
        try validate(photos, target: PhotoStorage.validatedThumbnailFileURL(for:))
        try validate(projectDrawings.map(\.fileName), target: DrawingStorage.validatedFileURL(for:))
        try validate(projectDocuments.map(\.fileName), target: ProjectDocumentStorage.validatedFileURL(for:))
        let attachments = quickNotes.flatMap(\.attachments)
            + constructionMethods.flatMap(\.attachments)
            + constructionMethods.flatMap(\.tutorialAttachments)
        try validate(attachments.map(\.fileName), target: QuickNoteAttachmentStorage.validatedFileURL(for:))
        try validate(photoFiles.map(\.fileName), target: PhotoStorage.validatedFileURL(for:), allowsEmpty: false)
        try validate(photoFiles.map(\.fileName), target: PhotoStorage.validatedThumbnailFileURL(for:), allowsEmpty: false)
        try validate(drawingFiles.map(\.fileName), target: DrawingStorage.validatedFileURL(for:), allowsEmpty: false)
        try validate(documentFiles.map(\.fileName), target: ProjectDocumentStorage.validatedFileURL(for:), allowsEmpty: false)
        try validate(quickNoteAttachmentFiles.map(\.fileName), target: QuickNoteAttachmentStorage.validatedFileURL(for:), allowsEmpty: false)
    }
}

private extension BackupArchiveService {
    static func validateSupportedSchemaVersion(_ version: Int) throws {
        guard BackupSnapshot.supportedSchemaVersions.contains(version) else {
            throw BackupArchiveError.unsupportedSchemaVersion(version)
        }
    }
}
