import Foundation

struct DataStoreProjectFileCleanupResult: Equatable {
    var photoFileNames: Set<String> = []
    var quickNoteAttachmentFileNames: Set<String> = []
    var projectDocumentFileNames: Set<String> = []
    var drawingFileNames: Set<String> = []

    var totalFileCount: Int {
        photoFileNames.count
            + quickNoteAttachmentFileNames.count
            + projectDocumentFileNames.count
            + drawingFileNames.count
    }
}

@MainActor
extension DataStore {
    @discardableResult
    func clearProjectPhotoReferences(projectId: UUID) -> DataStoreProjectFileCleanupResult {
        var logs = dailyLogs
        var todos = siteTodos
        var selectedPhotoNames = Set<String>()

        for index in logs.indices where logs[index].projectId == projectId {
            selectedPhotoNames.formUnion(logs[index].allPhotoFileNames)
            logs[index].photoFileName = nil
            logs[index].photos = []
        }
        for index in todos.indices where todos[index].projectId == projectId {
            if let before = todos[index].rectificationBeforePhotoFileName {
                selectedPhotoNames.insert(before)
            }
            if let after = todos[index].rectificationAfterPhotoFileName {
                selectedPhotoNames.insert(after)
            }
            todos[index].rectificationBeforePhotoFileName = nil
            todos[index].rectificationAfterPhotoFileName = nil
        }

        replaceDailyLogs(logs)
        replaceSiteTodos(todos)

        let remainingPhotoNames = PhotoStorage.referencedFileNames(logs: dailyLogs, todos: siteTodos)
        return DataStoreProjectFileCleanupResult(
            photoFileNames: selectedPhotoNames.filter { !remainingPhotoNames.contains($0) }
        )
    }

    @discardableResult
    func clearProjectVideoReferences(
        projectId: UUID,
        videoFileExtensions: Set<String>
    ) -> DataStoreProjectFileCleanupResult {
        var notes = quickNotes
        var selectedAttachmentNames = Set<String>()

        for index in notes.indices where notes[index].projectId == projectId {
            let videos = notes[index].attachments.filter { $0.attachmentKind == .video }
            selectedAttachmentNames.formUnion(videos.map(\.fileName))
            notes[index].attachments.removeAll { $0.attachmentKind == .video }
        }
        replaceQuickNotes(notes)

        let videoDocumentIDs = Set(
            projectDocuments
                .filter { $0.projectId == projectId }
                .filter { document in
                    let ext = document.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return videoFileExtensions.contains(ext) && !Self.isStorageCleanupTicketCategory(document.category)
                }
                .map(\.id)
        )
        let videoDocumentFileNames = Set(
            projectDocuments
                .filter { videoDocumentIDs.contains($0.id) }
                .map(\.fileName)
        )
        removeProjectDocuments(ids: videoDocumentIDs)
        unlinkProjectDocumentReferences(ids: videoDocumentIDs)

        let extraMethodAttachments = constructionMethods.flatMap(\.attachments)
            + constructionMethods.flatMap(\.tutorialAttachments)
        let remainingAttachmentNames = QuickNoteAttachmentStorage.referencedFileNames(
            for: quickNotes,
            extraAttachments: extraMethodAttachments
        )
        let remainingDocumentNames = Set(projectDocuments.map(\.fileName))

        return DataStoreProjectFileCleanupResult(
            quickNoteAttachmentFileNames: selectedAttachmentNames.filter { !remainingAttachmentNames.contains($0) },
            projectDocumentFileNames: videoDocumentFileNames.filter { !remainingDocumentNames.contains($0) }
        )
    }

    @discardableResult
    func clearProjectCADReferences(
        projectId: UUID,
        cadFileExtensions: Set<String>
    ) -> DataStoreProjectFileCleanupResult {
        let drawingIDs = Set(
            projectDrawings
                .filter { drawing in
                    let ext = drawing.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return drawing.projectId == projectId && cadFileExtensions.contains(ext)
                }
                .map(\.id)
        )
        let drawingFileNames = Set(
            projectDrawings
                .filter { drawingIDs.contains($0.id) }
                .map(\.fileName)
        )

        removeProjectDrawings(ids: drawingIDs)

        let remainingDrawingNames = Set(projectDrawings.map(\.fileName))
        return DataStoreProjectFileCleanupResult(
            drawingFileNames: drawingFileNames.filter { !remainingDrawingNames.contains($0) }
        )
    }

    @discardableResult
    func clearProjectTicketDocumentReferences(projectId: UUID) -> DataStoreProjectFileCleanupResult {
        let documentIDs = Set(
            projectDocuments
                .filter { $0.projectId == projectId && Self.isStorageCleanupTicketCategory($0.category) }
                .map(\.id)
        )
        let documentFileNames = Set(
            projectDocuments
                .filter { documentIDs.contains($0.id) }
                .map(\.fileName)
        )

        removeProjectDocuments(ids: documentIDs)
        unlinkProjectDocumentReferences(ids: documentIDs)

        let remainingDocumentNames = Set(projectDocuments.map(\.fileName))
        return DataStoreProjectFileCleanupResult(
            projectDocumentFileNames: documentFileNames.filter { !remainingDocumentNames.contains($0) }
        )
    }

    func unlinkProjectDocumentReferences(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        var records = projectFinancialRecords
        for index in records.indices {
            records[index].linkedDocumentIds.removeAll { ids.contains($0) }
        }
        replaceProjectFinancialRecords(records)

        var movements = projectWarehouseMovements
        for index in movements.indices {
            movements[index].linkedDocumentIds.removeAll { ids.contains($0) }
        }
        replaceProjectWarehouseMovements(movements)
    }

    private static func isStorageCleanupTicketCategory(_ category: ProjectDocumentCategory) -> Bool {
        switch category {
        case .invoice, .receipt, .paymentRequest:
            return true
        default:
            return false
        }
    }
}
