import Foundation

struct DataStoreProjectDeletionSnapshot {
    let projects: [Project]
    let materialItems: [MaterialItem]
    let quoteItems: [QuoteItem]
    let laborRecords: [LaborRecord]
    let dailyLogs: [DailyLog]
    let progressTasks: [ProgressTask]
    let siteTodos: [SiteTodo]
    let projectDrawings: [ProjectDrawing]
    let projectContacts: [ProjectContact]
    let projectFinancialRecords: [ProjectFinancialRecord]
    let projectDocuments: [ProjectDocument]
    let quickNotes: [QuickNote]
    let projectWarehouseMovements: [ProjectWarehouseMovement]
    let materialSheetDrafts: [MaterialSheetDraft]
}

struct DataStoreProjectDeletionResult {
    let projectId: UUID
    let snapshot: DataStoreProjectDeletionSnapshot
    let removedProject: Project?
    let deletedRecordCount: Int
    var audit: DataStoreDeletionAuditContext?
    var deferredFileCleanup: DataStoreDeferredFileCleanup?

    var isEmpty: Bool { removedProject == nil }

    func performDeferredFileCleanup() {
        deferredFileCleanup?.perform()
    }

    func recordAuditStarted() {
        audit?.record(outcome: .started)
    }

    func recordAuditSucceeded() {
        audit?.record(outcome: .succeeded)
    }

    func recordAuditCancelled() {
        audit?.record(outcome: .cancelled)
    }
}
