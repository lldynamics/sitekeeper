import Foundation

extension DataHealthView {
    func applyDataHealthIssueRepair(_ repair: DataHealthIssueRepair) -> Bool {
        if let repaired = applyAttachmentIssueRepair(repair) {
            return repaired
        }
        return applyProjectLinkIssueRepair(repair)
    }

    private func applyAttachmentIssueRepair(_ repair: DataHealthIssueRepair) -> Bool? {
        switch repair {
        case .clearDailyLogLegacyPhoto(let logId, let fileName):
            return clearDailyLogLegacyPhoto(logId, fileName)

        case .removeDailyLogPhoto(let logId, let photoId):
            return removeDailyLogPhoto(logId, photoId)

        case .clearSiteTodoBeforePhoto(let todoId, let fileName):
            return clearSiteTodoBeforePhoto(todoId, fileName)

        case .clearSiteTodoAfterPhoto(let todoId, let fileName):
            return clearSiteTodoAfterPhoto(todoId, fileName)

        case .removeProjectDocument(let documentId):
            return removeProjectDocument(documentId)

        case .removeQuickNoteAttachment(let noteId, let attachmentId):
            return removeQuickNoteAttachment(noteId, attachmentId)

        case .unlinkFinancialDocument(let recordId, let documentId):
            return unlinkFinancialDocument(recordId, documentId)

        case .unlinkWarehouseDocument(let movementId, let documentId):
            return unlinkWarehouseDocument(movementId, documentId)

        case .clearDocumentLinkedFinancialRecord(let documentId):
            return clearDocumentLinkedFinancialRecord(documentId)

        default:
            return nil
        }
    }

    private func applyProjectLinkIssueRepair(_ repair: DataHealthIssueRepair) -> Bool {
        switch repair {
        case .clearMaterialProject(let itemId):
            return clearMaterialProject(itemId)

        case .clearQuoteProject(let itemId):
            return clearQuoteProject(itemId)

        case .clearLaborProject(let recordId):
            return clearLaborProject(recordId)

        case .clearDailyLogProject(let logId):
            return clearDailyLogProject(logId)

        case .clearSiteTodoProject(let todoId):
            return clearSiteTodoProject(todoId)

        case .clearQuickNoteProject(let noteId):
            return clearQuickNoteProject(noteId)

        default:
            return false
        }
    }

    private func clearDailyLogLegacyPhoto(_ logId: UUID, _ fileName: String) -> Bool {
        var logs = store.dailyLogs
        guard let index = logs.firstIndex(where: { $0.id == logId }),
              logs[index].photoFileName == fileName else { return false }
        logs[index].photoFileName = nil
        store.replaceDailyLogs(logs)
        return true
    }

    private func removeDailyLogPhoto(_ logId: UUID, _ photoId: UUID) -> Bool {
        var logs = store.dailyLogs
        guard let index = logs.firstIndex(where: { $0.id == logId }) else { return false }
        let before = logs[index].photos.count
        logs[index].photos.removeAll { $0.id == photoId }
        guard logs[index].photos.count != before else { return false }
        store.replaceDailyLogs(logs)
        return true
    }

    private func clearSiteTodoBeforePhoto(_ todoId: UUID, _ fileName: String) -> Bool {
        var todos = store.siteTodos
        guard let index = todos.firstIndex(where: { $0.id == todoId }),
              todos[index].rectificationBeforePhotoFileName == fileName else { return false }
        todos[index].rectificationBeforePhotoFileName = nil
        store.replaceSiteTodos(todos)
        return true
    }

    private func clearSiteTodoAfterPhoto(_ todoId: UUID, _ fileName: String) -> Bool {
        var todos = store.siteTodos
        guard let index = todos.firstIndex(where: { $0.id == todoId }),
              todos[index].rectificationAfterPhotoFileName == fileName else { return false }
        todos[index].rectificationAfterPhotoFileName = nil
        store.replaceSiteTodos(todos)
        return true
    }

    private func removeProjectDocument(_ documentId: UUID) -> Bool {
        var documents = store.projectDocuments
        let before = documents.count
        documents.removeAll { $0.id == documentId }
        guard documents.count != before else { return false }
        store.replaceProjectDocuments(documents)
        removeDocumentLinks(documentId)
        return true
    }

