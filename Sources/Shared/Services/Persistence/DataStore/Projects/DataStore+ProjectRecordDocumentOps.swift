import Foundation

@MainActor
extension DataStore {
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
}
