import Foundation
import GRDB

/// Explicit, offline candidate builder. It never opens the source through the live
/// persistence actor (which may recover journals), replaces JSON, or selects a new backend.
actor SQLiteCandidateBuilder {
    struct Result: Sendable {
        let directory: URL
        let manifest: SQLiteCandidateManifest
    }

    func build(
        sourceURL: URL,
        assetDirectories: [RepositoryAssetFamily: URL] = [:],
        options: SQLiteCandidateOptions = SQLiteCandidateOptions()
    ) async throws -> Result {
        try Task.checkCancellation()
        let source = sourceURL.standardizedFileURL
        let lease = try RepositoryWorkspaceLease(root: RepositoryWorkspaceMaintenance.root(beside: source))
        defer { withExtendedLifetime(lease) {} }
        let raw = try CandidateFiles.readRegularFile(source)
        let audit = try CandidateFiles.auditData(for: source)
        let id = UUID()
        let directory = try Self.createDirectory(for: source, id: id)
        let manifestURL = directory.appendingPathComponent("candidate.json")
        var manifest = SQLiteCandidateManifest(id: id, sourceSHA256: CandidateFiles.hash(raw), auditSHA256: audit.map(CandidateFiles.hash), createdAt: Date())
        var pool: DatabasePool?
        do {
            try CandidateFiles.write(manifest, to: manifestURL)
            let dataset = try Self.preserveSource(raw, audit: audit, source: source, directory: directory, manifest: &manifest, options: options)
            let assets = try CandidateFiles.assets(for: dataset, directories: assetDirectories)
            try CandidateFiles.write(assets, to: directory.appendingPathComponent("assets.json"))
            let databaseURL = directory.appendingPathComponent("candidate.sqlite")
            let database = try SQLiteRepositorySchema.makePool(at: databaseURL, create: true)
            pool = database
            try SQLiteRepositorySchema.create(in: database)
            try options.fault(.schemaCreated)
            manifest.phase = .importing
            manifest.recordCounts = Dictionary(uniqueKeysWithValues: RepositoryCollection.allCases.map { ($0.rawValue, dataset.records[$0]?.count ?? 0) })
            try CandidateFiles.write(manifest, to: manifestURL)
            if let maximum = options.maximumPageCount {
                try await database.writeWithoutTransaction { db in try db.execute(sql: "PRAGMA max_page_count = \(max(1, maximum))") }
            }
            try await Self.importDataset(dataset, into: database, options: options)
            try options.fault(.importCommitted)
            try await database.read { db in
                try SQLiteRepositorySchema.verify(db)
                try SQLiteRepositoryRows.verifyDataset(dataset, in: db)
            }
            try Self.verifySource(source, raw: raw, audit: audit, dataset: dataset, assets: assets,
                                  assetDirectories: assetDirectories, directory: directory, manifest: &manifest, options: options)
            try await database.write { db in try db.execute(sql: "UPDATE repository_state SET disposition = 'ready'") }
            // Close before publishing the marker; SQLite completes its final WAL checkpoint.
            try database.close()
            pool = nil
            BackupArchiveSecurity.applyDataProtection(to: databaseURL)
            manifest.phase = .ready
            try CandidateFiles.write(manifest, to: manifestURL)
            return Result(directory: directory, manifest: manifest)
        } catch {
            try? pool?.close()
            manifest.phase = .failed
            manifest.error = String(describing: error)
            try? CandidateFiles.write(manifest, to: manifestURL)
            throw error
        }
    }

    private static func createDirectory(for source: URL, id: UUID) throws -> URL {
        let parent = source.deletingLastPathComponent().appendingPathComponent(".sqlite-candidates", isDirectory: true)
        if FileManager.default.fileExists(atPath: parent.path) {
            guard try parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw RepositoryError.invalidCandidate }
        }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let directory = parent.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private static func preserveSource(
        _ raw: Data, audit: Data?, source: URL, directory: URL,
        manifest: inout SQLiteCandidateManifest, options: SQLiteCandidateOptions
    ) throws -> RepositoryDataset {
        try CandidateFiles.requireNoPendingRestore(for: source)
        try options.fault(.beforePreservation)
        guard try options.availableBytes(directory) >= Int64(raw.count) * 4 + Int64(audit?.count ?? 0) * 2 + 1_048_576 else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        BackupArchiveSecurity.applyDataProtection(to: directory)
        let original = directory.appendingPathComponent("source.json")
        let originalAudit = directory.appendingPathComponent("date-audit.json")
        try raw.write(to: original, options: .atomic)
        BackupArchiveSecurity.applyDataProtection(to: original)
        if let audit {
            try audit.write(to: originalAudit, options: .atomic)
            BackupArchiveSecurity.applyDataProtection(to: originalAudit)
        }
        guard try CandidateFiles.readRegularFile(original) == raw,
              try audit.map({ try CandidateFiles.readRegularFile(originalAudit) == $0 }) ?? true else {
            throw RepositoryError.preservationMismatch
        }
        manifest.phase = .preserved
        try CandidateFiles.write(manifest, to: directory.appendingPathComponent("candidate.json"))
        try options.fault(.preserved)
        return try decodeSource(raw, audit: audit)
    }

    private static func verifySource(
        _ source: URL, raw: Data, audit: Data?, dataset: RepositoryDataset,
        assets: [SQLiteCandidateAsset], assetDirectories: [RepositoryAssetFamily: URL],
        directory: URL, manifest: inout SQLiteCandidateManifest, options: SQLiteCandidateOptions
    ) throws {
        manifest.phase = .verified
        try CandidateFiles.write(manifest, to: directory.appendingPathComponent("candidate.json"))
        try options.fault(.verified)
        try options.fault(.beforeReady)
        try Task.checkCancellation()
        try CandidateFiles.requireNoPendingRestore(for: source)
        guard try CandidateFiles.readRegularFile(source) == raw,
              try CandidateFiles.auditData(for: source) == audit,
              try CandidateFiles.assets(for: dataset, directories: assetDirectories) == assets else { throw RepositoryError.sourceChanged }
    }

    /// Abandon a pristine candidate. Preserve all artifacts and never restore old
    /// JSON over newer writes. The database disposition also blocks already-open handles.
    func rollback(candidateDirectory: URL) async throws {
        let lease = try RepositoryWorkspaceLease(root: candidateDirectory.deletingLastPathComponent())
        defer { withExtendedLifetime(lease) {} }
        let url = candidateDirectory.appendingPathComponent("candidate.json")
        var manifest = try JSONDecoder().decode(SQLiteCandidateManifest.self, from: CandidateFiles.readRegularFile(url))
        guard manifest.version == 1 else { throw RepositoryError.invalidCandidate }
        let databaseURL = candidateDirectory.appendingPathComponent("candidate.sqlite")
        if FileManager.default.fileExists(atPath: databaseURL.path) {
            let pool = try SQLiteRepositorySchema.makePool(at: databaseURL, create: false)
            defer { try? pool.close() }
            try await pool.write { db in
                let revision = try Int.fetchOne(db, sql: "SELECT revision FROM repository_state") ?? 0
                guard revision == 0 else { throw RepositoryError.candidateHasNewWrites }
                try db.execute(sql: "UPDATE repository_state SET disposition = 'rolledBack'")
            }
        }
        manifest.phase = .rolledBack
        try CandidateFiles.write(manifest, to: url)
    }

    private static func decodeSource(_ raw: Data, audit: Data?) throws -> RepositoryDataset {
        try CandidateFiles.requireStableIDs(in: raw)
        var snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: raw)
        if let audit {
            let file = try JSONDecoder().decode(DateProvenanceAuditFile.self, from: audit)
            guard file.version == DateProvenanceAuditFile.currentVersion else { throw RepositoryError.invalidRecord("audit version") }
            var seen = Set(snapshot.legacyDateProvenance)
            snapshot.legacyDateProvenance += file.entries.map(\.provenance).filter { seen.insert($0).inserted }
        }
        return try RepositoryDataset(snapshot: snapshot)
    }

    private static func importDataset(_ dataset: RepositoryDataset, into pool: DatabasePool, options: SQLiteCandidateOptions) async throws {
        try await pool.write { db in
            for (name, payload) in dataset.fields where name != "legacyDateProvenance" {
                try db.execute(sql: "INSERT INTO snapshot_fields VALUES (?, ?)", arguments: [name, payload])
            }
            let provenance = try dataset.fields["legacyDateProvenance"].map { try JSONSerialization.jsonObject(with: $0) as? [Any] } ?? []
            for (position, value) in (provenance ?? []).enumerated() {
                try db.execute(sql: "INSERT INTO date_provenance VALUES (?, ?)", arguments: [position, try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])])
            }
            for collection in RepositoryCollection.allCases {
                try Task.checkCancellation()
                for row in dataset.records[collection] ?? [] { try SQLiteRepositoryRows.put(row, in: db) }
                try options.fault(.imported(collection))
            }
            for row in dataset.records.values.flatMap({ $0 }) { try SQLiteRepositoryRows.relate(row, in: db) }
            try options.fault(.beforeCommit)
            try Task.checkCancellation()
        }
    }
}
