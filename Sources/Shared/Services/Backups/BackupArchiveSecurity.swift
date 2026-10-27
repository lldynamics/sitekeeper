import CryptoKit
import Foundation

enum BackupArchiveSecurityError: Error, Equatable {
    case digestMismatch
    case invalidDigest
}

enum BackupArchiveSecurity {
    static let digestAlgorithm = "sha256"
    private static let readChunkSize = 1_048_576

    static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: readChunkSize) ?? Data()
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func normalizedDigest(_ value: String) throws -> String {
        let digest = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard digest.count == 64,
              digest.unicodeScalars.allSatisfy({
                  (48 ... 57).contains($0.value) || (97 ... 102).contains($0.value)
              }) else {
            throw BackupArchiveSecurityError.invalidDigest
        }
        return digest
    }

    static func validateRemoteCopy(at fileURL: URL, expectedSHA256: String?) throws {
        if let expectedSHA256 {
            let expected = try normalizedDigest(expectedSHA256)
            guard try sha256Hex(of: fileURL) == expected else {
                throw BackupArchiveSecurityError.digestMismatch
            }
        }
        _ = try BackupArchiveService.validateArchive(at: fileURL)
    }

    @discardableResult
    static func applyDataProtection(to fileURL: URL) -> Bool {
        #if os(iOS)
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fileURL.path
            )
            return true
        } catch {
            StorageIssueLog.recordEvent(
                "backup.security.file_protection_failed",
                category: .zipArchive,
                details: ["file": fileURL.lastPathComponent],
                error: error
            )
            return false
        }
        #else
        return true
        #endif
    }
}

extension BackupArchiveService {
    /// Performs a full streaming ZIP/CRC scan and validates the manifest and metadata.
    /// Unlike preview, every embedded file is read so a damaged remote copy is rejected
    /// before the import UI offers it to the user.
    static func validateArchive(at fileURL: URL) throws -> BackupArchiveManifest {
        guard fileURL.pathExtension.lowercased() == "zip" else {
            throw BackupArchiveError.invalidBackup
        }

        var manifestData: Data?
        var metadataData: Data?
        try SimpleZipArchiveReader.scan(
            fileURL: fileURL,
            limits: .backup,
            verifyAllEntries: true,
            onEntry: { entry, readData, _ in
                switch entry.path {
                case manifestPath:
                    manifestData = try readData()
                case metadataPath:
                    metadataData = try readData()
                default:
                    break
                }
            }
        )

        guard let manifestData else { throw BackupArchiveError.missingManifest }
        guard let metadataData else { throw BackupArchiveError.missingMetadata }
        let manifest = try decodeManifest(from: manifestData)
        _ = try decodeJSONSnapshot(from: metadataData)
        return manifest
    }
}
