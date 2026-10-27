import Foundation

extension JSONSnapshotRepository {
    func stockPage(_ query: RepositoryStockQuery, after: RepositoryStockCursor?, limit: Int) throws -> RepositoryStockPage {
        try RepositoryStockContract.check(query, after: after, limit: limit, revision: currentRevision)
        let rows = (dataset.records[.projectWarehouseMovements] ?? []).filter { $0.projectID == query.projectID.uuidString }
        var groups: [String: [RepositoryRecord]] = [:]
        for row in rows {
            if let key = row.warehouse?.stockKey { groups[key, default: []].append(row) }
        }
        let keys = groups.keys.filter { key in
            groups[key]!.contains { (query.normalizedSearch.isEmpty || $0.warehouse?.stockSearch.contains(query.normalizedSearch) == true) }
        }.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        let visible = keys.filter { key in after.map { $0.key.utf8.lexicographicallyPrecedes(key.utf8) } ?? true }.prefix(limit + 1)
        let items = try visible.prefix(limit).map { key -> RepositoryStockLine in
            let group = groups[key]!.sorted { $0.id < $1.id }
            guard let fields = group.first(where: { (query.normalizedSearch.isEmpty || $0.warehouse?.stockSearch.contains(query.normalizedSearch) == true) })?.warehouse else { throw RepositoryError.integrityFailure }
            var accumulator = RepositoryStockAccumulator()
            for row in group { try accumulator.add(quantity: row.warehouse?.quantity, type: row.warehouse?.movementType.rawValue) }
            return try accumulator.line(fields: fields)
        }
        let next = visible.count > limit ? items.last.map { RepositoryStockCursor(query: query, revision: currentRevision, key: $0.id) } : nil
        return RepositoryStockPage(items: items, next: next, revision: currentRevision, totalMaterials: keys.count,
            unnamedMovements: rows.filter { $0.warehouse?.stockKey == nil }.count)
    }
}
