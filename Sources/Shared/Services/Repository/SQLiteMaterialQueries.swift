import Foundation
import GRDB

enum SQLiteMaterialQueries {
    static func fields(_ row: Row, collection: RepositoryCollection) throws -> RepositoryMaterialFields? {
        guard collection == .materialItems else { return nil }
        let status: String = row["purchase_status"]
        guard let status = MaterialPurchaseStatus(rawValue: status) else { throw RepositoryError.integrityFailure }
        return RepositoryMaterialFields(quantity: row["quantity"], unitPrice: row["unit_price"], unit: row["unit"],
            specification: row["specification"], brand: row["brand"], supplier: row["supplier"], purchaseStatus: status)
    }

    static func summary(_ query: RepositoryQuery, in db: Database) throws -> RepositoryMaterialSummary {
        let (predicate, arguments) = SQLiteRepositoryRows.filter(query)
        let rows = try Row.fetchCursor(db, sql: "SELECT quantity, unit_price FROM materialItems WHERE \(predicate)", arguments: arguments)
        var total = RepositoryMaterialAccumulator()
        while let row = try rows.next() { total.add(quantity: row["quantity"], unitPrice: row["unit_price"]) }
        return total.result()
    }

    static func upgrade(_ db: Database) throws {
        for column in ["quantity", "unit_price", "unit", "specification", "brand", "supplier", "purchase_status"] {
            try db.execute(sql: "ALTER TABLE materialItems ADD COLUMN \(column) TEXT NOT NULL DEFAULT ''")
        }
        try db.execute(sql: "CREATE INDEX material_status_page ON materialItems(project_id, purchase_status, sort_key, id)")
        var lastID = ""
        while true {
            let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM materialItems WHERE id > ? ORDER BY id LIMIT 200", arguments: [lastID])
            guard !rows.isEmpty else { break }
            for row in rows {
                let record = try RepositoryRecord(collection: .materialItems, payload: row["payload"], position: 0)
                guard let material = record.material else { throw RepositoryError.integrityFailure }
                try db.execute(sql: """
                    UPDATE materialItems SET sort_key = ?, title = ?, search_text = ?, quantity = ?, unit_price = ?, unit = ?,
                    specification = ?, brand = ?, supplier = ?, purchase_status = ? WHERE id = ?
                    """, arguments: [record.sortKey, record.title, record.searchText, material.quantity, material.unitPrice, material.unit,
                                      material.specification, material.brand, material.supplier, material.purchaseStatus.rawValue, record.id])
                lastID = record.id
            }
        }
    }
}
