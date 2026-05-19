import Foundation

@MainActor
extension DataStore {
    func appendProjectContact(_ contact: ProjectContact) {
        replaceProjectContacts(projectContacts + [contact])
    }

    func insertProjectContactAtTop(_ contact: ProjectContact) {
        var contacts = projectContacts
        contacts.insert(contact, at: 0)
        replaceProjectContacts(contacts)
    }

    func mergeProjectContactsByID(_ contacts: [ProjectContact]) {
        replaceProjectContacts(mergedProjectRecordElementsByID(projectContacts, with: contacts))
    }

    func upsertProjectContact(
        _ contact: ProjectContact,
        insertAtTopWhenNew: Bool = false
    ) {
        var currentContacts = projectContacts
        if let index = currentContacts.firstIndex(where: { $0.id == contact.id }) {
            currentContacts[index] = contact
            replaceProjectContacts(currentContacts)
            return
        }
        if insertAtTopWhenNew {
            currentContacts.insert(contact, at: 0)
        } else {
            currentContacts.append(contact)
        }
        replaceProjectContacts(currentContacts)
    }

    func restoreProjectContacts(from deletion: DataStoreRemovalResult<ProjectContact>) {
        replaceProjectContacts(deletion.restoredItems(current: projectContacts, id: \.id))
    }

