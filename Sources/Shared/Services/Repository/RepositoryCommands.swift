import Foundation

enum RepositoryWrite {
    case put(RepositoryRecord)
    case remove(RepositoryCollection, String)
}

extension RepositoryCommand {
    func prepare(fetch: (RepositoryCollection, UUID) throws -> Data?) throws -> RepositoryWrite {
        func row<T: Encodable>(_ value: T, _ collection: RepositoryCollection) throws -> RepositoryWrite {
            .put(try RepositoryRecord(collection: collection, payload: JSONEncoder().encode(value), position: 0))
        }
        switch self {
        case .putProject(let value): return try row(value, .projects)
        case .putDailyLog(let value): return try row(value, .dailyLogs)
        case .putContact(let value):
            try RepositoryContactDraft.validate(value)
            return try row(value, .projectContacts)
        case .putLaborRecord(let value):
            try RepositoryLaborDraft.validate(value)
            return try row(value, .laborRecords)
        case .putQuoteItem(let value):
            try RepositoryQuoteDraft.validate(value)
            return try row(value, .quoteItems)
        case .putMaterialItem(let value):
            try RepositoryMaterialDraft.validate(value)
            return try row(value, .materialItems)
        case .putWarehouseMovement(let value):
            try RepositoryWarehouseDraft.validate(value)
            return try row(value, .projectWarehouseMovements)
        case .putFinancialRecord(let value):
            try Self.validateFinancial(value)
            return try row(value, .projectFinancialRecords)
        case .removeDailyLog, .setTodoCompletion:
            return try prepareExistingRecord(fetch: fetch)
        }
    }

    private func prepareExistingRecord(fetch: (RepositoryCollection, UUID) throws -> Data?) throws -> RepositoryWrite {
        switch self {
        case .removeDailyLog(let id):
            guard try fetch(.dailyLogs, id) != nil else { throw RepositoryError.missingRecord }
            return .remove(.dailyLogs, id.uuidString)
        case .setTodoCompletion(let id, let done, let date):
            guard let data = try fetch(.siteTodos, id) else { throw RepositoryError.missingRecord }
            var todo = try JSONDecoder().decode(SiteTodo.self, from: data)
            todo.isDone = done
            todo.completedAt = done ? date : nil
            return .put(try RepositoryRecord(collection: .siteTodos, payload: JSONEncoder().encode(todo), position: 0))
        default: throw RepositoryError.invalidRecord("existing record command")
        }
    }
    private static func validateFinancial(_ value: ProjectFinancialRecord) throws {
        guard let amount = value.amount.optionalDecimal, amount > .zero else { throw RepositoryError.invalidAmount }
        guard value.direction.supports(value.category) else { throw RepositoryError.invalidRecord("financial category") }
    }
}

