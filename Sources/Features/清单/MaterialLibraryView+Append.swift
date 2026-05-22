import SwiftUI

extension MaterialLibraryView {
    var activeMaterialSheetDraftIDs: [UUID] {
        activeMaterialSheetDrafts.map(\.id)
    }

    var pendingAddContextID: UUID? {
        appendState.pendingAddContext?.id
    }

    var defaultTargetMaterialSheetDraft: MaterialSheetDraft? {
        MaterialLibraryLogicHelpers.defaultTargetDraft(
            activeDrafts: activeMaterialSheetDrafts,
            selectedDefaultDraftID: appendState.selectedDefaultMaterialSheetDraftID,
            rememberedDraftIDRaw: lastAppendDraftIDRaw
        )
    }

    var defaultMaterialSheetTargetBar: some View {
        MaterialLibraryDefaultTargetBar(
            draft: defaultTargetMaterialSheetDraft,
            activeDrafts: activeMaterialSheetDrafts,
            draftTitle: { draft in
                MaterialLibraryLogicHelpers.materialSheetDraftPickerTitle(draft, projects: projects)
            },
            projectName: { projectID in
                MaterialLibraryLogicHelpers.projectName(for: projectID, projects: projects)
            },
            recentlyAddedSummary: { draft in
                MaterialLibraryLogicHelpers.recentlyAddedSummary(
                    for: draft,
                    recentlyAddedDraftID: appendState.recentlyAddedDraftID,
                    recentlyAddedItemCount: appendState.recentlyAddedItemCount
                )
            },
            onSelectDraft: { draftID in
                appendState.selectedDefaultMaterialSheetDraftID = draftID
            },
            onCreateDraft: {
                createAndSelectDefaultMaterialSheetDraft()
            },
            onOpenDraft: { draftID in
                appendState.recentlyAddedDraftID = draftID
                appendState.navigateToMaterialSheet = true
            }
        )
    }

    func prepareAppendMaterial(_ context: PendingMaterialAppendContext) {
        appendState.pendingAddContext = context
        appendState.pendingAddQuantity = "1"
        appendState.pendingAddUnitPrice = context.defaultUnitPrice
        appendState.pendingAddNote = ""
        appendState.pendingAddProjectId = nil
        applyDefaultAppendTarget()
        appendState.pendingAddDraftTitle = MaterialLibraryLogicHelpers.defaultMaterialSheetDraftTitle(
            projectId: appendState.pendingAddProjectId,
            projects: projects
        )
    }

    @discardableResult
    func confirmAppendMaterials(
        _ contexts: [PendingMaterialAppendContext],
        quantityText: String,
        showPostAddPrompt: Bool = true,
        deferToastUntilSheetDismissal: Bool = false
    ) -> Bool {
        appendMaterialsToSheet(
            contexts,
            quantityText: quantityText,
            showPostAddPrompt: showPostAddPrompt,
            deferToastUntilSheetDismissal: deferToastUntilSheetDismissal
        ) { context in
            context.defaultUnitPrice
        }
    }

    @discardableResult
    func appendMaterialsToSheet(
        _ contexts: [PendingMaterialAppendContext],
        quantityText: String,
        showPostAddPrompt: Bool = true,
        deferToastUntilSheetDismissal: Bool = false,
        unitPriceResolver: (PendingMaterialAppendContext) -> String
    ) -> Bool {
        guard !contexts.isEmpty else { return false }
        let computation = MaterialLibraryLogicHelpers.computeAppendComputation(
            contexts: contexts,
            quantityText: quantityText,
            noteText: appendState.pendingAddNote,
            targetMode: appendState.pendingAddTargetMode,
            targetDraftID: appendState.pendingAddDraftId,
            targetProjectID: appendState.pendingAddProjectId,
            draftTitleInput: appendState.pendingAddDraftTitle,
            drafts: materialSheetDrafts,
            projects: projects,
            now: Formatters.now(),
            unitPriceResolver: unitPriceResolver
        )

        switch computation {
        case .failure(let message, let nextPendingTargetMode, let nextPendingDraftID):
            operationMessage = message
            appendState.pendingAddTargetMode = nextPendingTargetMode
            appendState.pendingAddDraftId = nextPendingDraftID
            return false
        case .success(let output):
            store.replaceMaterialSheetDrafts(output.drafts)
            contexts.forEach { appendRecentMaterialKey($0.key) }
            store.scheduleSave()

            lastAppendTargetModeRaw = MaterialSheetTargetMode.existing.rawValue
            lastAppendDraftIDRaw = output.targetDraftID.uuidString
            lastAppendProjectIDRaw = output.lastProjectIDRaw

            appendState.pendingAddTargetMode = output.nextPendingTargetMode
            appendState.pendingAddDraftId = output.nextPendingDraftID
            appendState.selectedDefaultMaterialSheetDraftID = output.nextSelectedDefaultDraftID
            showOperationMessage(
                MaterialLibraryLogicHelpers.appendSuccessMessage(
                    itemCount: contexts.count,
                    draftTitle: output.targetTitle
                ),
                deferUntilDismissal: deferToastUntilSheetDismissal
            )
            appendState.selectedDefaultMaterialSheetDraftID = output.targetDraftID
            appendState.recentlyAddedDraftID = output.targetDraftID
            appendState.recentlyAddedDraftTitle = output.targetTitle
            appendState.recentlyAddedItemCount = contexts.count
            appendState.showOpenMaterialSheetPrompt = promptAfterAdd && showPostAddPrompt
            return true
        }
    }

