import Foundation

struct StorageCleanupUndoSnapshot: Codable, Sendable {
    let dailyLogs: [DailyLog]
    let siteTodos: [SiteTodo]
    let quickNotes: [QuickNote]
    let projectDrawings: [ProjectDrawing]
    let projectDocuments: [ProjectDocument]
    let projectFinancialRecords: [ProjectFinancialRecord]
    let projectWarehouseMovements: [ProjectWarehouseMovement]

    @MainActor
    static func capture(from store: DataStore) -> StorageCleanupUndoSnapshot {
        StorageCleanupUndoSnapshot(
            dailyLogs: store.dailyLogs,
            siteTodos: store.siteTodos,
            quickNotes: store.quickNotes,
            projectDrawings: store.projectDrawings,
            projectDocuments: store.projectDocuments,
            projectFinancialRecords: store.projectFinancialRecords,
            projectWarehouseMovements: store.projectWarehouseMovements
        )
    }

    @MainActor
    func restore(into store: DataStore) {
        store.replaceDailyLogs(dailyLogs)
        store.replaceSiteTodos(siteTodos)
        store.replaceQuickNotes(quickNotes)
        store.replaceProjectDrawings(projectDrawings)
        store.replaceProjectDocuments(projectDocuments)
        store.replaceProjectFinancialRecords(projectFinancialRecords)
        store.replaceProjectWarehouseMovements(projectWarehouseMovements)
    }
}

struct DeferredProjectFileCleanupPlan: Codable, Sendable {
    var photoFileNames: Set<String> = []
    var quickNoteAttachmentFileNames: Set<String> = []
    var projectDocumentFileNames: Set<String> = []
    var drawingFileNames: Set<String> = []

    init(
        photoFileNames: Set<String> = [],
        quickNoteAttachmentFileNames: Set<String> = [],
        projectDocumentFileNames: Set<String> = [],
        drawingFileNames: Set<String> = []
    ) {
        self.photoFileNames = photoFileNames
        self.quickNoteAttachmentFileNames = quickNoteAttachmentFileNames
        self.projectDocumentFileNames = projectDocumentFileNames
        self.drawingFileNames = drawingFileNames
    }

    init(_ result: DataStoreProjectFileCleanupResult) {
        self.init(
            photoFileNames: result.photoFileNames,
            quickNoteAttachmentFileNames: result.quickNoteAttachmentFileNames,
            projectDocumentFileNames: result.projectDocumentFileNames,
            drawingFileNames: result.drawingFileNames
        )
    }

    var totalFileCount: Int {
        photoFileNames.count
            + quickNoteAttachmentFileNames.count
            + projectDocumentFileNames.count
            + drawingFileNames.count
    }

    mutating func merge(_ other: DeferredProjectFileCleanupPlan) {
        photoFileNames.formUnion(other.photoFileNames)
        quickNoteAttachmentFileNames.formUnion(other.quickNoteAttachmentFileNames)
        projectDocumentFileNames.formUnion(other.projectDocumentFileNames)
        drawingFileNames.formUnion(other.drawingFileNames)
    }
}
