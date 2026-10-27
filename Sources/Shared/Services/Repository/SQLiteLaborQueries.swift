import Foundation
import GRDB

enum SQLiteLaborQueries {
    static func fields(_ row: Row, collection: RepositoryCollection) throws -> RepositoryLaborFields? {
        guard collection == .laborRecords else { return nil }
        let raw: String = row["workload_unit"]
        guard let unit = LaborWorkloadUnit(rawValue: raw) else { throw RepositoryError.integrityFailure }
        return RepositoryLaborFields(workers: row["workers"], hours: row["hours"], unitRate: row["unit_rate"], workloadUnit: unit,
            teamName: row["team_name"], workType: row["work_type"], isSettled: row["is_settled"])
    }

    static func summary(_ query: RepositoryQuery, in db: Database) throws -> RepositoryLaborSummary {
        let (predicate, arguments) = SQLiteRepositoryRows.filter(query)
        let rows = try Row.fetchCursor(db, sql: "SELECT workers, hours, unit_rate, workload_unit, is_settled FROM laborRecords WHERE \(predicate)", arguments: arguments)
        var total = RepositoryLaborAccumulator()
        while let row = try rows.next() {
            let raw: String = row["workload_unit"]
            guard let unit = LaborWorkloadUnit(rawValue: raw) else { throw RepositoryError.integrityFailure }
            total.add(RepositoryLaborFields(workers: row["workers"], hours: row["hours"], unitRate: row["unit_rate"], workloadUnit: unit,
                teamName: "", workType: "", isSettled: row["is_settled"]))
        }
        return total.result()
    }

    static func upgrade(_ db: Database) throws {
        for column in ["workers", "hours", "unit_rate", "workload_unit", "team_name", "work_type"] {
            try db.execute(sql: "ALTER TABLE laborRecords ADD COLUMN \(column) TEXT NOT NULL DEFAULT ''")
        }
        try db.execute(sql: "ALTER TABLE laborRecords ADD COLUMN is_settled INTEGER NOT NULL DEFAULT 0 CHECK(is_settled IN (0, 1))")
        try db.execute(sql: "CREATE INDEX labor_filtered_page ON laborRecords(project_id, is_settled, workload_unit, sort_key, id)")
        var lastID = ""
        while true {
            let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM laborRecords WHERE id > ? ORDER BY id LIMIT 200", arguments: [lastID])
            guard !rows.isEmpty else { break }
            for row in rows {
                let record = try RepositoryRecord(collection: .laborRecords, payload: row["payload"], position: 0)
                guard record.id == (row["id"] as String), let fields = record.labor else { throw RepositoryError.integrityFailure }
                try db.execute(sql: """
                    UPDATE laborRecords SET sort_key = ?, title = ?, search_text = ?, workers = ?, hours = ?, unit_rate = ?,
                    workload_unit = ?, team_name = ?, work_type = ?, is_settled = ? WHERE id = ?
                    """, arguments: [record.sortKey, record.title, record.searchText, fields.workers, fields.hours, fields.unitRate,
                                      fields.workloadUnit.rawValue, fields.teamName, fields.workType, fields.isSettled, record.id])
                lastID = record.id
            }
        }
    }
}
