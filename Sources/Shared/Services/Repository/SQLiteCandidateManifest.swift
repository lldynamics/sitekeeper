import Foundation
import CryptoKit

struct SQLiteCandidateManifest: Codable, Sendable {
    enum Phase: String, Codable, Sendable { case preserving, preserved, importing, verified, ready, failed, rolledBack }
    var version = 1
    let id: UUID
    let sourceSHA256: String
    let auditSHA256: String?
    var phase: Phase = .preserving
    var recordCounts: [String: Int] = [:]
    var error: String?
    let createdAt: Date
}

struct SQLiteCandidateAsset: Codable, Equatable, Sendable {
    let family: RepositoryAssetFamily
    let fileName: String
    let byteCount: Int
    let sha256: String
}

enum SQLiteCandidateFaultPoint: Equatable, Sendable {
    case beforePreservation, preserved, schemaCreated
    case imported(RepositoryCollection)
    case beforeCommit, importCommitted, verified, beforeReady
}

struct SQLiteCandidateOptions: Sendable {
    var fault: @Sendable (SQLiteCandidateFaultPoint) throws -> Void = { _ in }
    var availableBytes: @Sendable (URL) throws -> Int64 = { url in
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: url.path)
        return (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }
    /// Fault-testing hook for SQLITE_FULL; nil leaves SQLite's limit unchanged.
    var maximumPageCount: Int?
}

enum CandidateFiles {
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
        BackupArchiveSecurity.applyDataProtection(to: url)
    }

    static func readRegularFile(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true else { throw RepositoryError.invalidRecord(url.lastPathComponent) }
        return try Data(contentsOf: url)
    }

    static func auditData(for source: URL) throws -> Data? {
        let audit = DateProvenanceAuditFile.fileURL(forStore: source)
        return FileManager.default.fileExists(atPath: audit.path) ? try readRegularFile(audit) : nil
    }

    static func requireNoPendingRestore(for source: URL) throws {
        let root = BackupArchiveRestoreJournal.transactionsRoot(for: source)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        guard try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty else { throw RepositoryError.pendingRestore }
    }

    static func assets(for dataset: RepositoryDataset, directories: [RepositoryAssetFamily: URL]) throws -> [SQLiteCandidateAsset] {
        var seen = Set<String>()
        var result: [SQLiteCandidateAsset] = []
        for row in dataset.records.values.flatMap({ $0 }) {
            for reference in try RepositoryDataset.attachments(for: row) {
                let key = reference.family.rawValue + "/" + reference.fileName
                guard seen.insert(key).inserted else { continue }
                guard let root = directories[reference.family] else { throw RepositoryError.missingAssetRoot(reference.family.rawValue) }
                let url = root.appendingPathComponent(reference.fileName)
                let before = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                guard before.isRegularFile == true, before.isSymbolicLink != true, let size = before.fileSize else {
                    throw RepositoryError.invalidRecord(reference.fileName)
                }
                // Stream large photos/PDFs instead of allocating one Data per attachment.
                let digest = try BackupArchiveSecurity.sha256Hex(of: url)
                let after = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                guard before.fileSize == after.fileSize, before.contentModificationDate == after.contentModificationDate else {
                    throw RepositoryError.sourceChanged
                }
                result.append(SQLiteCandidateAsset(family: reference.family, fileName: reference.fileName, byteCount: size, sha256: digest))
            }
        }
        return result.sorted { ($0.family.rawValue, $0.fileName) < ($1.family.rawValue, $1.fileName) }
    }

    /// Legacy decoders can generate missing IDs. Migration must instead stop and report them.
    static func requireStableIDs(in data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw RepositoryError.invalidRecord("root") }
        for collection in RepositoryCollection.allCases {
            guard let objects = root[collection.rawValue] as? [[String: Any]] else { continue }
            var ids = Set<UUID>()
            for object in objects {
                guard let raw = object["id"] as? String, let id = UUID(uuidString: raw) else { throw RepositoryError.invalidRecord(collection.rawValue + "/id") }
                guard ids.insert(id).inserted else { throw RepositoryError.duplicateID(collection.rawValue + "/" + raw) }
                for field in ["photos", "attachments", "tutorialAttachments"] {
                    var nestedIDs = Set<UUID>()
                    for nested in object[field] as? [[String: Any]] ?? [] {
                        guard let raw = nested["id"] as? String, let nestedID = UUID(uuidString: raw), nestedIDs.insert(nestedID).inserted else {
                            throw RepositoryError.invalidRecord(collection.rawValue + "/" + field + "/id")
                        }
                    }
                }
            }
        }
    }
}
