import Foundation
import GRDB

/// Opens only a verified candidate. No production path or DataStore writer is changed.
actor SQLiteBusinessRepository: BusinessRepository {
    private var workspaceLease: RepositoryWorkspaceLease?
    private let pool: DatabasePool

    init(candidateDirectory: URL, statementObserver: (@Sendable (String) -> Void)? = nil) throws {
        let lease = try RepositoryWorkspaceLease(root: candidateDirectory.deletingLastPathComponent())
        let manifest = try JSONDecoder().decode(SQLiteCandidateManifest.self, from: Data(contentsOf: candidateDirectory.appendingPathComponent("candidate.json")))
        guard manifest.version == 1, manifest.phase == .ready else { throw RepositoryError.invalidCandidate }
        pool = try SQLiteRepositorySchema.makePool(at: candidateDirectory.appendingPathComponent("candidate.sqlite"), create: false, statementObserver: statementObserver)
        try pool.read { db in try SQLiteRepositorySchema.requireReady(db) }
        try SQLiteRepositorySchema.create(in: pool)
        try pool.read { db in
            try SQLiteRepositorySchema.requireReady(db)
            try SQLiteRepositorySchema.verify(db)
        }
        workspaceLease = lease
    }

    deinit {
        // Finish closing SQLite before the directory lease is released.
        try? pool.close()
    }

    func close() throws {
        try pool.close()
        workspaceLease = nil
    }

    func revision() async throws -> Int {
        try await pool.read { db in
            try SQLiteRepositorySchema.requireReady(db)
            return try Int.fetchOne(db, sql: "SELECT revision FROM repository_state") ?? 0
        }
    }

    func record(_ collection: RepositoryCollection, id: UUID) async throws -> Data? {
        try await pool.read { db in
            try SQLiteRepositorySchema.requireReady(db)
            return try SQLiteRepositoryRows.payload(collection, id: id, in: db)
        }
    }

    func detail(_ collection: RepositoryCollection, id: UUID) async throws -> RepositoryDetail? {
        try await pool.read { db in
            try SQLiteRepositorySchema.requireReady(db)
            let revision = try Int.fetchOne(db, sql: "SELECT revision FROM repository_state") ?? 0
            return try SQLiteRepositoryRows.payload(collection, id: id, in: db).map {
                RepositoryDetail(payload: $0, revision: revision)
            }
        }
    }

    func page(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) async throws -> RepositoryPage {
        try await pool.read { db in
            try SQLiteRepositorySchema.requireReady(db)
            return try SQLiteRepositoryQueries.page(query, after: after, limit: limit, in: db)
        }
    }

    func financialPage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) async throws -> RepositoryFinancialPage {
        guard query.collection == .projectFinancialRecords else { throw RepositoryError.invalidRecord("financial query") }
        return try await pool.read { db in
            try SQLiteRepositorySchema.requireReady(db)
            let page = try SQLiteRepositoryQueries.page(query, after: after, limit: limit, in: db)
            let summary = try SQLiteRepositoryQueries.financialSummary(query, in: db)
            return RepositoryFinancialPage(page: page, summary: summary)
        }
    }

    func laborPage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) async throws -> RepositoryLaborPage {
        guard query.collection == .laborRecords else { throw RepositoryError.invalidRecord("labor query") }
        return try await pool.read { db in
            try SQLiteRepositorySchema.requireReady(db)
            let page = try SQLiteRepositoryQueries.page(query, after: after, limit: limit, in: db)
            let summary = try SQLiteLaborQueries.summary(query, in: db)
            return RepositoryLaborPage(page: page, summary: summary)
        }
    }

    func quotePage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) async throws -> RepositoryQuotePage {
        guard query.collection == .quoteItems else { throw RepositoryError.invalidRecord("quote query") }
        return try await pool.read { db in
            try SQLiteRepositorySchema.requireReady(db)
            let page = try SQLiteRepositoryQueries.page(query, after: after, limit: limit, in: db)
            let summary = try SQLiteQuoteQueries.summary(query, in: db)
            return RepositoryQuotePage(page: page, summary: summary)
        }
    }

    func materialPage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) async throws -> RepositoryMaterialPage {
        guard query.collection == .materialItems else { throw RepositoryError.invalidRecord("material query") }
        return try await pool.read { db in
            try SQLiteRepositorySchema.requireReady(db)
            let page = try SQLiteRepositoryQueries.page(query, after: after, limit: limit, in: db)
            let summary = try SQLiteMaterialQueries.summary(query, in: db)
            return RepositoryMaterialPage(page: page, summary: summary)
        }
    }

    func stockPage(_ query: RepositoryStockQuery, after: RepositoryStockCursor?, limit: Int) async throws -> RepositoryStockPage {
        try await pool.read { db in
            try SQLiteRepositorySchema.requireReady(db)
            return try SQLiteWarehouseQueries.stockPage(query, after: after, limit: limit, in: db)
        }
    }

    func summary(_ query: RepositoryQuery) async throws -> RepositorySummary {
        try await pool.read { db in
            try SQLiteRepositorySchema.requireReady(db)
            let (predicate, arguments) = SQLiteRepositoryRows.filter(query)
            let count = try Int.fetchOne(db, sql: "SELECT count(*) FROM \(query.collection.rawValue) WHERE \(predicate)", arguments: arguments) ?? 0
            let amounts = query.collection == .projectFinancialRecords
                ? try Row.fetchAll(db, sql: "SELECT amount, direction FROM projectFinancialRecords WHERE \(predicate)", arguments: arguments)
                : []
            // Decimal arithmetic avoids SQLite SUM coercing decimal text to binary floats.
            return try RepositoryContract.summary(count: count, amounts: amounts.map { ($0["amount"], $0["direction"]) })
        }
    }

    func apply(_ commands: [RepositoryCommand], expectedRevision: Int) async throws -> Int {
        try await pool.write { db in
            try SQLiteRepositorySchema.requireReady(db)
            let revision = try Int.fetchOne(db, sql: "SELECT revision FROM repository_state") ?? 0
            guard revision == expectedRevision else { throw RepositoryError.staleRevision }
            guard !commands.isEmpty else { return revision }
            var changed: [RepositoryRecord] = []
            for command in commands {
                let write = try command.prepare { try SQLiteRepositoryRows.payload($0, id: $1, in: db) }
                switch write {
                case .put(var row):
                    row.position = try Int.fetchOne(db, sql: "SELECT coalesce(max(position), -1) + 1 FROM \(row.collection.rawValue)") ?? 0
                    try SQLiteRepositoryRows.put(row, in: db)
                    changed.append(row)
                case .remove(let collection, let id):
                    try db.execute(sql: "DELETE FROM \(collection.rawValue) WHERE id = ?", arguments: [id])
                    try db.execute(sql: "DELETE FROM record_keys WHERE collection = ? AND id = ?", arguments: [collection.rawValue, id])
                }
            }
            for row in changed { try SQLiteRepositoryRows.relate(row, in: db) }
            for row in changed { try SQLiteRepositoryRows.validateIncoming(to: row, in: db) }
            try db.execute(sql: "UPDATE repository_state SET revision = revision + 1 WHERE singleton = 1")
            return revision + 1
        }
    }

    func exportSnapshot() async throws -> BackupSnapshot {
        try await pool.read { db in
            try SQLiteRepositorySchema.requireReady(db)
            return try SQLiteRepositoryRows.dataset(in: db).snapshot()
        }
    }

    func attachments(owner: RepositoryCollection, id: UUID) async throws -> [RepositoryAttachment] {
        try await pool.read { db in
            try SQLiteRepositorySchema.requireReady(db)
            return try Row.fetchAll(db, sql: "SELECT family, file_name FROM attachment_references WHERE owner_collection = ? AND owner_id = ? ORDER BY family, file_name", arguments: [owner.rawValue, id.uuidString]).map { row in
                let family: String = row["family"]
                guard let family = RepositoryAssetFamily(rawValue: family) else { throw RepositoryError.integrityFailure }
                return RepositoryAttachment(owner: owner, ownerID: id.uuidString, family: family, fileName: row["file_name"])
            }
        }
    }
}
