import Foundation

struct DataHealthScanInput: Sendable {
    var projects: [Project] = []
    var dailyLogs: [DailyLog] = []
    var siteTodos: [SiteTodo] = []
    var projectDocuments: [ProjectDocument] = []
    var quickNotes: [QuickNote] = []
    var constructionMethods: [ConstructionMethod] = []
    var projectFinancialRecords: [ProjectFinancialRecord] = []
    var projectWarehouseMovements: [ProjectWarehouseMovement] = []
    var materialItems: [MaterialItem] = []
    var quoteItems: [QuoteItem] = []
    var laborRecords: [LaborRecord] = []
    var progressTasks: [ProgressTask] = []
    var projectDrawings: [ProjectDrawing] = []
    var projectContacts: [ProjectContact] = []
    var historyRecords: [HistoryRecord] = []
    var storageIssues: [String] = []
}

extension DataHealthScanInput {
    @MainActor
    init(store: DataStore) {
        self.init(
            projects: store.projects,
            dailyLogs: store.dailyLogs,
            siteTodos: store.siteTodos,
            projectDocuments: store.projectDocuments,
            quickNotes: store.quickNotes,
            constructionMethods: store.constructionMethods,
            projectFinancialRecords: store.projectFinancialRecords,
            projectWarehouseMovements: store.projectWarehouseMovements,
            materialItems: store.materialItems,
            quoteItems: store.quoteItems,
            laborRecords: store.laborRecords,
            progressTasks: store.progressTasks,
            projectDrawings: store.projectDrawings,
            projectContacts: store.projectContacts,
            historyRecords: store.historyRecords,
            storageIssues: StorageIssueLog.entries()
        )
    }
}

/// Serializes scans on its own executor. Inputs are value snapshots; the worker
/// never reads a live observable store or mutates UI state.
actor DataHealthScanWorker {
    typealias Scan = @Sendable (DataHealthScanInput, DataHealthScanReason, Bool) -> DataHealthScanSummary
    private let scanImplementation: Scan

    init(scan: @escaping Scan = { input, reason, includeMetrics in
        DataHealthScanner.scan(input: input, reason: reason, includeSupplementalMetrics: includeMetrics)
    }) {
        scanImplementation = scan
    }

    func scan(
        input: DataHealthScanInput,
        reason: DataHealthScanReason,
        includeSupplementalMetrics: Bool
    ) throws -> DataHealthScanSummary {
        try Task.checkCancellation()
        let result = scanImplementation(input, reason, includeSupplementalMetrics)
        try Task.checkCancellation()
        return result
    }
}
