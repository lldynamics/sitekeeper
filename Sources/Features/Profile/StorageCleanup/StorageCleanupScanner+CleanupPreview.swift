import Foundation

@MainActor
extension StorageCleanupScanner {
    static func photoCleanupPreview(store: DataStore, projectId: UUID) -> CleanupImpactSummary {
        let projectLogs = store.dailyLogs.filter { $0.projectId == projectId }
        let projectTodos = store.siteTodos.filter { $0.projectId == projectId }
        let logsWithPhotos = projectLogs.filter { !$0.allPhotoFileNames.isEmpty }
        let todosWithPhotos = projectTodos.filter {
            $0.rectificationBeforePhotoFileName != nil || $0.rectificationAfterPhotoFileName != nil
        }

        var selectedPhotoNames = Set<String>()
        for log in projectLogs {
            selectedPhotoNames.formUnion(log.allPhotoFileNames)
        }
        for todo in projectTodos {
            if let before = todo.rectificationBeforePhotoFileName {
                selectedPhotoNames.insert(before)
            }
            if let after = todo.rectificationAfterPhotoFileName {
                selectedPhotoNames.insert(after)
            }
        }
        let remainingLogs = store.dailyLogs.filter { $0.projectId != projectId }
        let remainingTodos = store.siteTodos.filter { $0.projectId != projectId }
        let remainingPhotoNames = PhotoStorage.referencedFileNames(logs: remainingLogs, todos: remainingTodos)
        let deletablePhotoNames = selectedPhotoNames.filter { !remainingPhotoNames.contains($0) }

        var summary = CleanupImpactSummary()
        summary.addFile(title: AppLocalization.string("照片原文件"), count: deletablePhotoNames.count)
        summary.addRecord(title: AppLocalization.string("日志照片记录"), count: logsWithPhotos.count)
        summary.addRecord(title: AppLocalization.string("待办整改照片"), count: todosWithPhotos.count)
        summary.addSampleFileNames(deletablePhotoNames)
        return summary
    }

    static func videoCleanupPreview(
        store: DataStore,
        projectId: UUID,
        videoFileExtensions: Set<String>
    ) -> CleanupImpactSummary {
        let projectNotes = store.quickNotes.filter { $0.projectId == projectId }
        let notesWithVideos = projectNotes.filter { note in
            note.attachments.contains { $0.attachmentKind == .video }
        }

        var selectedAttachmentNames = Set<String>()
        for note in projectNotes {
            let names = note.attachments
                .filter { $0.attachmentKind == .video }
                .map(\.fileName)
            selectedAttachmentNames.formUnion(names)
        }

        let videoDocuments = store.projectDocuments
            .filter { $0.projectId == projectId }
            .filter { document in
                let ext = document.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return videoFileExtensions.contains(ext) && !isTicketCategory(document.category)
            }
        let videoDocumentIDs = Set(videoDocuments.map(\.id))
        let videoDocumentFileNames = Set(videoDocuments.map(\.fileName))

        let notesAfterCleanup = store.quickNotes.map { note -> QuickNote in
            guard note.projectId == projectId else { return note }
            var value = note
            value.attachments.removeAll { $0.attachmentKind == .video }
            return value
        }

        let extraMethodAttachments = store.constructionMethods.flatMap(\.attachments)
            + store.constructionMethods.flatMap(\.tutorialAttachments)
        let remainingAttachmentNames = QuickNoteAttachmentStorage.referencedFileNames(
            for: notesAfterCleanup,
            extraAttachments: extraMethodAttachments
        )
        let deletableAttachmentNames = selectedAttachmentNames.filter { !remainingAttachmentNames.contains($0) }

        let remainingDocumentNamesAfterCleanup = Set(
            store.projectDocuments
                .filter { !videoDocumentIDs.contains($0.id) }
                .map(\.fileName)
        )
        let deletableDocumentNames = videoDocumentFileNames.filter { !remainingDocumentNamesAfterCleanup.contains($0) }

        let financialLinkedCount = store.projectFinancialRecords.filter { record in
            record.linkedDocumentIds.contains(where: videoDocumentIDs.contains)
        }.count
        let warehouseLinkedCount = store.projectWarehouseMovements.filter { movement in
            movement.linkedDocumentIds.contains(where: videoDocumentIDs.contains)
        }.count

        var summary = CleanupImpactSummary()
        summary.addFile(title: AppLocalization.string("随手记视频文件"), count: deletableAttachmentNames.count)
        summary.addFile(title: AppLocalization.string("资料视频文件"), count: deletableDocumentNames.count)
        summary.addRecord(title: AppLocalization.string("随手记视频记录"), count: notesWithVideos.count)
        summary.addRecord(title: AppLocalization.string("视频资料记录"), count: videoDocumentIDs.count)
        summary.addRecord(title: AppLocalization.string("财务关联变更"), count: financialLinkedCount)
        summary.addRecord(title: AppLocalization.string("仓库关联变更"), count: warehouseLinkedCount)
        summary.addSampleFileNames(Set(deletableAttachmentNames).union(deletableDocumentNames))
        return summary
    }