    @discardableResult
    func removeProjectContact(
        id: UUID,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectContact> {
        removeProjectRecordElements(
            from: projectContacts,
            ids: Set([id]),
            id: \.id,
            replace: replaceProjectContacts,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    func removeProjectContacts(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectContact> {
        removeProjectRecordElements(
            from: projectContacts,
            ids: ids,
            id: \.id,
            replace: replaceProjectContacts,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendProjectFinancialRecord(_ record: ProjectFinancialRecord) {
        replaceProjectFinancialRecords(projectFinancialRecords + [record])
    }

    func appendProjectFinancialRecords(_ records: [ProjectFinancialRecord]) {
        guard !records.isEmpty else { return }
        replaceProjectFinancialRecords(projectFinancialRecords + records)
    }

    @discardableResult
    func updateProjectFinancialRecord(_ record: ProjectFinancialRecord) -> Bool {
        var current = projectFinancialRecords
        guard let index = current.firstIndex(where: { $0.id == record.id }) else { return false }
        current[index] = record
        replaceProjectFinancialRecords(current)
        return true
    }

    @discardableResult
    func mutateProjectFinancialRecord(
        id: UUID,
        _ mutation: (inout ProjectFinancialRecord) -> Void
    ) -> Bool {
        var current = projectFinancialRecords
        guard let index = current.firstIndex(where: { $0.id == id }) else { return false }
        mutation(&current[index])
        replaceProjectFinancialRecords(current)
        return true
    }

    func mergeProjectFinancialRecordsByID(_ records: [ProjectFinancialRecord]) {
        replaceProjectFinancialRecords(mergedProjectRecordElementsByID(projectFinancialRecords, with: records))
    }

    func restoreProjectFinancialRecords(from deletion: DataStoreRemovalResult<ProjectFinancialRecord>) {
        replaceProjectFinancialRecords(deletion.restoredItems(current: projectFinancialRecords, id: \.id))
    }

    @discardableResult
    func removeProjectFinancialRecords(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectFinancialRecord> {
        removeProjectRecordElements(
            from: projectFinancialRecords,
            ids: ids,
            id: \.id,
            replace: replaceProjectFinancialRecords,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendProjectDocument(_ document: ProjectDocument) {
        replaceProjectDocuments(projectDocuments + [document])
    }

    func appendProjectDocuments(_ documents: [ProjectDocument]) {
        guard !documents.isEmpty else { return }
        replaceProjectDocuments(projectDocuments + documents)
    }

    @discardableResult
    func updateProjectDocument(_ document: ProjectDocument) -> Bool {
        var current = projectDocuments
        guard let index = current.firstIndex(where: { $0.id == document.id }) else { return false }
        current[index] = document
        replaceProjectDocuments(current)
        return true
    }

    @discardableResult
    func mutateProjectDocument(
        id: UUID,
        _ mutation: (inout ProjectDocument) -> Void
    ) -> Bool {
        var current = projectDocuments
        guard let index = current.firstIndex(where: { $0.id == id }) else { return false }
        mutation(&current[index])
        replaceProjectDocuments(current)
        return true
    }

    func mergeProjectDocumentsByID(_ documents: [ProjectDocument]) {
        replaceProjectDocuments(mergedProjectRecordElementsByID(projectDocuments, with: documents))
    }

    func restoreProjectDocuments(from deletion: DataStoreRemovalResult<ProjectDocument>) {
        replaceProjectDocuments(deletion.restoredItems(current: projectDocuments, id: \.id))
    }

    @discardableResult
    func removeProjectDocuments(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectDocument> {
        removeProjectRecordElements(
            from: projectDocuments,
            ids: ids,
            id: \.id,
            replace: replaceProjectDocuments,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendQuickNote(_ note: QuickNote) {
        replaceQuickNotes(quickNotes + [note])
    }

    func insertQuickNoteAtTop(_ note: QuickNote) {
        var notes = quickNotes
        notes.insert(note, at: 0)
        replaceQuickNotes(notes)
    }

    @discardableResult
    func updateQuickNote(_ note: QuickNote) -> Bool {
        var current = quickNotes
        guard let index = current.firstIndex(where: { $0.id == note.id }) else { return false }
        current[index] = note
        replaceQuickNotes(current)
        return true
    }

    @discardableResult
    func mutateQuickNote(
        id: UUID,
        _ mutation: (inout QuickNote) -> Void
    ) -> Bool {
        var current = quickNotes
        guard let index = current.firstIndex(where: { $0.id == id }) else { return false }
        mutation(&current[index])
        replaceQuickNotes(current)
        return true
    }

    func mergeQuickNotesByID(_ notes: [QuickNote]) {
        replaceQuickNotes(mergedProjectRecordElementsByID(quickNotes, with: notes))
    }

    func restoreQuickNotes(from deletion: DataStoreRemovalResult<QuickNote>) {
        replaceQuickNotes(deletion.restoredItems(current: quickNotes, id: \.id))
    }

    @discardableResult
    func removeQuickNotes(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<QuickNote> {
        removeProjectRecordElements(
            from: quickNotes,
            ids: ids,
            id: \.id,
            replace: replaceQuickNotes,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendProjectWarehouseMovement(_ movement: ProjectWarehouseMovement) {
        replaceProjectWarehouseMovements(projectWarehouseMovements + [movement])
    }

    func insertProjectWarehouseMovementAtTop(_ movement: ProjectWarehouseMovement) {
        var movements = projectWarehouseMovements
        movements.insert(movement, at: 0)
        replaceProjectWarehouseMovements(movements)
    }

    @discardableResult
    func updateProjectWarehouseMovement(_ movement: ProjectWarehouseMovement) -> Bool {
        var current = projectWarehouseMovements
        guard let index = current.firstIndex(where: { $0.id == movement.id }) else { return false }
        current[index] = movement
        replaceProjectWarehouseMovements(current)
        return true
    }

    @discardableResult
    func mutateProjectWarehouseMovement(
        id: UUID,
        _ mutation: (inout ProjectWarehouseMovement) -> Void
    ) -> Bool {
        var current = projectWarehouseMovements
        guard let index = current.firstIndex(where: { $0.id == id }) else { return false }
        mutation(&current[index])
        replaceProjectWarehouseMovements(current)
        return true
    }

    func mergeProjectWarehouseMovementsByID(_ movements: [ProjectWarehouseMovement]) {
        replaceProjectWarehouseMovements(mergedProjectRecordElementsByID(projectWarehouseMovements, with: movements))
    }

    func restoreProjectWarehouseMovements(from deletion: DataStoreRemovalResult<ProjectWarehouseMovement>) {
        replaceProjectWarehouseMovements(deletion.restoredItems(current: projectWarehouseMovements, id: \.id))
    }

    @discardableResult
    func removeProjectWarehouseMovements(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectWarehouseMovement> {
        removeProjectRecordElements(
            from: projectWarehouseMovements,
            ids: ids,
            id: \.id,
            replace: replaceProjectWarehouseMovements,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    private func mergedProjectRecordElementsByID<Element: Identifiable>(
        _ current: [Element],
        with incoming: [Element]
    ) -> [Element] where Element.ID: Hashable {
        guard !incoming.isEmpty else { return current }
        var merged = current
        var existingIDs = Set(current.map(\.id))
        for item in incoming where existingIDs.insert(item.id).inserted {
            merged.append(item)
        }
        return merged
    }

    @discardableResult
    private func removeProjectRecordElements<Element, ID: Hashable>(
        from current: [Element],
        ids: Set<ID>,
        id: (Element) -> ID,
        replace: ([Element]) -> Void,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<Element> {
        guard !ids.isEmpty else {
            return DataStoreRemovalResult(
                snapshot: current,
                removed: [],
                audit: audit,
                deferredFileCleanup: deferredFileCleanup
            )
        }

        let removed = current.filter { ids.contains(id($0)) }
        guard !removed.isEmpty else {
            return DataStoreRemovalResult(
                snapshot: current,
                removed: [],
                audit: audit,
                deferredFileCleanup: deferredFileCleanup
            )
        }

        replace(current.filter { !ids.contains(id($0)) })

        let result = DataStoreRemovalResult(
            snapshot: current,
            removed: removed,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup
        )
        if recordsAuditImmediately {
            result.recordAuditStarted()
            result.performDeferredFileCleanup()
            result.recordAuditSucceeded()
        }
        return result
    }
}
