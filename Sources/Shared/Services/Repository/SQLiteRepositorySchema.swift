import Foundation
import GRDB

/// The candidate schema is versioned independently from the public backup format.
enum SQLiteRepositorySchema {
    static func create(in pool: DatabasePool) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("candidate-v1") { db in
            try db.execute(sql: """
                CREATE TABLE repository_state (
                    singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
                    revision INTEGER NOT NULL, disposition TEXT NOT NULL
                );
                INSERT INTO repository_state VALUES (1, 0, 'building');
                CREATE TABLE snapshot_fields (name TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL);
                CREATE TABLE record_keys (
                    collection TEXT NOT NULL, id TEXT NOT NULL, project_id TEXT,
                    PRIMARY KEY (collection, id),
                    FOREIGN KEY(project_id) REFERENCES projects(id) DEFERRABLE INITIALLY DEFERRED
                );
                """)
            for collection in RepositoryCollection.allCases {
                let name = collection.rawValue
                try db.execute(sql: """
                    CREATE TABLE \(name) (
                        collection TEXT NOT NULL DEFAULT '\(name)' CHECK(collection = '\(name)'),
                        id TEXT PRIMARY KEY NOT NULL, project_id TEXT, sort_key TEXT NOT NULL,
                        title TEXT NOT NULL, amount TEXT, direction TEXT, position INTEGER NOT NULL,
                        payload BLOB NOT NULL,
                        FOREIGN KEY(collection, id) REFERENCES record_keys(collection, id) DEFERRABLE INITIALLY DEFERRED
                    );
                    CREATE INDEX \(name)_project_page ON \(name)(project_id, sort_key, id);
                    CREATE INDEX \(name)_page ON \(name)(sort_key, id);
                    """)
            }
            try db.execute(sql: """
                CREATE TABLE record_links (
                    owner_collection TEXT NOT NULL, owner_id TEXT NOT NULL, field TEXT NOT NULL,
                    target_collection TEXT NOT NULL, target_id TEXT NOT NULL,
                    PRIMARY KEY(owner_collection, owner_id, field, target_collection, target_id),
                    FOREIGN KEY(owner_collection, owner_id) REFERENCES record_keys(collection, id) ON DELETE CASCADE,
                    FOREIGN KEY(target_collection, target_id) REFERENCES record_keys(collection, id) DEFERRABLE INITIALLY DEFERRED
                );
                CREATE INDEX record_links_target ON record_links(target_collection, target_id);
                CREATE TABLE attachment_references (
                    owner_collection TEXT NOT NULL, owner_id TEXT NOT NULL, family TEXT NOT NULL, file_name TEXT NOT NULL,
                    PRIMARY KEY(owner_collection, owner_id, family, file_name),
                    FOREIGN KEY(owner_collection, owner_id) REFERENCES record_keys(collection, id) ON DELETE CASCADE
                );
                CREATE TABLE date_provenance (position INTEGER PRIMARY KEY, payload BLOB NOT NULL);
                """)
        }
        registerDomainMigrations(in: &migrator)
        try migrator.migrate(pool)
    }

    private static func registerDomainMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("candidate-v2-search") { db in try addSearchColumns(to: db) }
        migrator.registerMigration("candidate-v3-finance") { db in try SQLiteRepositoryQueries.upgradeFinancialColumns(db) }
        migrator.registerMigration("candidate-v4-warehouse") { db in try SQLiteWarehouseQueries.upgrade(db) }
        migrator.registerMigration("candidate-v5-materials") { db in try SQLiteMaterialQueries.upgrade(db) }
        migrator.registerMigration("candidate-v6-quotes") { db in try SQLiteQuoteQueries.upgrade(db) }
        migrator.registerMigration("candidate-v7-domain-dates") { db in try upgradeDateSortKeys(in: db) }
        migrator.registerMigration("candidate-v8-labor") { db in try SQLiteLaborQueries.upgrade(db) }
        migrator.registerMigration("candidate-v9-contacts") { db in try SQLiteContactQueries.upgrade(db) }
    }

    /// GRDB runs this in a transaction. Only derived indexes change; payload,
    /// revision, source JSON, attachments and provenance keep their original bytes.
    private static func upgradeDateSortKeys(in db: Database) throws {
        for collection in RepositoryCollection.allCases {
            var lastID = ""
            while true {
                let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM \(collection.rawValue) WHERE id > ? ORDER BY id LIMIT 200", arguments: [lastID])
                guard !rows.isEmpty else { break }
                for row in rows {
                    let id: String = row["id"]
                    let payload: Data = row["payload"]
                    let key = RepositoryRecord.dateSortKey(collection: collection, object: try RepositoryJSON.object(payload))
                    try db.execute(sql: "UPDATE \(collection.rawValue) SET sort_key = ? WHERE id = ?", arguments: [key, id])
                    lastID = id
                }
            }
        }
    }

    private static func addSearchColumns(to db: Database) throws {
        for collection in RepositoryCollection.allCases {
            try db.execute(sql: "ALTER TABLE \(collection.rawValue) ADD COLUMN search_text TEXT NOT NULL DEFAULT ''")
            try db.execute(sql: "CREATE INDEX \(collection.rawValue)_position ON \(collection.rawValue)(position)")
            var lastID = ""
            while true {
                let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM \(collection.rawValue) WHERE id > ? ORDER BY id LIMIT 200", arguments: [lastID])
                guard !rows.isEmpty else { break }
                for row in rows {
                    let payload: Data = row["payload"]
                    let id: String = row["id"]
                    let text = RepositorySearch.text(collection: collection, object: try RepositoryJSON.object(payload))
                    try db.execute(sql: "UPDATE \(collection.rawValue) SET search_text = ? WHERE id = ?", arguments: [text, id])
                    lastID = id
                }
            }
        }
    }

    static func makePool(at url: URL, create: Bool, statementObserver: (@Sendable (String) -> Void)? = nil) throws -> DatabasePool {
        if !create, !FileManager.default.fileExists(atPath: url.path) { throw RepositoryError.invalidCandidate }
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA synchronous = FULL")
            if let statementObserver {
                db.trace { event in
                    if case .statement(let statement) = event { statementObserver(statement.sql) }
                }
            }
        }
        return try DatabasePool(path: url.path, configuration: configuration)
    }

    static func verify(_ db: Database) throws {
        guard try String.fetchOne(db, sql: "PRAGMA integrity_check") == "ok",
              try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty,
              try Int.fetchOne(db, sql: "PRAGMA foreign_keys") == 1 else { throw RepositoryError.integrityFailure }
    }

    static func requireReady(_ db: Database) throws {
        guard try String.fetchOne(db, sql: "SELECT disposition FROM repository_state WHERE singleton = 1") == "ready" else {
            throw RepositoryError.invalidCandidate
        }
    }
}
