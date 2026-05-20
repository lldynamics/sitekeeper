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
}
