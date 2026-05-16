import SwiftUI

private struct ProjectDeletionUndoSnapshot {
    let projectDocuments: [ProjectDocument]
    let projectFinancialRecords: [ProjectFinancialRecord]
    let projectWarehouseMovements: [ProjectWarehouseMovement]
}

extension ProjectDetailContainer {
    func saveMaterial(_ updated: MaterialItem) {
        if let index = financeStore.materialItems.firstIndex(where: { $0.id == updated.id }) {
            store.materialItems[index] = updated
            store.scheduleSave()
        }
    }

    func deleteMaterial(id: UUID) {
        store.removeMaterialItems(ids: Set([id]))
        store.scheduleSave()
    }

    func saveQuote(_ updated: QuoteItem) {
        if let index = financeStore.quoteItems.firstIndex(where: { $0.id == updated.id }) {
            store.quoteItems[index] = updated
            store.scheduleSave()
        }
    }

    func deleteQuote(id: UUID) {
        store.removeQuoteItems(ids: Set([id]))
        store.scheduleSave()
    }

    func saveLabor(_ updated: LaborRecord) {
        if let index = financeStore.laborRecords.firstIndex(where: { $0.id == updated.id }) {
            store.laborRecords[index] = updated
            store.scheduleSave()
        }
    }

    func deleteLabor(_ target: LaborRecord) {
        store.removeLaborRecords(ids: Set([target.id]))
        store.scheduleSave()
    }

    func saveProgress(_ updated: ProgressTask) {
        if let index = projectStore.progressTasks.firstIndex(where: { $0.id == updated.id }) {
            store.progressTasks[index] = updated
            store.scheduleSave()
        }
    }

    func deleteProgress(id: UUID) {
        store.removeProgressTasks(ids: Set([id]))
        store.scheduleSave()
    }

