import SwiftUI

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
        ProjectDetailFinanceDocumentActions.deleteFinancialRecords(
            ids: ids,
            deleteLinkedDocuments: deleteLinkedDocuments,
            store: store
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
