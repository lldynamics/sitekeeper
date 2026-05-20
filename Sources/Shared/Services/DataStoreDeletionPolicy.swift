import Foundation

struct DataStoreDeletionAuditContext {
    let summary: String
    var detail: String = ""
    var source: String = ""

    func record(outcome: OperationAuditEntry.Outcome) {
        OperationAuditLog.record(
            action: .delete,
            outcome: outcome,
            summary: summary,
            detail: detail,
            source: source
        )
    }
}

struct DataStoreDeferredFileCleanup {
    let summary: String
    let fileCount: Int
    let perform: () -> Void
}

extension DataStoreDeferredFileCleanup {
    private static func normalizedFileNames(_ fileNames: [String]) -> [String] {
        Array(
            Set(
                fileNames
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }

    static func combined(
        summary: String,
        cleanups: [DataStoreDeferredFileCleanup?]
    ) -> DataStoreDeferredFileCleanup {
        let validCleanups = cleanups.compactMap { $0 }
        let totalFileCount = validCleanups.reduce(0) { $0 + $1.fileCount }
        return DataStoreDeferredFileCleanup(
            summary: summary,
            fileCount: totalFileCount,
            perform: {
                for cleanup in validCleanups {
                    cleanup.perform()
                }
            }
        )
    }

    static func photoFiles(
        _ fileNames: [String],
        summary: String
    ) -> DataStoreDeferredFileCleanup? {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return nil }

        return DataStoreDeferredFileCleanup(
            summary: summary,
            fileCount: normalizedFileNames.count,
            perform: {
                PhotoStorage.delete(fileNames: normalizedFileNames)
            }
        )
    }

    static func deletePhotoFilesOrThrow(
        _ fileNames: [String],
        summary _: String
    ) throws {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return }
        for fileName in normalizedFileNames {
            try PhotoStorage.deleteOrThrow(fileName: fileName)
            PhotoCache.shared.invalidate(fileName: fileName)
        }
    }

    static func drawingFiles(
        _ fileNames: [String],
        summary: String
    ) -> DataStoreDeferredFileCleanup? {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return nil }

        return DataStoreDeferredFileCleanup(
            summary: summary,
            fileCount: normalizedFileNames.count,
            perform: {
                DrawingStorage.delete(fileNames: normalizedFileNames)
            }
        )
    }

    static func deleteDrawingFilesOrThrow(
        _ fileNames: [String],
        summary _: String
    ) throws {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return }
        for fileName in normalizedFileNames {
            try DrawingStorage.deleteOrThrow(fileName: fileName)
        }
    }

    static func quickNoteAttachmentFiles(
        _ fileNames: [String],
        summary: String
    ) -> DataStoreDeferredFileCleanup? {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return nil }

        return DataStoreDeferredFileCleanup(
            summary: summary,
            fileCount: normalizedFileNames.count,
            perform: {
                QuickNoteAttachmentStorage.delete(fileNames: normalizedFileNames)
            }
        )
    }

    static func deleteQuickNoteAttachmentFilesOrThrow(
        _ fileNames: [String],
        summary _: String
    ) throws {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return }
        for fileName in normalizedFileNames {
            try QuickNoteAttachmentStorage.deleteOrThrow(fileName: fileName)
        }
    }

    static func quickNoteAttachments(
        _ attachments: [QuickNoteAttachment],
        summary: String
    ) -> DataStoreDeferredFileCleanup? {
        quickNoteAttachmentFiles(attachments.map(\.fileName), summary: summary)
    }

    static func projectDocumentFiles(
        _ fileNames: [String],
        summary: String
    ) -> DataStoreDeferredFileCleanup? {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return nil }

        return DataStoreDeferredFileCleanup(
            summary: summary,
            fileCount: normalizedFileNames.count,
            perform: {
                ProjectDocumentStorage.delete(fileNames: normalizedFileNames)
            }
        )
    }

    static func deleteProjectDocumentFilesOrThrow(
        _ fileNames: [String],
        summary _: String
    ) throws {
        let normalizedFileNames = normalizedFileNames(fileNames)
        guard !normalizedFileNames.isEmpty else { return }
        for fileName in normalizedFileNames {
            try ProjectDocumentStorage.deleteOrThrow(fileName: fileName)
        }
    }
}

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

struct DataStoreRemovalResult<Element> {
    let snapshot: [Element]
    let removed: [Element]
    var audit: DataStoreDeletionAuditContext?
    var deferredFileCleanup: DataStoreDeferredFileCleanup?

    var isEmpty: Bool { removed.isEmpty }
    var deletedCount: Int { removed.count }

    func removedIDs<ID: Hashable>(_ id: (Element) -> ID) -> Set<ID> {
        Set(removed.map(id))
    }

    func restoredItems<ID: Hashable>(
        current: [Element],
        id: (Element) -> ID
    ) -> [Element] {
        let snapshotIDs = Set(snapshot.map(id))
        let deletedIDs = removedIDs(id)
        var currentByID = Dictionary(uniqueKeysWithValues: current.map { (id($0), $0) })

        for item in snapshot where deletedIDs.contains(id(item)) {
            currentByID[id(item)] = item
        }

        let newItems = current.filter { !snapshotIDs.contains(id($0)) }
        let restoredSnapshotItems = snapshot.compactMap { currentByID[id($0)] }
        return newItems + restoredSnapshotItems
    }

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
