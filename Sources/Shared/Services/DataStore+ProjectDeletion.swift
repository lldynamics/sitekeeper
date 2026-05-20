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
        current: [Item]
    ) -> [Item] where Item.ID: Hashable {
        let snapshotIDs = Set(snapshot.map(\.id))
        let newItems = current.filter { !snapshotIDs.contains($0.id) }
        return newItems + snapshot
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
        replaceProjects(restoredSnapshotItems(snapshot: deletion.snapshot.projects, current: projects))
        replaceMaterialItems(restoredSnapshotItems(snapshot: deletion.snapshot.materialItems, current: materialItems))
        replaceQuoteItems(restoredSnapshotItems(snapshot: deletion.snapshot.quoteItems, current: quoteItems))
        replaceLaborRecords(restoredSnapshotItems(snapshot: deletion.snapshot.laborRecords, current: laborRecords))
        replaceDailyLogs(restoredSnapshotItems(snapshot: deletion.snapshot.dailyLogs, current: dailyLogs))
        replaceProgressTasks(restoredSnapshotItems(snapshot: deletion.snapshot.progressTasks, current: progressTasks))
        replaceSiteTodos(restoredSnapshotItems(snapshot: deletion.snapshot.siteTodos, current: siteTodos))
        replaceProjectDrawings(restoredSnapshotItems(snapshot: deletion.snapshot.projectDrawings, current: projectDrawings))
        replaceProjectContacts(restoredSnapshotItems(snapshot: deletion.snapshot.projectContacts, current: projectContacts))
        replaceProjectFinancialRecords(
            restoredSnapshotItems(snapshot: deletion.snapshot.projectFinancialRecords, current: projectFinancialRecords)
        )
        replaceProjectDocuments(restoredSnapshotItems(snapshot: deletion.snapshot.projectDocuments, current: projectDocuments))
        replaceQuickNotes(restoredSnapshotItems(snapshot: deletion.snapshot.quickNotes, current: quickNotes))
        replaceProjectWarehouseMovements(
            restoredSnapshotItems(snapshot: deletion.snapshot.projectWarehouseMovements, current: projectWarehouseMovements)
        )
        replaceMaterialSheetDrafts(
            restoredSnapshotItems(snapshot: deletion.snapshot.materialSheetDrafts, current: materialSheetDrafts)
        )
    }

    func deleteProject(_ projectId: UUID) {
        let deletion = removeProjectCascade(projectId)
        deletion.performDeferredFileCleanup()
        scheduleSave()
    }
}
