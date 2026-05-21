import Foundation

enum DataHealthScanReason: String, Codable, Hashable {
    case startup
    case scheduled
    case dataChanged
    case manual
}

struct DataHealthScanSummary: Codable, Equatable {
    let scannedAt: Date
    let reason: DataHealthScanReason
    let missingPhotoFiles: Int
    let missingDocumentFiles: Int
    let missingQuickNoteAttachmentFiles: Int
    let orphanPhotoFiles: Int
    let orphanDrawingFiles: Int
    let orphanDocumentFiles: Int
    let orphanQuickNoteAttachmentFiles: Int
    let orphanAttachmentMappings: Int
    let orphanWarehouseAttachmentMappings: Int
    let danglingDocumentLinks: Int
    let invalidProjectRefs: Int
    let storageIssues: Int

    var totalIssues: Int {
        missingPhotoFiles
            + missingDocumentFiles
            + missingQuickNoteAttachmentFiles
            + orphanPhotoFiles
            + orphanDrawingFiles
            + orphanDocumentFiles
            + orphanQuickNoteAttachmentFiles
            + orphanAttachmentMappings
            + orphanWarehouseAttachmentMappings
            + danglingDocumentLinks
            + invalidProjectRefs
            + storageIssues
    }

    var hasIssues: Bool {
        totalIssues > 0
    }
}

struct DataHealthScanInput {
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
            storageIssues: StorageIssueLog.entries()
        )
    }
}

struct DataHealthScanStorage {
    var photoExists: (String) -> Bool = PhotoStorage.exists(fileName:)
    var projectDocumentExists: (String) -> Bool = ProjectDocumentStorage.exists(fileName:)
    var quickNoteAttachmentExists: (String) -> Bool = QuickNoteAttachmentStorage.exists(fileName:)
    var orphanPhotoFileNames: ([DailyLog], [SiteTodo]) -> [String] = PhotoStorage.orphanFileNames(logs:todos:)
    var orphanDrawingFileNames: ([ProjectDrawing]) -> [String] = DrawingStorage.orphanFileNames(for:)
    var orphanProjectDocumentFileNames: ([ProjectDocument]) -> [String] = ProjectDocumentStorage.orphanFileNames(for:)
    var orphanQuickNoteAttachmentFileNames: ([QuickNote], [QuickNoteAttachment]) -> [String] = QuickNoteAttachmentStorage.orphanFileNames(for:extraAttachments:)
}

enum DataHealthScanner {
    static func scan(
        input: DataHealthScanInput,
        reason: DataHealthScanReason,
        scannedAt: Date = Date(),
        storage: DataHealthScanStorage = DataHealthScanStorage()
    ) -> DataHealthScanSummary {
        let projectIds = Set(input.projects.map(\.id))
        let documentIds = Set(input.projectDocuments.map(\.id))
        let financialRecordIds = Set(input.projectFinancialRecords.map(\.id))
        let quickNoteAttachments = input.quickNotes.flatMap(\.attachments)
        let methodAttachments = input.constructionMethods.flatMap(\.attachments)
            + input.constructionMethods.flatMap(\.tutorialAttachments)
        let allQuickNoteAttachments = quickNoteAttachments + methodAttachments
        let referencedPhotoNames = Set(
            input.dailyLogs.flatMap(\.allPhotoFileNames)
                + input.siteTodos.flatMap { [$0.rectificationBeforePhotoFileName, $0.rectificationAfterPhotoFileName].compactMap { $0 } }
        )

        let missingPhotoFiles = referencedPhotoNames.filter { !storage.photoExists($0) }.count
        let missingDocumentFiles = input.projectDocuments.filter { !storage.projectDocumentExists($0.fileName) }.count
        let missingQuickNoteAttachmentFiles = allQuickNoteAttachments.filter {
            !storage.quickNoteAttachmentExists($0.fileName)
        }.count
        let orphanAttachmentMappings = input.projectFinancialRecords.reduce(0) { count, record in
            count + record.linkedDocumentIds.filter { !documentIds.contains($0) }.count
        }
        let orphanWarehouseAttachmentMappings = input.projectWarehouseMovements.reduce(0) { count, movement in
            count + movement.linkedDocumentIds.filter { !documentIds.contains($0) }.count
        }
        let danglingDocumentLinks = input.projectDocuments.filter { document in
            guard let linkedId = document.linkedFinancialRecordId else { return false }
            return !financialRecordIds.contains(linkedId)
        }.count

        return DataHealthScanSummary(
            scannedAt: scannedAt,
            reason: reason,
            missingPhotoFiles: missingPhotoFiles,
            missingDocumentFiles: missingDocumentFiles,
            missingQuickNoteAttachmentFiles: missingQuickNoteAttachmentFiles,
            orphanPhotoFiles: storage.orphanPhotoFileNames(input.dailyLogs, input.siteTodos).count,
            orphanDrawingFiles: storage.orphanDrawingFileNames(input.projectDrawings).count,
            orphanDocumentFiles: storage.orphanProjectDocumentFileNames(input.projectDocuments).count,
            orphanQuickNoteAttachmentFiles: storage.orphanQuickNoteAttachmentFileNames(input.quickNotes, methodAttachments).count,
            orphanAttachmentMappings: orphanAttachmentMappings,
            orphanWarehouseAttachmentMappings: orphanWarehouseAttachmentMappings,
            danglingDocumentLinks: danglingDocumentLinks,
            invalidProjectRefs: invalidProjectReferenceCount(input: input, projectIds: projectIds),
            storageIssues: input.storageIssues.count
        )
    }

    private static func invalidProjectReferenceCount(input: DataHealthScanInput, projectIds: Set<UUID>) -> Int {
        invalidOptionalProjectCount(input.materialItems.map(\.projectId), projectIds: projectIds)
            + invalidOptionalProjectCount(input.quoteItems.map(\.projectId), projectIds: projectIds)
            + invalidOptionalProjectCount(input.laborRecords.map(\.projectId), projectIds: projectIds)
            + invalidOptionalProjectCount(input.dailyLogs.map(\.projectId), projectIds: projectIds)
            + invalidOptionalProjectCount(input.siteTodos.map(\.projectId), projectIds: projectIds)
            + invalidOptionalProjectCount(input.quickNotes.map(\.projectId), projectIds: projectIds)
            + input.progressTasks.filter { !projectIds.contains($0.projectId) }.count
            + input.projectDrawings.filter { !projectIds.contains($0.projectId) }.count
            + input.projectContacts.filter { !projectIds.contains($0.projectId) }.count
            + input.projectFinancialRecords.filter { !projectIds.contains($0.projectId) }.count
            + input.projectDocuments.filter { !projectIds.contains($0.projectId) }.count
            + input.projectWarehouseMovements.filter { !projectIds.contains($0.projectId) }.count
    }

    private static func invalidOptionalProjectCount(_ ids: [UUID?], projectIds: Set<UUID>) -> Int {
        ids.compactMap { $0 }.filter { !projectIds.contains($0) }.count
    }
}
