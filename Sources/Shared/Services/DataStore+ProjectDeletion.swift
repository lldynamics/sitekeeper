import Foundation

@MainActor
extension DataStore {
    private func projectDeletionSnapshot() -> DataStoreProjectDeletionSnapshot {
        DataStoreProjectDeletionSnapshot(
            projects: projects,
            materialItems: materialItems,
            quoteItems: quoteItems,
            laborRecords: laborRecords,
            dailyLogs: dailyLogs,
            progressTasks: progressTasks,
            siteTodos: siteTodos,
            projectDrawings: projectDrawings,
            projectContacts: projectContacts,
            projectFinancialRecords: projectFinancialRecords,
            projectDocuments: projectDocuments,
            quickNotes: quickNotes,
            projectWarehouseMovements: projectWarehouseMovements,
            materialSheetDrafts: materialSheetDrafts
        )
    }

    private func projectDeletionFileCleanup(
        logs: [DailyLog],
        todos: [SiteTodo],
        drawings: [ProjectDrawing],
        documents: [ProjectDocument],
        quickNotes: [QuickNote]
    ) -> DataStoreDeferredFileCleanup {
        DataStoreDeferredFileCleanup.combined(
            summary: String(localized: "删除项目关联文件"),
            cleanups: [
                DataStoreDeferredFileCleanup.photoFiles(
                    logs.flatMap(\.allPhotoFileNames)
                        + todos.compactMap(\.rectificationBeforePhotoFileName)
                        + todos.compactMap(\.rectificationAfterPhotoFileName),
                    summary: "project.photoFiles"
                ),
                DataStoreDeferredFileCleanup.drawingFiles(
                    drawings.map(\.fileName),
                    summary: "project.drawingFiles"
                ),
                DataStoreDeferredFileCleanup.projectDocumentFiles(
                    documents.map(\.fileName),
                    summary: "project.documentFiles"
                ),
                DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                    quickNotes.flatMap { note in
                        note.attachments.map(\.fileName)
                    },
                    summary: "project.quickNoteAttachmentFiles"
                )
            ]
        )
    }

    private func restoredSnapshotItems<Item: Identifiable>(
        snapshot: [Item],
        current: [Item],
        matching wasDeleted: (Item) -> Bool
    ) -> [Item] where Item.ID: Hashable {
        let currentIDs = Set(current.map(\.id))
        // Undo only this deletion; current records include edits made during the undo window.
        return current + snapshot.filter { wasDeleted($0) && !currentIDs.contains($0.id) }
    }

    func relatedDataCount(for projectId: UUID) -> Int {
        let summary = projectStore.projectActivitySummary(for: projectId)
        return financeStore.materialItems(for: projectId).count
            + financeStore.quoteItems(for: projectId).count
            + financeStore.laborRecords(for: projectId).count
            + summary.dailyLogCount
            + summary.progressTaskCount
            + summary.todoCount
            + projectStore.projectDrawings(for: projectId).count
            + projectStore.projectContacts(for: projectId).count
            + projectStore.projectFinancialRecords(for: projectId).count
            + summary.documentCount
            + projectStore.quickNotes(for: projectId).count
            + projectStore.projectWarehouseMovements(for: projectId).count
            + materialLibraryStore.materialSheetDraftCount(for: projectId)
    }

    @discardableResult
    func removeProjectCascade(
        _ projectId: UUID,
        audit: DataStoreDeletionAuditContext? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreProjectDeletionResult {
        let snapshot = projectDeletionSnapshot()
        let removedProject = snapshot.projects.first { $0.id == projectId }
        let projectLogs = snapshot.dailyLogs.filter { $0.projectId == projectId }
        let projectTodos = snapshot.siteTodos.filter { $0.projectId == projectId }
        let projectDrawingItems = snapshot.projectDrawings.filter { $0.projectId == projectId }
        let projectDocumentItems = snapshot.projectDocuments.filter { $0.projectId == projectId }
        let projectQuickNotes = snapshot.quickNotes.filter { $0.projectId == projectId }
        let fileCleanup = projectDeletionFileCleanup(
            logs: projectLogs,
            todos: projectTodos,
            drawings: projectDrawingItems,
            documents: projectDocumentItems,
            quickNotes: projectQuickNotes
        )

        guard removedProject != nil else {
            return DataStoreProjectDeletionResult(
                projectId: projectId,
                snapshot: snapshot,
                removedProject: nil,
                deletedRecordCount: 0,
                audit: audit,
                deferredFileCleanup: fileCleanup
            )
        }

        let deletedRecordCount = 1
            + snapshot.materialItems.filter { $0.projectId == projectId }.count
            + snapshot.quoteItems.filter { $0.projectId == projectId }.count
            + snapshot.laborRecords.filter { $0.projectId == projectId }.count
            + projectLogs.count
            + snapshot.progressTasks.filter { $0.projectId == projectId }.count
            + projectTodos.count
            + projectDrawingItems.count
            + snapshot.projectContacts.filter { $0.projectId == projectId }.count
            + snapshot.projectFinancialRecords.filter { $0.projectId == projectId }.count
            + projectDocumentItems.count
            + projectQuickNotes.count
            + snapshot.projectWarehouseMovements.filter { $0.projectId == projectId }.count
            + snapshot.materialSheetDrafts.filter { $0.projectId == projectId }.count

        replaceMaterialItems(snapshot.materialItems.filter { $0.projectId != projectId })
        replaceQuoteItems(snapshot.quoteItems.filter { $0.projectId != projectId })
        replaceLaborRecords(snapshot.laborRecords.filter { $0.projectId != projectId })
        replaceDailyLogs(snapshot.dailyLogs.filter { $0.projectId != projectId })
        replaceProgressTasks(snapshot.progressTasks.filter { $0.projectId != projectId })
        replaceSiteTodos(snapshot.siteTodos.filter { $0.projectId != projectId })
        replaceProjectDrawings(snapshot.projectDrawings.filter { $0.projectId != projectId })
        replaceProjectContacts(snapshot.projectContacts.compactMap { contact in
            if contact.projectId == projectId {
                return nil
            }
            var cleaned = contact
            cleaned.relatedProjectIds.removeAll { $0 == projectId }
            return cleaned
        })
        replaceProjectFinancialRecords(snapshot.projectFinancialRecords.filter { $0.projectId != projectId })
        replaceProjectDocuments(snapshot.projectDocuments.filter { $0.projectId != projectId })
        replaceQuickNotes(snapshot.quickNotes.filter { $0.projectId != projectId })
        replaceProjectWarehouseMovements(snapshot.projectWarehouseMovements.filter { $0.projectId != projectId })
        replaceMaterialSheetDrafts(snapshot.materialSheetDrafts.filter { $0.projectId != projectId })
        replaceProjects(snapshot.projects.filter { $0.id != projectId })

        let result = DataStoreProjectDeletionResult(
            projectId: projectId,
            snapshot: snapshot,
            removedProject: removedProject,
            deletedRecordCount: deletedRecordCount,
            audit: audit,
            deferredFileCleanup: fileCleanup
        )
        if recordsAuditImmediately {
            result.recordAuditStarted()
            result.performDeferredFileCleanup()
            result.recordAuditSucceeded()
        }
        return result
    }

    func restoreProjectCascade(_ deletion: DataStoreProjectDeletionResult) {
        guard !deletion.isEmpty else { return }
        let snapshot = deletion.snapshot
        let projectID = deletion.projectId
        replaceProjects(restoredSnapshotItems(snapshot: snapshot.projects, current: projects) { $0.id == projectID })
        replaceMaterialItems(restoredSnapshotItems(snapshot: snapshot.materialItems, current: materialItems) { $0.projectId == projectID })
        replaceQuoteItems(restoredSnapshotItems(snapshot: snapshot.quoteItems, current: quoteItems) { $0.projectId == projectID })
        replaceLaborRecords(restoredSnapshotItems(snapshot: snapshot.laborRecords, current: laborRecords) { $0.projectId == projectID })
        replaceDailyLogs(restoredSnapshotItems(snapshot: snapshot.dailyLogs, current: dailyLogs) { $0.projectId == projectID })
        replaceProgressTasks(restoredSnapshotItems(snapshot: snapshot.progressTasks, current: progressTasks) { $0.projectId == projectID })
        replaceSiteTodos(restoredSnapshotItems(snapshot: snapshot.siteTodos, current: siteTodos) { $0.projectId == projectID })
        replaceProjectDrawings(restoredSnapshotItems(snapshot: snapshot.projectDrawings, current: projectDrawings) { $0.projectId == projectID })
        restoreProjectDeletionContacts(snapshot.projectContacts, projectID: projectID)
        replaceProjectFinancialRecords(
            restoredSnapshotItems(snapshot: snapshot.projectFinancialRecords, current: projectFinancialRecords) { $0.projectId == projectID }
        )
        replaceProjectDocuments(restoredSnapshotItems(snapshot: snapshot.projectDocuments, current: projectDocuments) { $0.projectId == projectID })
        replaceQuickNotes(restoredSnapshotItems(snapshot: snapshot.quickNotes, current: quickNotes) { $0.projectId == projectID })
        replaceProjectWarehouseMovements(
            restoredSnapshotItems(snapshot: snapshot.projectWarehouseMovements, current: projectWarehouseMovements) { $0.projectId == projectID }
        )
        replaceMaterialSheetDrafts(
            restoredSnapshotItems(snapshot: snapshot.materialSheetDrafts, current: materialSheetDrafts) { $0.projectId == projectID }
        )
    }

    private func restoreProjectDeletionContacts(_ snapshot: [ProjectContact], projectID: UUID) {
        let unlinkedContactIDs = Set(snapshot.filter {
            $0.projectId != projectID && $0.relatedProjectIds.contains(projectID)
        }.map(\.id))
        let restored = restoredSnapshotItems(snapshot: snapshot, current: projectContacts) { $0.projectId == projectID }
        replaceProjectContacts(restored.map { contact in
            guard unlinkedContactIDs.contains(contact.id), !contact.isLinked(to: projectID) else { return contact }
            var updated = contact
            updated.relatedProjectIds.append(projectID)
            return updated
        })
    }

    func deleteProject(_ projectId: UUID) {
        let deletion = removeProjectCascade(projectId)
        deletion.performDeferredFileCleanup()
        scheduleSave()
    }
}
