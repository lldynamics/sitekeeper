import Foundation

@MainActor
extension DataStore {
    func appendTemplate(_ template: ProjectTemplate) {
        replaceTemplates(templates + [template])
    }

    func mergeTemplatesByID(_ templates: [ProjectTemplate]) {
        replaceTemplates(mergedUniqueByID(self.templates, with: templates))
    }

    func insertTemplateAtTop(_ template: ProjectTemplate) {
        var currentTemplates = templates
        currentTemplates.insert(template, at: 0)
        replaceTemplates(currentTemplates)
    }

    func upsertTemplate(
        _ template: ProjectTemplate,
        insertAtTopWhenNew: Bool = false
    ) {
        var currentTemplates = templates
        if let index = currentTemplates.firstIndex(where: { $0.id == template.id }) {
            currentTemplates[index] = template
            replaceTemplates(currentTemplates)
            return
        }
        if insertAtTopWhenNew {
            currentTemplates.insert(template, at: 0)
        } else {
            currentTemplates.append(template)
        }
        replaceTemplates(currentTemplates)
    }

    func restoreTemplates(from deletion: DataStoreRemovalResult<ProjectTemplate>) {
        replaceTemplates(deletion.restoredItems(current: templates, id: \.id))
    }

    @discardableResult
    func removeTemplates(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectTemplate> {
        removeLibraryElements(
            from: templates,
            ids: ids,
            id: \.id,
            replace: replaceTemplates,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }
}
