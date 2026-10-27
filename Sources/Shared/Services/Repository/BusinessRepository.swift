import Foundation

/// Table names are a closed set. No user-supplied SQL identifiers enter the repository.
enum RepositoryCollection: String, CaseIterable, Codable, Sendable {
    case projects, dailyLogs, siteTodos, progressTasks, projectDrawings, projectContacts
    case projectFinancialRecords, projectDocuments, projectWarehouseMovements, quickNotes
    case materialItems, quoteItems, laborRecords, historyRecords, templates
    case materialPriceEntries, materialSheetDrafts, supplierProfiles, constructionMethods
    case userMaterials, deletedUserMaterials
}

enum RepositoryError: Error, Equatable {
    case invalidRecord(String)
    case duplicateID(String)
    case danglingReference(String)
    case crossProjectReference(String)
    case invalidQuantity
    case invalidAmount
    case invalidQuoteValues
    case invalidContactName
    case invalidLaborValues
    case invalidMaterialValues
    case invalidPageSize
    case staleRevision
    case invalidCursor
    case missingRecord
    case pendingRestore
    case sourceChanged
    case preservationMismatch
    case invalidCandidate
    case candidateHasNewWrites
    case integrityFailure
    case missingAssetRoot(String)
}

enum RepositoryProjectFilter: Equatable, Sendable {
    case all, unassigned, project(UUID)
}

enum RepositoryOrder: String, CaseIterable, Sendable { case oldestFirst, newestFirst }

struct RepositoryQuery: Equatable, Sendable {
    let collection: RepositoryCollection
    var project: RepositoryProjectFilter = .all
    var searchText = ""
    var order: RepositoryOrder = .oldestFirst
    var financialDirection: ProjectFinancialDirection?
    var financialStatus: ProjectFinancialStatus?
    var warehouseType: WarehouseMovementType?
    var materialStatus: MaterialPurchaseStatus?
    var quoteStatus: QuoteStatus?
    var quoteVersion: String?
    var laborSettled: Bool?
    var laborUnit: LaborWorkloadUnit?
    var contactRole: ProjectContactRole?
}

struct RepositoryCursor: Equatable, Sendable {
    let query: RepositoryQuery
    let revision: Int
    let sortKey: String
    let id: String
}

struct RepositoryListItem: Equatable, Sendable {
    let id: UUID
    let projectID: UUID?
    let sortKey: String
    let title: String
    var financial: RepositoryFinancialFields?
    var warehouse: RepositoryWarehouseFields?
    var material: RepositoryMaterialFields?
    var quote: RepositoryQuoteFields?
    var labor: RepositoryLaborFields?
    var contact: RepositoryContactFields?
}

struct RepositoryDetail: Sendable {
    let payload: Data
    let revision: Int
}

struct RepositoryPage: Sendable {
    let items: [RepositoryListItem]
    let next: RepositoryCursor?
    let revision: Int
}

struct RepositorySummary: Equatable, Sendable {
    let count: Int
    let income: Decimal
    let expense: Decimal
}

enum RepositoryCommand: Sendable {
    case putProject(Project)
    case putDailyLog(DailyLog)
    case removeDailyLog(UUID)
    case setTodoCompletion(UUID, Bool, at: BusinessDateValue)
    case putFinancialRecord(ProjectFinancialRecord)
    case putWarehouseMovement(ProjectWarehouseMovement)
    case putMaterialItem(MaterialItem)
    case putQuoteItem(QuoteItem)
    case putLaborRecord(LaborRecord)
    case putContact(ProjectContact)
}

/// A batch is all-or-nothing. Expected revisions prevent stale editors from
/// silently overwriting changes. A cursor is scoped to its query and revision.
protocol BusinessRepository: Sendable {
    func revision() async throws -> Int
    func record(_ collection: RepositoryCollection, id: UUID) async throws -> Data?
    func detail(_ collection: RepositoryCollection, id: UUID) async throws -> RepositoryDetail?
    func page(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) async throws -> RepositoryPage
    func financialPage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) async throws -> RepositoryFinancialPage
    func laborPage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) async throws -> RepositoryLaborPage
    func quotePage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) async throws -> RepositoryQuotePage
    func materialPage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) async throws -> RepositoryMaterialPage
    func stockPage(_ query: RepositoryStockQuery, after: RepositoryStockCursor?, limit: Int) async throws -> RepositoryStockPage
    func summary(_ query: RepositoryQuery) async throws -> RepositorySummary
    func apply(_ commands: [RepositoryCommand], expectedRevision: Int) async throws -> Int
    func exportSnapshot() async throws -> BackupSnapshot
    func attachments(owner: RepositoryCollection, id: UUID) async throws -> [RepositoryAttachment]
}

struct ProjectRepository: Sendable {
    let repository: any BusinessRepository

    func projects(after: RepositoryCursor? = nil, limit: Int = 50) async throws -> RepositoryPage {
        try await repository.page(RepositoryQuery(collection: .projects), after: after, limit: limit)
    }

    func dailyLogs(projectID: UUID, after: RepositoryCursor? = nil, limit: Int = 50) async throws -> RepositoryPage {
        try await repository.page(RepositoryQuery(collection: .dailyLogs, project: .project(projectID)), after: after, limit: limit)
    }

    func dailyLog(id: UUID) async throws -> DailyLog? {
        guard let data = try await repository.record(.dailyLogs, id: id) else { return nil }
        return try JSONDecoder().decode(DailyLog.self, from: data)
    }
}

struct FinanceRepository: Sendable {
    let repository: any BusinessRepository

    func page(_ query: RepositoryQuery, after: RepositoryCursor? = nil, limit: Int = 50) async throws -> RepositoryFinancialPage {
        guard query.collection == .projectFinancialRecords else { throw RepositoryError.invalidRecord("financial query") }
        return try await repository.financialPage(query, after: after, limit: limit)
    }

    /// Legacy migration reconciliation across all statuses; UI totals come from page().
    func summary(projectID: UUID) async throws -> RepositorySummary {
        try await repository.summary(RepositoryQuery(collection: .projectFinancialRecords, project: .project(projectID)))
    }
}

struct AttachmentRepository: Sendable {
    let repository: any BusinessRepository

    func references(owner: RepositoryCollection, id: UUID) async throws -> [RepositoryAttachment] {
        try await repository.attachments(owner: owner, id: id)
    }
}