    static func drawingCleanupPreview(
        store: DataStore,
        projectId: UUID,
        drawingFileExtensions: Set<String>
    ) -> CleanupImpactSummary {
        let drawings = store.projectDrawings
            .filter { $0.projectId == projectId }
            .filter { drawing in
                let ext = drawing.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return drawingFileExtensions.contains(ext)
            }
        let drawingFileNames = Set(drawings.map(\.fileName))
        let remainingDrawingNamesAfterCleanup = Set(
            store.projectDrawings
                .filter { drawing in
                    let ext = drawing.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let shouldRemove = drawing.projectId == projectId && drawingFileExtensions.contains(ext)
                    return !shouldRemove
                }
                .map(\.fileName)
        )
        let deletableDrawingNames = drawingFileNames.filter { !remainingDrawingNamesAfterCleanup.contains($0) }

        var summary = CleanupImpactSummary()
        summary.addFile(title: AppLocalization.string("图纸原件"), count: deletableDrawingNames.count)
        summary.addRecord(title: AppLocalization.string("图纸台账记录"), count: drawings.count)
        summary.addSampleFileNames(deletableDrawingNames)
        return summary
    }

    static func ticketCleanupPreview(store: DataStore, projectId: UUID) -> CleanupImpactSummary {
        let ticketDocuments = store.projectDocuments.filter { $0.projectId == projectId && isTicketCategory($0.category) }
        let removedDocumentIDs = Set(ticketDocuments.map(\.id))
        let documentFileNames = Set(ticketDocuments.map(\.fileName))
        let remainingDocumentNamesAfterCleanup = Set(
            store.projectDocuments
                .filter { !removedDocumentIDs.contains($0.id) }
                .map(\.fileName)
        )
        let deletableDocumentNames = documentFileNames.filter { !remainingDocumentNamesAfterCleanup.contains($0) }

        let financialLinkedCount = store.projectFinancialRecords.filter { record in
            record.linkedDocumentIds.contains(where: removedDocumentIDs.contains)
        }.count
        let warehouseLinkedCount = store.projectWarehouseMovements.filter { movement in
            movement.linkedDocumentIds.contains(where: removedDocumentIDs.contains)
        }.count

        var summary = CleanupImpactSummary()
        summary.addFile(title: AppLocalization.string("票据文件"), count: deletableDocumentNames.count)
        summary.addRecord(title: AppLocalization.string("票据资料记录"), count: removedDocumentIDs.count)
        summary.addRecord(title: AppLocalization.string("财务关联变更"), count: financialLinkedCount)
        summary.addRecord(title: AppLocalization.string("仓库关联变更"), count: warehouseLinkedCount)
        summary.addSampleFileNames(deletableDocumentNames)
        return summary
    }
}
