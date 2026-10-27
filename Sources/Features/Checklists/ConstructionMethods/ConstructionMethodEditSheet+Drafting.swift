import SwiftUI

extension ConstructionMethodEditSheet {
    var formSnapshot: ConstructionMethodEditFormSnapshot {
        ConstructionMethodEditFormSnapshot(
            title: title,
            trade: trade,
            versionName: versionName,
            publishStatus: publishStatus,
            tutorialBody: tutorialBody,
            tutorialAttachments: tutorialAttachments,
            procedureSteps: procedureSteps,
            qualityChecklist: qualityChecklist,
            safetyChecklist: safetyChecklist
        )
    }

    var hasDraftContent: Bool {
        formSnapshot.hasDraftContent
    }

    var draftAutosaveFingerprint: String {
        formSnapshot.autosaveFingerprint
    }

    func cancelEditingAndDismiss() {
        draftSaveTask?.cancel()
        if hasDraftContent {
            persistDraftImmediately()
        } else {
            ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
        }
        dismiss()
    }

    func saveAndDismiss() {
        draftSaveTask?.cancel()
        didSave = true
        onSave(formSnapshot.applying(to: method))
        ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
        dismiss()
    }

    func deleteAndDismiss() {
        draftSaveTask?.cancel()
        ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
        if let target = method {
            onDelete?(target)
        }
        dismiss()
    }

    func restoreDraftIfNeeded() {
        guard let draft = ConstructionMethodEditDraftStore.load(methodID: method?.id, scopeID: draftScopeID) else { return }
        title = draft.title
        trade = draft.trade
        versionName = draft.versionName
        publishStatus = draft.publishStatus
        tutorialBody = draft.tutorialBody
        tutorialAttachments = draft.tutorialAttachments
        procedureSteps = draft.procedureSteps
        qualityChecklist = draft.qualityChecklist
        safetyChecklist = draft.safetyChecklist
        didRestoreDraft = true
    }

    func scheduleDraftSave() {
        guard hasDraftContent else {
            ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
            return
        }
        let snapshot = formSnapshot.draft
        let methodID = method?.id
        let scopeID = draftScopeID
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            guard await DebouncedTask.wait(for: .milliseconds(350)) else { return }
            ConstructionMethodEditDraftStore.save(snapshot, methodID: methodID, scopeID: scopeID)
        }
    }

    func persistDraftImmediately() {
        guard hasDraftContent else {
            ConstructionMethodEditDraftStore.clear(methodID: method?.id, scopeID: draftScopeID)
            return
        }
        let snapshot = formSnapshot.draft
        ConstructionMethodEditDraftStore.save(snapshot, methodID: method?.id, scopeID: draftScopeID)
    }
}
