import Foundation

struct RepositoryRecord: Equatable, Sendable {
    let collection: RepositoryCollection
    let id: String
    let projectID: String?
    let sortKey: String
    let title: String
    let searchText: String
    let amount: String?
    let direction: String?
    let financial: RepositoryFinancialFields?
    let warehouse: RepositoryWarehouseFields?
    let material: RepositoryMaterialFields?
    let quote: RepositoryQuoteFields?
    let labor: RepositoryLaborFields?
    let contact: RepositoryContactFields?
    var position: Int
    let payload: Data

    init(collection: RepositoryCollection, payload: Data, position: Int) throws {
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let rawID = object["id"] as? String, let uuid = UUID(uuidString: rawID) else {
            throw RepositoryError.invalidRecord(collection.rawValue)
        }
        self.collection = collection
        id = uuid.uuidString
        if let value = object["projectId"] as? String {
            guard let uuid = UUID(uuidString: value) else { throw RepositoryError.invalidRecord("projectId") }
            projectID = uuid.uuidString
        } else {
            projectID = nil
        }
        sortKey = Self.dateSortKey(collection: collection, object: object)
        warehouse = collection == .projectWarehouseMovements ? try RepositoryWarehouseFields(object: object) : nil
        material = collection == .materialItems ? try RepositoryMaterialFields(object: object) : nil
        quote = collection == .quoteItems ? RepositoryQuoteFields(object: object) : nil
        labor = collection == .laborRecords ? try RepositoryLaborFields(object: object) : nil
        contact = collection == .projectContacts ? try RepositoryContactFields(object: object) : nil
        financial = try Self.financialFields(collection: collection, object: object)
        title = labor.map { String(($0.teamName.isEmpty ? $0.workType : $0.teamName).prefix(120)) } ?? warehouse.map { String($0.materialName.prefix(120)) } ?? financial.map { String(($0.counterparty.isEmpty ? $0.category.rawValue : $0.counterparty).prefix(120)) } ?? String((object["name"] as? String ?? object["title"] as? String ?? object["content"] as? String ?? "").prefix(120))
        searchText = RepositorySearch.text(collection: collection, object: object)
        amount = collection == .projectFinancialRecords ? object["amount"] as? String : nil
        direction = object["direction"] as? String
        self.position = position
        self.payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    /// Index text is a persistence concern; the live record's source date text
    /// remains untouched in payload. Unknown dates sort separately from instants.
    static func dateSortKey(collection: RepositoryCollection, object: [String: Any]) -> String {
        if collection == .projectContacts { return String(RepositorySearch.normalize(object["name"] as? String ?? "").prefix(240)) }
        let key: String
        switch collection {
        case .projects, .progressTasks: key = "startDate"
        case .siteTodos: key = "dueDate"
        case .quickNotes, .materialPriceEntries, .materialSheetDrafts, .supplierProfiles, .constructionMethods: key = "updatedAt"
        case .materialItems: key = "arrivalDate"
        case .quoteItems: key = "customerConfirmedDate"
        case .projectDrawings: key = "importedAt"
        case .projectDocuments: key = "createdAt"
        default: key = "date"
        }
        return BusinessDateValue(legacyText: object[key] as? String ?? "").sortKey
    }

    var listItem: RepositoryListItem {
        RepositoryListItem(id: UUID(uuidString: id)!, projectID: projectID.flatMap(UUID.init(uuidString:)), sortKey: sortKey, title: title, financial: financial, warehouse: warehouse, material: material, quote: quote, labor: labor, contact: contact)
    }

    func matches(_ query: RepositoryQuery) -> Bool {
        let search = RepositorySearch.normalize(query.searchText)
        guard collection == query.collection, search.isEmpty || searchText.contains(search) else { return false }
        guard matchesDomainFilters(query) else { return false }
        switch query.project {
        case .all: return true
        case .unassigned: return projectID == nil
        case .project(let id):
            if projectID == id.uuidString { return true }
            guard collection == .projectContacts else { return false }
            return (try? RepositoryDataset.links(for: self).contains { $0.field == "relatedProjectIds" && $0.targetID == id.uuidString }) == true
        }
    }
    private func matchesDomainFilters(_ query: RepositoryQuery) -> Bool {
        if let role = query.contactRole, contact?.role != role { return false }
        if let settled = query.laborSettled, labor?.isSettled != settled { return false }
        if let unit = query.laborUnit, labor?.workloadUnit != unit { return false }
        if let status = query.quoteStatus, quote?.status != status { return false }
        if let version = query.quoteVersion, quote?.versionName != version { return false }
        if let status = query.materialStatus, material?.purchaseStatus != status { return false }
        if let type = query.warehouseType, warehouse?.movementType != type { return false }
        if let direction = query.financialDirection, financial?.direction != direction { return false }
        if let status = query.financialStatus, financial?.status != status { return false }
        return true
    }

    private static func financialFields(collection: RepositoryCollection, object: [String: Any]) throws -> RepositoryFinancialFields? {
        guard collection == .projectFinancialRecords else { return nil }
        guard let direction = (object["direction"] as? String).flatMap(ProjectFinancialDirection.init(rawValue:)),
              let category = (object["category"] as? String).flatMap(ProjectFinancialCategory.init(rawValue:)),
              let status = (object["status"] as? String).flatMap(ProjectFinancialStatus.init(rawValue:)) else { throw RepositoryError.invalidRecord("finance") }
        return RepositoryFinancialFields(amount: object["amount"] as? String ?? "", direction: direction, category: category,
            status: status, counterparty: String((object["counterparty"] as? String ?? "").prefix(120)))
    }
}

struct RepositoryLink: Hashable, Sendable {
    let owner: RepositoryCollection
    let ownerID: String
    let field: String
    let target: RepositoryCollection
    let targetID: String
}

enum RepositoryAssetFamily: String, Codable, CaseIterable, Sendable {
    case photos, drawings, documents, attachments
}

struct RepositoryAttachment: Codable, Hashable, Sendable {
    let owner: RepositoryCollection
    let ownerID: String
    let family: RepositoryAssetFamily
    let fileName: String
}

enum RepositoryContract {
    static func checkPage(_ query: RepositoryQuery, cursor: RepositoryCursor?, limit: Int, revision: Int) throws {
        guard (1...200).contains(limit) else { throw RepositoryError.invalidPageSize }
        if let cursor {
            guard cursor.query == query else { throw RepositoryError.invalidCursor }
            guard cursor.revision == revision else { throw RepositoryError.staleRevision }
        }
    }

