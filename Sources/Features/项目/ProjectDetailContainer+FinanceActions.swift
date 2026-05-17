import SwiftUI

private struct ProjectDeletionUndoSnapshot {
    let projectDocuments: [ProjectDocument]
    let projectFinancialRecords: [ProjectFinancialRecord]
    let projectWarehouseMovements: [ProjectWarehouseMovement]
}

extension ProjectDetailContainer {
    func saveMaterial(_ updated: MaterialItem) {
        if store.updateMaterialItem(updated) {
            store.scheduleSave()
        }
    }

    func deleteMaterial(id: UUID) {
        flushPendingProjectDeletionIfNeeded()
        let snapshot = store.materialItems
        guard let target = snapshot.first(where: { $0.id == id }) else { return }

        store.removeMaterialItems(ids: Set([id]))
        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(localized: "已删除材料"),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.replaceMaterialItems(UndoableDeletionCoordinator.restoringItems(
                    snapshot: snapshot,
                    current: store.materialItems,
                    deletedIDs: Set([id])
                ))
                store.scheduleSave()
            },
            audit: UndoableDeletionAuditContext(
                summary: String(localized: "删除项目材料 1 条"),
                detail: projectDetailAuditDetail([target.name]),
                source: "ProjectDetailView"
            )
        )
    }

    func saveQuote(_ updated: QuoteItem) {
        if store.updateQuoteItem(updated) {
            store.scheduleSave()
        }
    }

    func deleteQuote(id: UUID) {
        flushPendingProjectDeletionIfNeeded()
        let snapshot = store.quoteItems
        guard let target = snapshot.first(where: { $0.id == id }) else { return }

        store.removeQuoteItems(ids: Set([id]))
        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(localized: "已删除报价"),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.replaceQuoteItems(UndoableDeletionCoordinator.restoringItems(
                    snapshot: snapshot,
                    current: store.quoteItems,
                    deletedIDs: Set([id])
                ))
                store.scheduleSave()
            },
            audit: UndoableDeletionAuditContext(
                summary: String(localized: "删除项目报价 1 条"),
                detail: projectDetailAuditDetail([target.name, target.versionName]),
                source: "ProjectDetailView"
            )
        )
    }

    func saveLabor(_ updated: LaborRecord) {
        if store.updateLaborRecord(updated) {
            store.scheduleSave()
        }
    }

    func deleteLabor(_ target: LaborRecord) {
        flushPendingProjectDeletionIfNeeded()
        let snapshot = store.laborRecords
        guard snapshot.contains(where: { $0.id == target.id }) else { return }

        store.removeLaborRecords(ids: Set([target.id]))
        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(localized: "已删除人工记录"),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.replaceLaborRecords(UndoableDeletionCoordinator.restoringItems(
                    snapshot: snapshot,
                    current: store.laborRecords,
                    deletedIDs: Set([target.id])
                ))
                store.scheduleSave()
            },
            audit: UndoableDeletionAuditContext(
                summary: String(localized: "删除项目人工记录 1 条"),
                detail: projectDetailAuditDetail([target.date, target.teamName, target.workType]),
                source: "ProjectDetailView"
            )
        )
    }

    func saveProgress(_ updated: ProgressTask) {
        if projectStore.progressTasks.contains(where: { $0.id == updated.id }) {
            store.updateProgressTask(updated)
            store.scheduleSave()
        }
    }

    func deleteProgress(id: UUID) {
        flushPendingProjectDeletionIfNeeded()
        let snapshot = store.progressTasks
        guard let target = snapshot.first(where: { $0.id == id }) else { return }

        store.removeProgressTasks(ids: Set([id]))
        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(localized: "已删除进度任务"),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.replaceProgressTasks(UndoableDeletionCoordinator.restoringItems(
                    snapshot: snapshot,
                    current: store.progressTasks,
                    deletedIDs: Set([id])
                ))
                store.scheduleSave()
            },
            audit: UndoableDeletionAuditContext(
                summary: String(localized: "删除项目进度任务 1 条"),
                detail: projectDetailAuditDetail([target.title, target.dueDate]),
                source: "ProjectDetailView"
            )
        )
    }

    func saveFinancialRecord(_ updated: ProjectFinancialRecord) {
        if projectStore.projectFinancialRecords.contains(where: { $0.id == updated.id }) {
            store.updateProjectFinancialRecord(updated)
            store.scheduleSave()
        }
    }

    func requestDeleteFinancialRecord(_ record: ProjectFinancialRecord) {
        requestDeleteFinancialRecords(ids: Set([record.id]))
    }

    func deleteFinancialRecords(ids: Set<UUID>) {
        requestDeleteFinancialRecords(ids: ids)
    }

    func requestDeleteFinancialRecords(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        financeState.pendingDeleteFinancialRecordIDs = ids
        financeState.showFinancialDeleteConfirm = true
    }

    func performDeleteFinancialRecords(deleteLinkedDocuments: Bool) {
        let ids = financeState.pendingDeleteFinancialRecordIDs
        financeState.pendingDeleteFinancialRecordIDs.removeAll()
        guard !ids.isEmpty else { return }

        flushPendingProjectDeletionIfNeeded()

        let documentSnapshot = store.projectDocuments
        let financialSnapshot = store.projectFinancialRecords
        let warehouseSnapshot = store.projectWarehouseMovements
        guard let deletion = ProjectDetailFinanceDocumentActions.executeFinancialRecordDeletion(
            ids: ids,
            deleteLinkedDocuments: deleteLinkedDocuments,
            store: store,
            documentCleanupMode: .deferred
        ) else { return }

        let undoSnapshot = ProjectDeletionUndoSnapshot(
            projectDocuments: documentSnapshot,
            projectFinancialRecords: financialSnapshot,
            projectWarehouseMovements: warehouseSnapshot
        )
        let message = deleteLinkedDocuments
            ? String(format: String(localized: "已删除 %lld 条账目（含票据）"), Int64(deletion.financialDeletion.deletedCount))
            : String(format: String(localized: "已删除 %lld 条账目"), Int64(deletion.financialDeletion.deletedCount))
        queueUndoableProjectDeletion(
            message: message,
            snapshot: undoSnapshot,
            removableDocumentFileNames: deletion.removableDocumentFileNames
        )
    }

    func linkedDocuments(for record: ProjectFinancialRecord) -> [ProjectDocument] {
        ProjectDetailFinanceDocumentActions.linkedDocuments(for: record, documents: projectStore.projectDocuments)
    }

    func linkDocument(_ documentID: UUID, to recordID: UUID) {
        guard let document = projectStore.projectDocuments.first(where: { $0.id == documentID }),
              projectStore.projectFinancialRecords.contains(where: { $0.id == recordID }) else {
            return
        }

        let previousRecordID = document.linkedFinancialRecordId
        if let previousRecordID,
           previousRecordID != recordID {
            _ = store.mutateProjectFinancialRecord(id: previousRecordID) { record in
                record.linkedDocumentIds.removeAll { $0 == documentID }
            }
        }

        _ = store.mutateProjectDocument(id: documentID) { value in
            value.linkedFinancialRecordId = recordID
        }
        _ = store.mutateProjectFinancialRecord(id: recordID) { record in
            if !record.linkedDocumentIds.contains(documentID) {
                record.linkedDocumentIds.append(documentID)
            }
        }
        store.scheduleSave()
    }

    func deleteProjectDocumentWithUndo(_ document: ProjectDocument) {
        flushPendingProjectDeletionIfNeeded()

        let documentSnapshot = store.projectDocuments
        let financialSnapshot = store.projectFinancialRecords
        let warehouseSnapshot = store.projectWarehouseMovements
        guard let deletion = ProjectDetailFinanceDocumentActions.executeDocumentDeletion(
            ids: Set([document.id]),
            store: store,
            documentCleanupMode: .deferred
        ) else { return }

        queueUndoableProjectDeletion(
            message: String(localized: "已删除票据资料"),
            snapshot: ProjectDeletionUndoSnapshot(
                projectDocuments: documentSnapshot,
                projectFinancialRecords: financialSnapshot,
                projectWarehouseMovements: warehouseSnapshot
            ),
            removableDocumentFileNames: deletion.removableDocumentFileNames
        )
    }

    func flushPendingProjectDeletionIfNeeded() {
        undoableDeletion.flushPendingCommit()
    }

    func projectDetailAuditDetail(_ parts: [String]) -> String {
        ([projectDetailAuditProjectName] + parts)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var projectDetailAuditProjectName: String {
        let projectName = projectStore.projects.first(where: { $0.id == projectId })?.name
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return projectName.isEmpty ? String(localized: "未命名项目") : projectName
    }

    private func queueUndoableProjectDeletion(
        message: String,
        snapshot: ProjectDeletionUndoSnapshot,
        removableDocumentFileNames: [String]
    ) {
        let deferredCleanup = DataStoreDeferredFileCleanup.projectDocumentFiles(
            removableDocumentFileNames,
            summary: "projectDetail.undoDocumentFiles"
        )
        undoableDeletion.queue(
            notice: $operationNotice,
            message: message,
            commit: {
                deferredCleanup?.perform()
                store.scheduleSave()
            },
            undo: {
                store.replaceProjectDocuments(snapshot.projectDocuments)
                store.replaceProjectFinancialRecords(snapshot.projectFinancialRecords)
                store.replaceProjectWarehouseMovements(snapshot.projectWarehouseMovements)
                store.scheduleSave()
            },
            audit: UndoableDeletionAuditContext(
                summary: message,
                detail: String(format: String(localized: "关联票据文件 %lld 个"), Int64(removableDocumentFileNames.count)),
                source: "ProjectDetailView"
            )
        )
    }

    @ViewBuilder
    func attachmentSheet(record: ProjectFinancialRecord, documents: [ProjectDocument]) -> some View {
        ProjectFinancialAttachmentSheet(
            record: record,
            documents: documents,
            onDetach: { document in
                ProjectDetailFinanceDocumentActions.detachDocument(document, from: record, store: store)
            },
            onAttach: { document in
                ProjectDetailFinanceDocumentActions.attachDocument(document, to: record, store: store)
            },
            onBulkSetCategory: { documents, category in
                let ids = Set(documents.map(\.id))
                var projectDocuments = store.projectDocuments
                for index in projectDocuments.indices where ids.contains(projectDocuments[index].id) {
                    projectDocuments[index].category = category
                }
                store.replaceProjectDocuments(projectDocuments)
                store.scheduleSave()
            },
            onScan: {
                assetState.scanTarget = scanTarget(for: record)
            },
            onImportFiles: { urls, settings in
                importProjectDocuments(urls, linkedFinancialRecordId: record.id, ledgerSettings: settings)
            },
            onImportImage: { image, note in
                importCapturedImage(image, note: note, linkedFinancialRecordId: record.id)
            }
        )
    }
}
