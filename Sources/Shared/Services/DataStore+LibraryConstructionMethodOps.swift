import Foundation

@MainActor
extension DataStore {
    func mergeConstructionMethodsByID(_ methods: [ConstructionMethod]) {
        replaceConstructionMethods(mergedUniqueByID(constructionMethods, with: methods))
    }

    func upsertConstructionMethod(
        _ method: ConstructionMethod,
        insertAtTopWhenNew: Bool = false
    ) {
        var currentMethods = constructionMethods
        if let index = currentMethods.firstIndex(where: { $0.id == method.id }) {
            currentMethods[index] = method
            replaceConstructionMethods(currentMethods)
            return
        }
        if insertAtTopWhenNew {
            currentMethods.insert(method, at: 0)
        } else {
            currentMethods.append(method)
        }
        replaceConstructionMethods(currentMethods)
    }

    func restoreConstructionMethods(from deletion: DataStoreRemovalResult<ConstructionMethod>) {
        replaceConstructionMethods(deletion.restoredItems(current: constructionMethods, id: \.id))
    }

    @discardableResult
    func removeConstructionMethods(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ConstructionMethod> {
        removeLibraryElements(
            from: constructionMethods,
            ids: ids,
            id: \.id,
            replace: replaceConstructionMethods,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }
}