    static func summary(count: Int, amounts: [(String?, String?)]) throws -> RepositorySummary {
        var income = Decimal.zero
        var expense = Decimal.zero
        for (amount, direction) in amounts {
            guard let amount, !amount.isEmpty else { continue }
            guard let number = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")), !number.isNaN else {
                throw RepositoryError.invalidRecord("amount")
            }
            if direction == ProjectFinancialDirection.income.rawValue { income += number }
            if direction == ProjectFinancialDirection.expense.rawValue { expense += number }
        }
        return RepositorySummary(count: count, income: income, expense: expense)
    }
}

enum RepositoryJSON {
    static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RepositoryError.invalidRecord("object")
        }
        return object
    }
}

/// Search the complete text fields without fetching long JSON bodies into list pages.
enum RepositorySearch {
    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func text(collection: RepositoryCollection, object: [String: Any]) -> String {
        let keys: [String]
        switch collection {
        case .projectContacts: keys = ["name", "company", "phone", "note", "role"]
        case .projects: keys = ["name", "location", "customerName", "customerPhone", "managerName"]
        case .laborRecords: keys = ["teamName", "workType", "note", "date"]
        case .quoteItems: keys = ["name", "unit", "notes", "versionName", "status"]
        case .materialItems: keys = ["name", "specification", "brand", "supplier", "unit", "purchaseStatus"]
        case .dailyLogs: keys = ["content", "weather", "workers", "safety", "materials", "tomorrowPlan", "qualityIssue", "rectification", "confirmer"]
        case .projectWarehouseMovements: keys = ["materialName", "specification", "unit", "counterparty", "handler", "note"]
        case .projectFinancialRecords: keys = ["counterparty", "invoiceNumber", "note", "category", "direction"]
        default: keys = ["name", "title", "content"]
        }
        return normalize(keys.compactMap { object[$0] as? String }.joined(separator: "\n"))
    }
}
