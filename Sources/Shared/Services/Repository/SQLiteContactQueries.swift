import Foundation
import GRDB

enum SQLiteContactQueries {
    static func fields(_ row: Row, collection: RepositoryCollection) throws -> RepositoryContactFields? {
        guard collection == .projectContacts else { return nil }
        let raw: String = row["contact_role"]
        guard let role = ProjectContactRole(rawValue: raw) else { throw RepositoryError.integrityFailure }
        return RepositoryContactFields(role: role, company: row["company"], phone: row["phone"])
    }

    static func upgrade(_ db: Database) throws {
        for column in ["contact_role", "company", "phone"] {
            try db.execute(sql: "ALTER TABLE projectContacts ADD COLUMN \(column) TEXT NOT NULL DEFAULT ''")
        }
        try db.execute(sql: "CREATE INDEX contact_filtered_page ON projectContacts(contact_role, sort_key, id)")
        try db.execute(sql: "CREATE INDEX contact_project_page ON projectContacts(project_id, contact_role, sort_key, id)")
        var lastID = ""
        while true {
            let rows = try Row.fetchAll(db, sql: "SELECT id, project_id, payload FROM projectContacts WHERE id > ? ORDER BY id LIMIT 200", arguments: [lastID])
            guard !rows.isEmpty else { break }
            for row in rows {
                let record = try RepositoryRecord(collection: .projectContacts, payload: row["payload"], position: 0)
                guard record.id == (row["id"] as String), record.projectID == (row["project_id"] as String?), let fields = record.contact else { throw RepositoryError.integrityFailure }
                let expectedLinks = Set(try RepositoryDataset.links(for: record).map(\.targetID))
                let storedLinks = Set(try String.fetchAll(db, sql: "SELECT target_id FROM record_links WHERE owner_collection = 'projectContacts' AND owner_id = ? AND field = 'relatedProjectIds' AND target_collection = 'projects'", arguments: [record.id]))
                guard expectedLinks == storedLinks else { throw RepositoryError.integrityFailure }
                try db.execute(sql: """
                    UPDATE projectContacts SET sort_key = ?, title = ?, search_text = ?, contact_role = ?, company = ?, phone = ? WHERE id = ?
                    """, arguments: [record.sortKey, record.title, record.searchText, fields.role.rawValue, fields.company, fields.phone, record.id])
                lastID = record.id
            }
        }
    }
}