/// Compatibility adapter for isolated snapshots. It shares the SQL contract but
/// intentionally retains JSON's full-snapshot cost. Never attach it to the live DataStore writer.
actor JSONSnapshotRepository: BusinessRepository {
    private(set) var dataset: RepositoryDataset
    private(set) var currentRevision = 0
    private let persist: @Sendable (Data) throws -> Void

    init(snapshot: BackupSnapshot, persist: @escaping @Sendable (Data) throws -> Void = { _ in }) throws {
        dataset = try RepositoryDataset(snapshot: snapshot)
        self.persist = persist
    }

    func revision() -> Int { currentRevision }
    func record(_ collection: RepositoryCollection, id: UUID) -> Data? {
        dataset.records[collection]?.first { $0.id == id.uuidString }?.payload
    }

    func detail(_ collection: RepositoryCollection, id: UUID) -> RepositoryDetail? {
        record(collection, id: id).map { RepositoryDetail(payload: $0, revision: currentRevision) }
    }

    func page(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) throws -> RepositoryPage {
        try RepositoryContract.checkPage(query, cursor: after, limit: limit, revision: currentRevision)
        let rows = (dataset.records[query.collection] ?? []).filter { row in
            row.matches(query) && (after.map {
                query.order == .oldestFirst ? (row.sortKey, row.id) > ($0.sortKey, $0.id) : (row.sortKey, row.id) < ($0.sortKey, $0.id)
            } ?? true)
        }.sorted {
            query.order == .oldestFirst ? ($0.sortKey, $0.id) < ($1.sortKey, $1.id) : ($0.sortKey, $0.id) > ($1.sortKey, $1.id)
        }
        let selected = Array(rows.prefix(limit))
        let next = rows.count > limit ? selected.last.map {
            RepositoryCursor(query: query, revision: currentRevision, sortKey: $0.sortKey, id: $0.id)
        } : nil
        return RepositoryPage(items: selected.map(\.listItem), next: next, revision: currentRevision)
    }

    func financialPage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) throws -> RepositoryFinancialPage {
        guard query.collection == .projectFinancialRecords else { throw RepositoryError.invalidRecord("financial query") }
        let page = try page(query, after: after, limit: limit)
        var total = RepositoryFinancialAccumulator()
        for row in dataset.records[.projectFinancialRecords] ?? [] where row.matches(query) {
            try total.add(amount: row.amount, direction: row.direction, status: row.financial?.status.rawValue)
        }
        return RepositoryFinancialPage(page: page, summary: total.result())
    }

    func laborPage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) throws -> RepositoryLaborPage {
        guard query.collection == .laborRecords else { throw RepositoryError.invalidRecord("labor query") }
        let page = try page(query, after: after, limit: limit)
        var total = RepositoryLaborAccumulator()
        for row in dataset.records[.laborRecords] ?? [] where row.matches(query) {
            guard let fields = row.labor else { throw RepositoryError.integrityFailure }
            total.add(fields)
        }
        return RepositoryLaborPage(page: page, summary: total.result())
    }

    func quotePage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) throws -> RepositoryQuotePage {
        guard query.collection == .quoteItems else { throw RepositoryError.invalidRecord("quote query") }
        let page = try page(query, after: after, limit: limit)
        var total = RepositoryQuoteAccumulator()
        for row in dataset.records[.quoteItems] ?? [] where row.matches(query) {
            guard let fields = row.quote else { throw RepositoryError.integrityFailure }
            total.add(fields)
        }
        return RepositoryQuotePage(page: page, summary: total.result())
    }

    func materialPage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) throws -> RepositoryMaterialPage {
        guard query.collection == .materialItems else { throw RepositoryError.invalidRecord("material query") }
        let page = try page(query, after: after, limit: limit)
        var total = RepositoryMaterialAccumulator()
        for row in dataset.records[.materialItems] ?? [] where row.matches(query) {
            guard let fields = row.material else { throw RepositoryError.integrityFailure }
            total.add(quantity: fields.quantity, unitPrice: fields.unitPrice)
        }
        return RepositoryMaterialPage(page: page, summary: total.result())
    }

    func summary(_ query: RepositoryQuery) throws -> RepositorySummary {
        let rows = (dataset.records[query.collection] ?? []).filter { $0.matches(query) }
        return try RepositoryContract.summary(count: rows.count, amounts: rows.map { ($0.amount, $0.direction) })
    }

    func apply(_ commands: [RepositoryCommand], expectedRevision: Int) throws -> Int {
        guard expectedRevision == currentRevision else { throw RepositoryError.staleRevision }
        guard !commands.isEmpty else { return currentRevision }
        var next = dataset
        for command in commands {
            let write = try command.prepare { collection, id in next.records[collection]?.first { $0.id == id.uuidString }?.payload }
            switch write {
            case .put(var row):
                var rows = next.records[row.collection] ?? []
                if let index = rows.firstIndex(where: { $0.id == row.id }) {
                    row.position = rows[index].position
                    rows[index] = row
                } else {
                    row.position = (rows.map(\.position).max() ?? -1) + 1
                    rows.append(row)
                }
                next.records[row.collection] = rows
            case .remove(let collection, let id): next.records[collection]?.removeAll { $0.id == id }
            }
        }
        try next.validate()
        try persist(JSONEncoder().encode(next.snapshot()))
        dataset = next
        currentRevision += 1
        return currentRevision
    }

    func exportSnapshot() throws -> BackupSnapshot { try dataset.snapshot() }

    func attachments(owner: RepositoryCollection, id: UUID) throws -> [RepositoryAttachment] {
        guard let row = dataset.records[owner]?.first(where: { $0.id == id.uuidString }) else { return [] }
        return try RepositoryDataset.attachments(for: row).sorted { ($0.family.rawValue, $0.fileName) < ($1.family.rawValue, $1.fileName) }
    }
}
