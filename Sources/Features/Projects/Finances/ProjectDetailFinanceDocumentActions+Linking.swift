import Foundation

extension ProjectDetailFinanceDocumentActions {
    @MainActor
    static func attachDocument(_ document: ProjectDocument, to record: ProjectFinancialRecord, store: DataStore) {
        guard store.projectDocuments.contains(where: { $0.id == document.id }),
              store.projectFinancialRecords.contains(where: { $0.id == record.id }) else { return }
        relinkDocument(documentId: document.id, to: record.id, store: store)
        store.scheduleSave()
    }

    @MainActor
    static func detachDocument(_ document: ProjectDocument, from record: ProjectFinancialRecord, store: DataStore) {
        guard store.projectDocuments.contains(where: { $0.id == document.id }),
              store.projectFinancialRecords.contains(where: { $0.id == record.id }) else { return }
        if document.linkedFinancialRecordId == record.id {
            relinkDocument(documentId: document.id, to: nil, store: store)
        } else {
            _ = store.mutateProjectFinancialRecord(id: record.id) { value in
                value.linkedDocumentIds.removeAll { $0 == document.id }
            }
        }
        store.scheduleSave()
    }

    @MainActor
    static func saveDocumentEdit(_ updated: ProjectDocument, store: DataStore) {
        guard let index = store.projectDocuments.firstIndex(where: { $0.id == updated.id }) else { return }
        let previous = store.projectDocuments[index]
        var normalized = updated
        normalized.versionNumber = max(1, normalized.versionNumber)
        if normalized.replacesDocumentId == normalized.id {
            normalized.replacesDocumentId = nil
        }
        if normalized.replacedByDocumentId == normalized.id {
            normalized.replacedByDocumentId = nil
        }
        if let previousVersionId = normalized.replacesDocumentId,
           let previousVersion = store.projectDocuments.first(where: { $0.id == previousVersionId }) {
            if previousVersion.replacesDocumentId == normalized.id {
                normalized.replacesDocumentId = nil
            } else if normalized.versionNumber <= previousVersion.normalizedVersionNumber {
                normalized.versionNumber = min(999, previousVersion.normalizedVersionNumber + 1)
            }
        }
        store.updateProjectDocument(normalized)
        reconcileDocumentVersionLinks(
            document: normalized,
            previousReplacesDocumentId: previous.replacesDocumentId,
            store: store
        )
        relinkDocument(documentId: normalized.id, to: normalized.linkedFinancialRecordId, store: store)
        store.scheduleSave()
    }

    @MainActor
    @discardableResult
    static func appendProjectDocument(
        fileName: String,
        pageCount: Int,
        target: ProjectScanTarget,
        projectId: UUID,
        createdAt: String = Formatters.now(),
        store: DataStore,
        fileType: String = "pdf"
    ) -> ProjectDocument {
        let document = ProjectDocument(
            projectId: projectId,
            title: target.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? target.category.displayName : target.title,
            category: target.category,
            fileName: fileName,
            fileType: fileType,
            pageCount: pageCount,
            amount: target.amount,
            linkedFinancialRecordId: target.linkedFinancialRecordId,
            linkedConstructionMethodIDs: target.linkedConstructionMethodIDs,
            submissionStatus: target.submissionStatus,
            responsiblePerson: target.responsiblePerson,
            formedAt: target.formedAt,
            archiveNumber: target.archiveNumber,
            workSection: target.workSection,
            createdAt: BusinessDateValue(legacyText: createdAt),
            note: target.note
        )
        store.appendProjectDocument(document)
        if let recordId = target.linkedFinancialRecordId {
            _ = store.mutateProjectFinancialRecord(id: recordId) { record in
                if !record.linkedDocumentIds.contains(document.id) {
                    record.linkedDocumentIds.append(document.id)
                }
            }
        }
        store.scheduleSave()
        return document
    }

    @MainActor
    static func relinkDocument(documentId: UUID, to recordId: UUID?, store: DataStore) {
        var financialRecords = store.projectFinancialRecords
        for index in financialRecords.indices {
            financialRecords[index].linkedDocumentIds.removeAll { $0 == documentId }
        }
        let validRecordId: UUID?
        if let recordId,
           let recordIndex = financialRecords.firstIndex(where: { $0.id == recordId }) {
            if !financialRecords[recordIndex].linkedDocumentIds.contains(documentId) {
                financialRecords[recordIndex].linkedDocumentIds.append(documentId)
            }
            validRecordId = recordId
        } else {
            validRecordId = nil
        }
        store.replaceProjectFinancialRecords(financialRecords)
        _ = store.mutateProjectDocument(id: documentId) { document in
            document.linkedFinancialRecordId = validRecordId
        }
    }

    @MainActor
    static func reconcileDocumentVersionLinks(
        document: ProjectDocument,
        previousReplacesDocumentId: UUID?,
        store: DataStore
    ) {
        if let previousReplacesDocumentId,
           previousReplacesDocumentId != document.replacesDocumentId {
            _ = store.mutateProjectDocument(id: previousReplacesDocumentId) { previousVersion in
                guard previousVersion.replacedByDocumentId == document.id else { return }
                previousVersion.replacedByDocumentId = nil
                if previousVersion.versionState == .superseded {
                    previousVersion.versionState = .current
                }
            }
        }

        guard let previousVersionId = document.replacesDocumentId else { return }
        _ = store.mutateProjectDocument(id: previousVersionId) { previousVersion in
            previousVersion.replacedByDocumentId = document.id
            if previousVersion.versionState == .current {
                previousVersion.versionState = .superseded
            }
        }
    }
}
