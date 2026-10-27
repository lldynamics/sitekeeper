import Foundation
import GRDB

enum SQLiteQuoteQueries {
    static func fields(_ row: Row, collection: RepositoryCollection) throws -> RepositoryQuoteFields? {
        guard collection == .quoteItems else { return nil }
        let status: String = row["quote_status"]
        guard let status = QuoteStatus(rawValue: status) else { throw RepositoryError.integrityFailure }
        return RepositoryQuoteFields(quantity: row["quantity"], unitPrice: row["unit_price"], unit: row["unit"],
            taxRate: row["tax_rate"], discountRate: row["discount_rate"], versionName: row["version_name"], status: status)
    }

    static func summary(_ query: RepositoryQuery, in db: Database) throws -> RepositoryQuoteSummary {
        let (predicate, arguments) = SQLiteRepositoryRows.filter(query)
        let rows = try Row.fetchCursor(db, sql: "SELECT quantity, unit_price, tax_rate, discount_rate FROM quoteItems WHERE \(predicate)", arguments: arguments)
        var total = RepositoryQuoteAccumulator()
        while let row = try rows.next() {
            total.add(RepositoryQuoteFields(quantity: row["quantity"], unitPrice: row["unit_price"], unit: "",
                taxRate: row["tax_rate"], discountRate: row["discount_rate"], versionName: "", status: .draft))
        }
        return total.result()
    }

    static func upgrade(_ db: Database) throws {
        for column in ["quantity", "unit_price", "unit", "tax_rate", "discount_rate", "version_name", "quote_status"] {
            try db.execute(sql: "ALTER TABLE quoteItems ADD COLUMN \(column) TEXT NOT NULL DEFAULT ''")
        }
        try db.execute(sql: "CREATE INDEX quote_filtered_page ON quoteItems(project_id, quote_status, version_name, sort_key, id)")
        var lastID = ""
        while true {
            let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM quoteItems WHERE id > ? ORDER BY id LIMIT 200", arguments: [lastID])
            guard !rows.isEmpty else { break }
            for row in rows {
                let record = try RepositoryRecord(collection: .quoteItems, payload: row["payload"], position: 0)
                guard record.id == (row["id"] as String), let quote = record.quote else { throw RepositoryError.integrityFailure }
                try db.execute(sql: """
                    UPDATE quoteItems SET sort_key = ?, title = ?, search_text = ?, quantity = ?, unit_price = ?, unit = ?,
                    tax_rate = ?, discount_rate = ?, version_name = ?, quote_status = ? WHERE id = ?
                    """, arguments: [record.sortKey, record.title, record.searchText, quote.quantity, quote.unitPrice, quote.unit,
                                      quote.taxRate, quote.discountRate, quote.versionName, quote.status.rawValue, record.id])
                lastID = record.id
            }
        }
    }
}
