import Foundation
import GRDB

/// SQL helpers only run inside a GRDB read snapshot or write transaction.
enum SQLiteRepositoryRows {
    static func put(_ record: RepositoryRecord, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO record_keys(collection, id, project_id) VALUES (?, ?, ?)
            ON CONFLICT(collection, id) DO UPDATE SET project_id = excluded.project_id
            """, arguments: [record.collection.rawValue, record.id, record.collection == .historyRecords ? nil : record.projectID])
        var arguments: StatementArguments = [record.id, record.projectID, record.sortKey, record.title, record.amount, record.direction, record.position, record.payload, record.searchText]
        let columns: String
        let placeholders: String
        let updates: String
        if let financial = record.financial {
            columns = ", financial_category, financial_status, counterparty"
            placeholders = ", ?, ?, ?"
            updates = ", financial_category=excluded.financial_category, financial_status=excluded.financial_status, counterparty=excluded.counterparty"
            arguments += [financial.category.rawValue, financial.status.rawValue, financial.counterparty]
        } else if let contact = record.contact {
            columns = ", contact_role, company, phone"
            placeholders = ", ?, ?, ?"
            updates = ", contact_role=excluded.contact_role, company=excluded.company, phone=excluded.phone"
            arguments += [contact.role.rawValue, contact.company, contact.phone]
        } else if let labor = record.labor {
            columns = ", workers, hours, unit_rate, workload_unit, team_name, work_type, is_settled"
            placeholders = ", ?, ?, ?, ?, ?, ?, ?"
            updates = ", workers=excluded.workers, hours=excluded.hours, unit_rate=excluded.unit_rate, workload_unit=excluded.workload_unit, team_name=excluded.team_name, work_type=excluded.work_type, is_settled=excluded.is_settled"
            arguments += [labor.workers, labor.hours, labor.unitRate, labor.workloadUnit.rawValue, labor.teamName, labor.workType, labor.isSettled]
        } else if let quote = record.quote {
            columns = ", quantity, unit_price, unit, tax_rate, discount_rate, version_name, quote_status"
            placeholders = ", ?, ?, ?, ?, ?, ?, ?"
            updates = ", quantity=excluded.quantity, unit_price=excluded.unit_price, unit=excluded.unit, tax_rate=excluded.tax_rate, discount_rate=excluded.discount_rate, version_name=excluded.version_name, quote_status=excluded.quote_status"
            arguments += [quote.quantity, quote.unitPrice, quote.unit, quote.taxRate, quote.discountRate, quote.versionName, quote.status.rawValue]
        } else if let material = record.material {
            columns = ", quantity, unit_price, unit, specification, brand, supplier, purchase_status"
            placeholders = ", ?, ?, ?, ?, ?, ?, ?"
            updates = ", quantity=excluded.quantity, unit_price=excluded.unit_price, unit=excluded.unit, specification=excluded.specification, brand=excluded.brand, supplier=excluded.supplier, purchase_status=excluded.purchase_status"
            arguments += [material.quantity, material.unitPrice, material.unit, material.specification, material.brand, material.supplier, material.purchaseStatus.rawValue]
        } else if let warehouse = record.warehouse {
            columns = ", material_name, specification, unit, quantity, movement_type, stock_key, stock_search"
            placeholders = ", ?, ?, ?, ?, ?, ?, ?"
            updates = ", material_name=excluded.material_name, specification=excluded.specification, unit=excluded.unit, quantity=excluded.quantity, movement_type=excluded.movement_type, stock_key=excluded.stock_key, stock_search=excluded.stock_search"
            arguments += [warehouse.materialName, warehouse.specification, warehouse.unit, warehouse.quantity, warehouse.movementType.rawValue, warehouse.stockKey, warehouse.stockSearch]
        } else {
            columns = ""
            placeholders = ""
            updates = ""
        }
        try db.execute(sql: """
            INSERT INTO \(record.collection.rawValue)(id, project_id, sort_key, title, amount, direction, position, payload, search_text\(columns))
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?\(placeholders))
            ON CONFLICT(id) DO UPDATE SET project_id=excluded.project_id, sort_key=excluded.sort_key,
                title=excluded.title, amount=excluded.amount, direction=excluded.direction, payload=excluded.payload, search_text=excluded.search_text\(updates)
            """, arguments: arguments)
    }

    static func relate(_ record: RepositoryRecord, in db: Database) throws {
        try db.execute(sql: "DELETE FROM record_links WHERE owner_collection = ? AND owner_id = ?", arguments: [record.collection.rawValue, record.id])
        for link in try RepositoryDataset.links(for: record) {
            guard let target = try Row.fetchOne(db, sql: "SELECT project_id FROM record_keys WHERE collection = ? AND id = ?", arguments: [link.target.rawValue, link.targetID]) else {
                throw RepositoryError.danglingReference(link.field)
            }
            try RepositoryDataset.checkProjectScope(owner: record, targetProjectID: target["project_id"], link: link)
            try db.execute(sql: "INSERT INTO record_links VALUES (?, ?, ?, ?, ?)", arguments: [link.owner.rawValue, link.ownerID, link.field, link.target.rawValue, link.targetID])
        }
        try db.execute(sql: "DELETE FROM attachment_references WHERE owner_collection = ? AND owner_id = ?", arguments: [record.collection.rawValue, record.id])
        for attachment in try RepositoryDataset.attachments(for: record) {
            try db.execute(sql: "INSERT INTO attachment_references VALUES (?, ?, ?, ?)", arguments: [attachment.owner.rawValue, attachment.ownerID, attachment.family.rawValue, attachment.fileName])
        }
    }

    static func validateIncoming(to record: RepositoryRecord, in db: Database) throws {
        guard record.collection != .projects, record.collection != .constructionMethods else { return }
        let owners = try Row.fetchAll(db, sql: """
            SELECT k.project_id FROM record_links l JOIN record_keys k
            ON k.collection = l.owner_collection AND k.id = l.owner_id
            WHERE l.target_collection = ? AND l.target_id = ?
            """, arguments: [record.collection.rawValue, record.id])
        for owner in owners {
            let projectID: String? = owner["project_id"]
            guard projectID == record.projectID else { throw RepositoryError.crossProjectReference(record.id) }
        }
    }

    static func payload(_ collection: RepositoryCollection, id: UUID, in db: Database) throws -> Data? {
        try Data.fetchOne(db, sql: "SELECT payload FROM \(collection.rawValue) WHERE id = ?", arguments: [id.uuidString])
    }

    static func dataset(in db: Database) throws -> RepositoryDataset {
        let fields = try Row.fetchAll(db, sql: "SELECT name, payload FROM snapshot_fields")
        var root: [String: Any] = [:]
        for field in fields {
            let name: String = field["name"]
            let data: Data = field["payload"]
            root[name] = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        }
        root["legacyDateProvenance"] = try Data.fetchAll(db, sql: "SELECT payload FROM date_provenance ORDER BY position").map {
            try JSONSerialization.jsonObject(with: $0)
        }
        for collection in RepositoryCollection.allCases {
            root[collection.rawValue] = try Data.fetchAll(db, sql: "SELECT payload FROM \(collection.rawValue) ORDER BY position").map {
                try JSONSerialization.jsonObject(with: $0)
            }
        }
        let snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: JSONSerialization.data(withJSONObject: root))
        return try RepositoryDataset(snapshot: snapshot)
    }

    static func verifyDataset(_ expected: RepositoryDataset, in db: Database) throws {
        guard try dataset(in: db) == expected else { throw RepositoryError.preservationMismatch }
        var expectedLinks = Set<RepositoryLink>()
        var expectedAssets: [RepositoryAttachment] = []
        for collection in RepositoryCollection.allCases {
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM \(collection.rawValue) ORDER BY position")
            let originals = expected.records[collection] ?? []
            guard rows.count == originals.count else { throw RepositoryError.preservationMismatch }
            for (stored, original) in zip(rows, originals) {
                let id: String = stored["id"]
                let project: String? = stored["project_id"]
                let sort: String = stored["sort_key"]
                let title: String = stored["title"]
                let amount: String? = stored["amount"]
                let direction: String? = stored["direction"]
                let position: Int = stored["position"]
                guard id == original.id, project == original.projectID, sort == original.sortKey,
                      title == original.title, amount == original.amount, direction == original.direction,
                      position == original.position, (stored["search_text"] as String) == original.searchText else { throw RepositoryError.preservationMismatch }
                try verifyDomainFields(original, stored: stored)
                expectedLinks.formUnion(try RepositoryDataset.links(for: original))
                expectedAssets += try RepositoryDataset.attachments(for: original)
            }
        }
        let links = try Row.fetchAll(db, sql: "SELECT * FROM record_links").map { row -> RepositoryLink in
            let owner: String = row["owner_collection"]
            let target: String = row["target_collection"]
            guard let owner = RepositoryCollection(rawValue: owner), let target = RepositoryCollection(rawValue: target) else {
                throw RepositoryError.integrityFailure
            }
            return RepositoryLink(owner: owner, ownerID: row["owner_id"], field: row["field"], target: target, targetID: row["target_id"])
        }
        let assets = try Row.fetchAll(db, sql: "SELECT * FROM attachment_references").map { row -> RepositoryAttachment in
            let owner: String = row["owner_collection"]
            let family: String = row["family"]
            guard let owner = RepositoryCollection(rawValue: owner), let family = RepositoryAssetFamily(rawValue: family) else {
                throw RepositoryError.integrityFailure
            }
            return RepositoryAttachment(owner: owner, ownerID: row["owner_id"], family: family, fileName: row["file_name"])
        }
        guard Set(links) == expectedLinks, Set(assets) == Set(expectedAssets),
              try Int.fetchOne(db, sql: "SELECT count(*) FROM record_keys") == expected.records.values.reduce(0, { $0 + $1.count }) else {
            throw RepositoryError.preservationMismatch
        }
    }

    private static func verifyDomainFields(_ original: RepositoryRecord, stored: Row) throws {
        guard try SQLiteContactQueries.fields(stored, collection: original.collection) == original.contact,
              try SQLiteRepositoryQueries.financialFields(stored, collection: original.collection) == original.financial,
              try SQLiteWarehouseQueries.fields(stored, collection: original.collection) == original.warehouse,
              try SQLiteMaterialQueries.fields(stored, collection: original.collection) == original.material,
              try SQLiteLaborQueries.fields(stored, collection: original.collection) == original.labor,
              try SQLiteQuoteQueries.fields(stored, collection: original.collection) == original.quote else { throw RepositoryError.preservationMismatch }
        if let fields = original.warehouse {
            guard (stored["stock_key"] as String?) == fields.stockKey, (stored["stock_search"] as String) == fields.stockSearch else { throw RepositoryError.preservationMismatch }
        }
    }

    static func filter(_ query: RepositoryQuery) -> (String, StatementArguments) {
        guard acceptsFilters(query) else { return ("0", []) }
        var (predicate, arguments) = projectFilter(query)
        if let role = query.contactRole {
            predicate += " AND contact_role = ?"
            arguments += [role.rawValue]
        }
        if let settled = query.laborSettled {
            predicate += " AND is_settled = ?"
            arguments += [settled]
        }
        if let unit = query.laborUnit {
            predicate += " AND workload_unit = ?"
            arguments += [unit.rawValue]
        }
        appendQuoteFilter(query, predicate: &predicate, arguments: &arguments)
        if let status = query.materialStatus {
            predicate += " AND purchase_status = ?"
            arguments += [status.rawValue]
        }
        if let type = query.warehouseType {
            predicate += " AND movement_type = ?"
            arguments += [type.rawValue]
        }
        let search = RepositorySearch.normalize(query.searchText)
        if !search.isEmpty {
            predicate += " AND instr(search_text, ?) > 0"
            arguments += [search]
        }
        if let direction = query.financialDirection {
            predicate += " AND direction = ?"
            arguments += [direction.rawValue]
        }
        if let status = query.financialStatus {
            predicate += " AND financial_status = ?"
            arguments += [status.rawValue]
        }
        return (predicate, arguments)
    }

    private static func acceptsFilters(_ query: RepositoryQuery) -> Bool {
        if query.collection != .projectContacts, query.contactRole != nil { return false }
        if query.collection != .projectFinancialRecords, query.financialDirection != nil || query.financialStatus != nil { return false }
        if query.collection != .projectWarehouseMovements, query.warehouseType != nil { return false }
        if query.collection != .materialItems, query.materialStatus != nil { return false }
        if query.collection != .quoteItems, query.quoteStatus != nil || query.quoteVersion != nil { return false }
        if query.collection != .laborRecords, query.laborSettled != nil || query.laborUnit != nil { return false }
        return true
    }

    private static func appendQuoteFilter(_ query: RepositoryQuery, predicate: inout String, arguments: inout StatementArguments) {
        if let status = query.quoteStatus {
            predicate += " AND quote_status = ?"
            arguments += [status.rawValue]
        }
        if let version = query.quoteVersion {
            predicate += " AND version_name = ?"
            arguments += [version]
        }
    }

    private static func projectFilter(_ query: RepositoryQuery) -> (String, StatementArguments) {
        switch query.project {
        case .all: return ("1", [])
        case .unassigned: return ("project_id IS NULL", [])
        case .project(let id):
            if query.collection == .projectContacts {
                return ("(project_id = ? OR EXISTS (SELECT 1 FROM record_links WHERE owner_collection = 'projectContacts' AND owner_id = projectContacts.id AND field = 'relatedProjectIds' AND target_id = ?))", [id.uuidString, id.uuidString])
            }
            return ("project_id = ?", [id.uuidString])
        }
    }
}
