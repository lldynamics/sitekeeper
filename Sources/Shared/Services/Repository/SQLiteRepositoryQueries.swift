import Foundation
import GRDB

enum SQLiteRepositoryQueries {
    static func page(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int, in db: Database) throws -> RepositoryPage {
        let revision = try Int.fetchOne(db, sql: "SELECT revision FROM repository_state") ?? 0
        try RepositoryContract.checkPage(query, cursor: after, limit: limit, revision: revision)
        var (predicate, arguments) = SQLiteRepositoryRows.filter(query)
        if let after {
            predicate += query.order == .oldestFirst ? " AND (sort_key, id) > (?, ?)" : " AND (sort_key, id) < (?, ?)"
            arguments += [after.sortKey, after.id]
        }
        arguments += [limit + 1]
        let order = query.order == .oldestFirst ? "ASC" : "DESC"
        let financialColumns = query.collection == .projectFinancialRecords ? ", amount, direction, financial_category, financial_status, counterparty" : ""
        let warehouseColumns = query.collection == .projectWarehouseMovements ? ", material_name, specification, unit, quantity, movement_type" : ""
        let materialColumns = query.collection == .materialItems ? ", quantity, unit_price, unit, specification, brand, supplier, purchase_status" : ""
        let quoteColumns = query.collection == .quoteItems ? ", quantity, unit_price, unit, tax_rate, discount_rate, version_name, quote_status" : ""
        let laborColumns = query.collection == .laborRecords ? ", workers, hours, unit_rate, workload_unit, team_name, work_type, is_settled" : ""
        let contactColumns = query.collection == .projectContacts ? ", contact_role, company, phone" : ""
        // Payloads and long bodies are deliberately not selected for list pages.
        let rows = try Row.fetchAll(db, sql: "SELECT id, project_id, sort_key, title\(financialColumns)\(warehouseColumns)\(materialColumns)\(quoteColumns)\(laborColumns)\(contactColumns) FROM \(query.collection.rawValue) WHERE \(predicate) ORDER BY sort_key \(order), id \(order) LIMIT ?", arguments: arguments)
        let items = try rows.prefix(limit).map { row -> RepositoryListItem in
            let rawID: String = row["id"]
            guard let id = UUID(uuidString: rawID) else { throw RepositoryError.integrityFailure }
            let projectID: String? = row["project_id"]
            return RepositoryListItem(id: id, projectID: projectID.flatMap(UUID.init(uuidString:)), sortKey: row["sort_key"], title: row["title"], financial: try financialFields(row, collection: query.collection), warehouse: try SQLiteWarehouseQueries.fields(row, collection: query.collection), material: try SQLiteMaterialQueries.fields(row, collection: query.collection), quote: try SQLiteQuoteQueries.fields(row, collection: query.collection), labor: try SQLiteLaborQueries.fields(row, collection: query.collection), contact: try SQLiteContactQueries.fields(row, collection: query.collection))
        }
        let next = rows.count > limit ? items.last.map {
            RepositoryCursor(query: query, revision: revision, sortKey: $0.sortKey, id: $0.id.uuidString)
        } : nil
        return RepositoryPage(items: items, next: next, revision: revision)
    }

    static func financialFields(_ row: Row, collection: RepositoryCollection) throws -> RepositoryFinancialFields? {
        guard collection == .projectFinancialRecords else { return nil }
        let direction: String = row["direction"]
        let category: String = row["financial_category"]
        let status: String = row["financial_status"]
        guard let direction = ProjectFinancialDirection(rawValue: direction), let category = ProjectFinancialCategory(rawValue: category),
              let status = ProjectFinancialStatus(rawValue: status) else { throw RepositoryError.integrityFailure }
        return RepositoryFinancialFields(amount: row["amount"], direction: direction, category: category, status: status, counterparty: row["counterparty"])
    }

    static func financialSummary(_ query: RepositoryQuery, in db: Database) throws -> RepositoryFinancialSummary {
        let (predicate, arguments) = SQLiteRepositoryRows.filter(query)
        let rows = try Row.fetchCursor(db, sql: "SELECT amount, direction, financial_status FROM projectFinancialRecords WHERE \(predicate)", arguments: arguments)
        var total = RepositoryFinancialAccumulator()
        while let row = try rows.next() {
            try total.add(amount: row["amount"], direction: row["direction"], status: row["financial_status"])
        }
        return total.result()
    }

    static func upgradeFinancialColumns(_ db: Database) throws {
        try db.execute(sql: """
            ALTER TABLE projectFinancialRecords ADD COLUMN financial_category TEXT NOT NULL DEFAULT '';
            ALTER TABLE projectFinancialRecords ADD COLUMN financial_status TEXT NOT NULL DEFAULT '';
            ALTER TABLE projectFinancialRecords ADD COLUMN counterparty TEXT NOT NULL DEFAULT '';
            CREATE INDEX financial_filtered_page ON projectFinancialRecords(project_id, financial_status, direction, sort_key, id);
            """)
        var lastID = ""
        while true {
            let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM projectFinancialRecords WHERE id > ? ORDER BY id LIMIT 200", arguments: [lastID])
            guard !rows.isEmpty else { break }
            for row in rows {
                let record = try RepositoryRecord(collection: .projectFinancialRecords, payload: row["payload"], position: 0)
                guard let financial = record.financial else { throw RepositoryError.integrityFailure }
                try db.execute(sql: "UPDATE projectFinancialRecords SET title = ?, search_text = ?, financial_category = ?, financial_status = ?, counterparty = ? WHERE id = ?",
                    arguments: [record.title, record.searchText, financial.category.rawValue, financial.status.rawValue, financial.counterparty, record.id])
                lastID = record.id
            }
        }
    }
}