    private func removeQuickNoteAttachment(_ noteId: UUID, _ attachmentId: UUID) -> Bool {
        var notes = store.quickNotes
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else { return false }
        let before = notes[index].attachments.count
        notes[index].attachments.removeAll { $0.id == attachmentId }
        guard notes[index].attachments.count != before else { return false }
        store.replaceQuickNotes(notes)
        return true
    }

    private func unlinkFinancialDocument(_ recordId: UUID, _ documentId: UUID) -> Bool {
        var records = store.projectFinancialRecords
        guard let index = records.firstIndex(where: { $0.id == recordId }),
              records[index].linkedDocumentIds.contains(documentId) else { return false }
        records[index].linkedDocumentIds.removeAll { $0 == documentId }
        store.replaceProjectFinancialRecords(records)
        return true
    }

    private func unlinkWarehouseDocument(_ movementId: UUID, _ documentId: UUID) -> Bool {
        var movements = store.projectWarehouseMovements
        guard let index = movements.firstIndex(where: { $0.id == movementId }),
              movements[index].linkedDocumentIds.contains(documentId) else { return false }
        movements[index].linkedDocumentIds.removeAll { $0 == documentId }
        store.replaceProjectWarehouseMovements(movements)
        return true
    }

    private func clearDocumentLinkedFinancialRecord(_ documentId: UUID) -> Bool {
        var documents = store.projectDocuments
        guard let index = documents.firstIndex(where: { $0.id == documentId }),
              documents[index].linkedFinancialRecordId != nil else { return false }
        documents[index].linkedFinancialRecordId = nil
        store.replaceProjectDocuments(documents)
        return true
    }

    private func clearMaterialProject(_ itemId: UUID) -> Bool {
        var items = store.materialItems
        guard let index = items.firstIndex(where: { $0.id == itemId }),
              items[index].projectId != nil else { return false }
        items[index].projectId = nil
        store.replaceMaterialItems(items)
        return true
    }

    private func clearQuoteProject(_ itemId: UUID) -> Bool {
        var items = store.quoteItems
        guard let index = items.firstIndex(where: { $0.id == itemId }),
              items[index].projectId != nil else { return false }
        items[index].projectId = nil
        store.replaceQuoteItems(items)
        return true
    }

    private func clearLaborProject(_ recordId: UUID) -> Bool {
        var records = store.laborRecords
        guard let index = records.firstIndex(where: { $0.id == recordId }),
              records[index].projectId != nil else { return false }
        records[index].projectId = nil
        store.replaceLaborRecords(records)
        return true
    }

    private func clearDailyLogProject(_ logId: UUID) -> Bool {
        var logs = store.dailyLogs
        guard let index = logs.firstIndex(where: { $0.id == logId }),
              logs[index].projectId != nil else { return false }
        logs[index].projectId = nil
        store.replaceDailyLogs(logs)
        return true
    }

    private func clearSiteTodoProject(_ todoId: UUID) -> Bool {
        var todos = store.siteTodos
        guard let index = todos.firstIndex(where: { $0.id == todoId }),
              todos[index].projectId != nil else { return false }
        todos[index].projectId = nil
        store.replaceSiteTodos(todos)
        return true
    }

    private func clearQuickNoteProject(_ noteId: UUID) -> Bool {
        var notes = store.quickNotes
        guard let index = notes.firstIndex(where: { $0.id == noteId }),
              notes[index].projectId != nil else { return false }
        notes[index].projectId = nil
        store.replaceQuickNotes(notes)
        return true
    }

    private func removeDocumentLinks(_ documentId: UUID) {
        var financialRecords = store.projectFinancialRecords
        var changedFinancialRecords = false
        for index in financialRecords.indices where financialRecords[index].linkedDocumentIds.contains(documentId) {
            financialRecords[index].linkedDocumentIds.removeAll { $0 == documentId }
            changedFinancialRecords = true
        }
        if changedFinancialRecords {
            store.replaceProjectFinancialRecords(financialRecords)
        }

        var warehouseMovements = store.projectWarehouseMovements
        var changedWarehouseMovements = false
        for index in warehouseMovements.indices where warehouseMovements[index].linkedDocumentIds.contains(documentId) {
            warehouseMovements[index].linkedDocumentIds.removeAll { $0 == documentId }
            changedWarehouseMovements = true
        }
        if changedWarehouseMovements {
            store.replaceProjectWarehouseMovements(warehouseMovements)
        }
    }
}