    func saveFinancialRecord(_ updated: ProjectFinancialRecord) {
        if let index = projectStore.projectFinancialRecords.firstIndex(where: { $0.id == updated.id }) {
            store.projectFinancialRecords[index] = updated
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
        var updatedDocuments = documentSnapshot
        var updatedFinancialRecords = financialSnapshot
        var updatedWarehouseMovements = warehouseSnapshot
        var removableFileNames: [String] = []

        let recordsToDelete = financialSnapshot.filter { ids.contains($0.id) }
        let linkedDocumentIds = Set(recordsToDelete.flatMap(\.linkedDocumentIds))
        let linkedByRecordFieldIds: Set<UUID> = Set(
            documentSnapshot.compactMap { document in
                guard let linkedId = document.linkedFinancialRecordId, ids.contains(linkedId) else { return nil }
                return document.id
            }
        )
        let targetDocumentIds = linkedDocumentIds.union(linkedByRecordFieldIds)

        if deleteLinkedDocuments {
            if !targetDocumentIds.isEmpty {
                removableFileNames = updatedDocuments
                    .filter { targetDocumentIds.contains($0.id) }
                    .map(\.fileName)
                updatedDocuments.removeAll { targetDocumentIds.contains($0.id) }
                for index in updatedFinancialRecords.indices {
                    updatedFinancialRecords[index].linkedDocumentIds.removeAll { targetDocumentIds.contains($0) }
                }
                for index in updatedWarehouseMovements.indices {
                    updatedWarehouseMovements[index].linkedDocumentIds.removeAll { targetDocumentIds.contains($0) }
                }
            }
        } else if !targetDocumentIds.isEmpty {
            for index in updatedDocuments.indices where targetDocumentIds.contains(updatedDocuments[index].id) {
                updatedDocuments[index].linkedFinancialRecordId = nil
            }
        }
        updatedFinancialRecords.removeAll { ids.contains($0.id) }

        store.projectDocuments = updatedDocuments
        store.projectFinancialRecords = updatedFinancialRecords
        store.projectWarehouseMovements = updatedWarehouseMovements

        let undoSnapshot = ProjectDeletionUndoSnapshot(
            projectDocuments: documentSnapshot,
            projectFinancialRecords: financialSnapshot,
            projectWarehouseMovements: warehouseSnapshot
        )
        let message = deleteLinkedDocuments
            ? String(format: String(localized: "已删除 %lld 条账目（含票据）"), Int64(ids.count))
            : String(format: String(localized: "已删除 %lld 条账目"), Int64(ids.count))
        queueUndoableProjectDeletion(
            message: message,
            snapshot: undoSnapshot,
            removableDocumentFileNames: removableFileNames
        )
    }

    func linkedDocuments(for record: ProjectFinancialRecord) -> [ProjectDocument] {
        ProjectDetailFinanceDocumentActions.linkedDocuments(for: record, documents: projectStore.projectDocuments)
    }

    func linkDocument(_ documentID: UUID, to recordID: UUID) {
        guard let docIndex = projectStore.projectDocuments.firstIndex(where: { $0.id == documentID }),
              let targetRecordIndex = projectStore.projectFinancialRecords.firstIndex(where: { $0.id == recordID }) else {
            return
        }

        let previousRecordID = projectStore.projectDocuments[docIndex].linkedFinancialRecordId
        if let previousRecordID,
           let previousRecordIndex = projectStore.projectFinancialRecords.firstIndex(where: { $0.id == previousRecordID }) {
            store.projectFinancialRecords[previousRecordIndex].linkedDocumentIds.removeAll { $0 == documentID }
        }

        store.projectDocuments[docIndex].linkedFinancialRecordId = recordID
        if !projectStore.projectFinancialRecords[targetRecordIndex].linkedDocumentIds.contains(documentID) {
            store.projectFinancialRecords[targetRecordIndex].linkedDocumentIds.append(documentID)
        }
        store.scheduleSave()
    }

    func deleteProjectDocumentWithUndo(_ document: ProjectDocument) {
        flushPendingProjectDeletionIfNeeded()

        let documentSnapshot = store.projectDocuments
        let financialSnapshot = store.projectFinancialRecords
        let warehouseSnapshot = store.projectWarehouseMovements
        let documentID = document.id

        var updatedDocuments = documentSnapshot
        var updatedFinancialRecords = financialSnapshot
        var updatedWarehouseMovements = warehouseSnapshot

        updatedDocuments.removeAll { $0.id == documentID }
        for index in updatedFinancialRecords.indices {
            updatedFinancialRecords[index].linkedDocumentIds.removeAll { $0 == documentID }
        }
        for index in updatedWarehouseMovements.indices {
            updatedWarehouseMovements[index].linkedDocumentIds.removeAll { $0 == documentID }
        }

        store.projectDocuments = updatedDocuments
        store.projectFinancialRecords = updatedFinancialRecords
        store.projectWarehouseMovements = updatedWarehouseMovements

        queueUndoableProjectDeletion(
            message: String(localized: "已删除票据资料"),
            snapshot: ProjectDeletionUndoSnapshot(
                projectDocuments: documentSnapshot,
                projectFinancialRecords: financialSnapshot,
                projectWarehouseMovements: warehouseSnapshot
            ),
            removableDocumentFileNames: [document.fileName]
        )
    }

    func flushPendingProjectDeletionIfNeeded() {
        pendingDeleteCommitTask?.cancel()
        pendingDeleteCommitTask = nil
        pendingDeleteCommit?()
        pendingDeleteCommit = nil
    }

    private func queueUndoableProjectDeletion(
        message: String,
        snapshot: ProjectDeletionUndoSnapshot,
        removableDocumentFileNames: [String]
    ) {
        pendingDeleteCommit = {
            for fileName in removableDocumentFileNames {
                ProjectDocumentStorage.delete(fileName: fileName)
            }
            store.scheduleSave()
        }
        pendingDeleteCommitTask = Task { @MainActor in
            guard await DebouncedTask.wait(for: .seconds(4)) else { return }
            pendingDeleteCommit?()
            pendingDeleteCommit = nil
            pendingDeleteCommitTask = nil
        }

        operationNotice = OperationToastNotice(
            message: message,
            actionTitle: String(localized: "撤销"),
            action: {
                pendingDeleteCommitTask?.cancel()
                pendingDeleteCommitTask = nil
                pendingDeleteCommit = nil
                store.projectDocuments = snapshot.projectDocuments
                store.projectFinancialRecords = snapshot.projectFinancialRecords
                store.projectWarehouseMovements = snapshot.projectWarehouseMovements
                store.scheduleSave()
                operationNotice = .info(String(localized: "已撤销删除"))
            },
            autoDismissDuration: .seconds(4)
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
                for index in projectStore.projectDocuments.indices where ids.contains(projectStore.projectDocuments[index].id) {
                    store.projectDocuments[index].category = category
                }
                store.scheduleSave()
            },
            onScan: {
                assetState.scanTarget = scanTarget(for: record)
            },
            onImportFiles: { urls in
                importProjectDocuments(urls, linkedFinancialRecordId: record.id)
            },
            onImportImage: { image, note in
                importCapturedImage(image, note: note, linkedFinancialRecordId: record.id)
            }
        )
    }
}