    func showOperationMessage(_ message: String, deferUntilDismissal: Bool = false) {
        if deferUntilDismissal {
            appendState.deferredOperationMessage = message
        } else {
            operationMessage = message
        }
    }

    func flushDeferredOperationMessage() {
        guard let message = appendState.deferredOperationMessage else { return }
        appendState.deferredOperationMessage = nil
        operationMessage = message
    }

    func handlePendingAddContextChange(_: UUID?, _ newValue: UUID?) {
        if newValue != nil { return }
        flushDeferredOperationMessage()
    }

    var activeMaterialSheetDrafts: [MaterialSheetDraft] {
        MaterialLibraryLogicHelpers.activeMaterialSheetDrafts(from: materialSheetDrafts)
    }

    func applyDefaultAppendTarget() {
        if let draft = defaultTargetMaterialSheetDraft {
            appendState.pendingAddTargetMode = .existing
            appendState.pendingAddDraftId = draft.id
            appendState.pendingAddProjectId = nil
            return
        }
        let target = MaterialLibraryLogicHelpers.rememberedTargetState(
            lastModeRaw: lastAppendTargetModeRaw,
            lastDraftIDRaw: lastAppendDraftIDRaw,
            lastProjectIDRaw: lastAppendProjectIDRaw,
            activeDrafts: activeMaterialSheetDrafts,
            projects: projects
        )
        appendState.pendingAddTargetMode = target.mode
        appendState.pendingAddDraftId = target.draftID
        appendState.pendingAddProjectId = target.projectID
    }

    func ensureDefaultMaterialSheetSelection() {
        appendState.selectedDefaultMaterialSheetDraftID = MaterialLibraryLogicHelpers.ensureDefaultSelection(
            selectedDefaultDraftID: appendState.selectedDefaultMaterialSheetDraftID,
            rememberedDraftIDRaw: lastAppendDraftIDRaw,
            activeDrafts: activeMaterialSheetDrafts
        )
    }

    @discardableResult
    func createAndSelectDefaultMaterialSheetDraft() -> UUID {
        let now = Formatters.now()
        let newDraft = MaterialSheetDraft(
            title: MaterialLibraryLogicHelpers.defaultMaterialSheetDraftTitle(
                projectId: nil,
                projects: projects
            ),
            items: [],
            createdAt: now,
            updatedAt: now
        )
        store.insertMaterialSheetDraftAtTop(newDraft)
        store.scheduleSave()
        appendState.selectedDefaultMaterialSheetDraftID = newDraft.id
        lastAppendTargetModeRaw = MaterialSheetTargetMode.existing.rawValue
        lastAppendDraftIDRaw = newDraft.id.uuidString
        lastAppendProjectIDRaw = ""
        operationMessage = "已创建默认材料单「\(newDraft.title)」"
        return newDraft.id
    }

    var canAppendMaterialToSheet: Bool {
        switch appendState.pendingAddTargetMode {
        case .existing:
            return appendState.pendingAddDraftId != nil
        case .create:
            return true
        }
    }
}
