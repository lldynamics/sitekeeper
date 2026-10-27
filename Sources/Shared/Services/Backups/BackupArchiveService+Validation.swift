import Foundation

extension BackupArchiveService {
    static func decodeJSONSnapshot(from data: Data) throws -> BackupSnapshot {
        let header = try JSONDecoder().decode(BackupSchemaHeader.self, from: data)
        try validateSupportedSchemaVersion(header.schemaVersion)
        return try JSONDecoder().decode(BackupSnapshot.self, from: data)
    }

    static func decodeManifest(from data: Data) throws -> BackupArchiveManifest {
        let manifest = try JSONDecoder().decode(BackupArchiveManifest.self, from: data)
        try validateSupportedSchemaVersion(manifest.schemaVersion)
        guard manifest.metadataPath == metadataPath else {
            throw BackupArchiveError.invalidBackup
        }
        return manifest
    }

    static func encodeManifest(from snapshot: BackupSnapshot) throws -> Data {
        let manifest = BackupArchiveManifest(
            schemaVersion: snapshot.schemaVersion,
            appVersion: snapshot.appVersion,
            appBuild: snapshot.appBuild,
            appName: AppBrand.displayName,
            exportedAt: snapshot.backupCreatedAt,
            metadataPath: metadataPath
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
        guard !fileName.isEmpty, !fileName.contains("/") else { return nil }
        return fileName
    }
}

private extension BackupArchiveService {
    static func validateSupportedSchemaVersion(_ version: Int) throws {
        guard BackupSnapshot.supportedSchemaVersions.contains(version) else {
            throw BackupArchiveError.unsupportedSchemaVersion(version)
        }
    }
}
