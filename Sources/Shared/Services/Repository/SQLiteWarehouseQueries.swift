import Foundation
import GRDB

enum SQLiteWarehouseQueries {
    static func fields(_ row: Row, collection: RepositoryCollection) throws -> RepositoryWarehouseFields? {
        guard collection == .projectWarehouseMovements else { return nil }
        return try RepositoryWarehouseFields(object: ["materialName": row["material_name"] as String, "specification": row["specification"] as String,
            "unit": row["unit"] as String, "quantity": row["quantity"] as String, "movementType": row["movement_type"] as String])
    }

    static func stockPage(_ query: RepositoryStockQuery, after: RepositoryStockCursor?, limit: Int, in db: Database) throws -> RepositoryStockPage {
        let revision = try Int.fetchOne(db, sql: "SELECT revision FROM repository_state") ?? 0
        try RepositoryStockContract.check(query, after: after, limit: limit, revision: revision)
        let base = "project_id = ? AND stock_key IS NOT NULL AND instr(stock_search, ?) > 0"
        var arguments: StatementArguments = [query.projectID.uuidString, query.normalizedSearch]
        let total = try Int.fetchOne(db, sql: "SELECT count(DISTINCT stock_key) FROM projectWarehouseMovements WHERE \(base)", arguments: arguments) ?? 0
        let unnamed = try Int.fetchOne(db, sql: "SELECT count(*) FROM projectWarehouseMovements WHERE project_id = ? AND stock_key IS NULL", arguments: [query.projectID.uuidString]) ?? 0
        var predicate = base
        if let after { predicate += " AND stock_key > ?"
        arguments += [after.key] }
        arguments += [limit + 1]
        let groups = try Row.fetchAll(db, sql: "SELECT stock_key, min(id) AS representative FROM projectWarehouseMovements WHERE \(predicate) GROUP BY stock_key ORDER BY stock_key LIMIT ?", arguments: arguments)
        var items: [RepositoryStockLine] = []
        for group in groups.prefix(limit) {
            let key: String = group["stock_key"]
            let representative: String = group["representative"]
            guard let row = try Row.fetchOne(db, sql: "SELECT material_name, specification, unit, quantity, movement_type FROM projectWarehouseMovements WHERE id = ?", arguments: [representative]),
                  let fields = try fields(row, collection: .projectWarehouseMovements), fields.stockKey == key else { throw RepositoryError.integrityFailure }
            // Aggregate the complete material ledger, never just matching movements or the visible page.
            let rows = try Row.fetchCursor(db, sql: "SELECT quantity, movement_type FROM projectWarehouseMovements WHERE project_id = ? AND stock_key = ?", arguments: [query.projectID.uuidString, key])
            var accumulator = RepositoryStockAccumulator()
            while let row = try rows.next() { try accumulator.add(quantity: row["quantity"], type: row["movement_type"]) }
            items.append(try accumulator.line(fields: fields))
        }
        let next = groups.count > limit ? items.last.map { RepositoryStockCursor(query: query, revision: revision, key: $0.id) } : nil
        return RepositoryStockPage(items: items, next: next, revision: revision, totalMaterials: total, unnamedMovements: unnamed)
    }

    static func upgrade(_ db: Database) throws {
        for column in ["material_name", "specification", "unit", "quantity", "movement_type", "stock_search"] {
            try db.execute(sql: "ALTER TABLE projectWarehouseMovements ADD COLUMN \(column) TEXT NOT NULL DEFAULT ''")
        }
        try db.execute(sql: """
            ALTER TABLE projectWarehouseMovements ADD COLUMN stock_key TEXT;
            CREATE INDEX warehouse_stock ON projectWarehouseMovements(project_id, stock_key, id);
            CREATE INDEX warehouse_type_page ON projectWarehouseMovements(project_id, movement_type, sort_key, id);
            """)
        var lastID = ""
        while true {
            let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM projectWarehouseMovements WHERE id > ? ORDER BY id LIMIT 200", arguments: [lastID])
            guard !rows.isEmpty else { break }
            for row in rows {
                let record = try RepositoryRecord(collection: .projectWarehouseMovements, payload: row["payload"], position: 0)
                guard let fields = record.warehouse else { throw RepositoryError.integrityFailure }
                try db.execute(sql: "UPDATE projectWarehouseMovements SET title = ?, search_text = ?, material_name = ?, specification = ?, unit = ?, quantity = ?, movement_type = ?, stock_key = ?, stock_search = ? WHERE id = ?",
                    arguments: [record.title, record.searchText, fields.materialName, fields.specification, fields.unit, fields.quantity, fields.movementType.rawValue, fields.stockKey, fields.stockSearch, record.id])
                lastID = record.id
            }
        }
    }
}

enum RepositoryStockContract {
    static func check(_ query: RepositoryStockQuery, after: RepositoryStockCursor?, limit: Int, revision: Int) throws {
        guard (1...200).contains(limit) else { throw RepositoryError.invalidPageSize }
        if let after {
            guard after.query == query else { throw RepositoryError.invalidCursor }
            guard after.revision == revision else { throw RepositoryError.staleRevision }
        }
    }
}
