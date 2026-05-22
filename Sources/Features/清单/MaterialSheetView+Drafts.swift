import SwiftUI

extension MaterialSheetView {
    var currentMaterialSection: some View {
        Section {
            currentMaterialSectionContent
        } header: {
            currentMaterialSheetHeader
        }
    }

    @ViewBuilder
    var currentMaterialSectionContent: some View {
        if sheetItems.isEmpty {
            emptyMaterialSheetPlaceholder
        } else {
            ForEach($sheetItems) { $item in
                materialItemRow($item)
            }
            .onDelete { offsets in
                let ids = offsets.compactMap { sheetItems.indices.contains($0) ? sheetItems[$0].id : nil }
                requestDeleteSheetItems(ids: ids)
            }
        }
    }

    var emptyMaterialSheetPlaceholder: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(String(localized: "材料单为空"))
                    .foregroundStyle(.secondary)
                Text(String(localized: "在上方搜索材料库添加"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 20)
            Spacer()
        }
    }

    @ViewBuilder
    var currentMaterialSheetHeader: some View {
        MaterialSheetCurrentHeader(itemCountText: currentMaterialSheetItemCountText)
    }

    var currentMaterialSheetItemCountText: String? {
        guard !sheetItems.isEmpty else { return nil }
        return String(format: String(localized: "%d 项"), sheetItems.count)
    }

    func draftDisplayName(_ draft: MaterialSheetDraft) -> String {
        MaterialSheetLogicHelpers.draftDisplayName(draft)
    }

    func projectName(for projectId: UUID) -> String? {
        MaterialSheetLogicHelpers.projectName(for: projectId, projects: store.projects)
    }

    func defaultDraftTitle(projectId: UUID?) -> String {
        MaterialSheetLogicHelpers.defaultDraftTitle(
            projectId: projectId,
            projects: store.projects
        )
    }

    func prepareCreateDraftSheet() {
        let input = MaterialSheetLogicHelpers.createDraftSheetInput(
            selectedDraft: selectedDraft,
            projects: store.projects
        )
        draftProjectIdInput = input.projectID
        draftTitleInput = input.title
        showCreateDraftSheet = true
    }

    func prepareRenameDraftSheet() {
        guard let selectedDraft else { return }
        renameDraftTitleInput = draftDisplayName(selectedDraft)
        showRenameDraftSheet = true
    }

    func createDraftAndSelect(title: String, projectId: UUID?) {
        let newDraft = MaterialSheetLogicHelpers.makeDraft(
            title: title,
            projectId: projectId,
            projects: store.projects,
            now: Formatters.now(),
            items: []
        )
        store.replaceMaterialSheetDrafts(
            MaterialSheetLogicHelpers.insertingDraftAtTop(newDraft, drafts: store.materialSheetDrafts)
        )
        store.scheduleSave()
        selectedDraftID = newDraft.id
    }

    func renameSelectedDraft(to title: String) {
        guard let drafts = MaterialSheetLogicHelpers.renamedDrafts(
            selectedDraftID: selectedDraftID,
            title: title,
            drafts: store.materialSheetDrafts,
            now: Formatters.now()
        ) else { return }
        store.replaceMaterialSheetDrafts(drafts)
        store.scheduleSave()
    }

    func archiveSelectedDraft() {
        guard let context = MaterialSheetLogicHelpers.archiveContext(
            selectedDraftID: selectedDraftID,
            drafts: store.materialSheetDrafts,
            now: Formatters.now()
        ) else { return }
        store.replaceMaterialSheetDrafts(context.updatedDrafts)
        store.scheduleSave()

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(
                format: String(localized: "已归档材料单「%@」"),
                draftDisplayName(context.archivedDraft)
            ),
            undoMessage: String(localized: "已恢复材料单草稿"),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.replaceMaterialSheetDrafts(UndoableDeletionCoordinator.restoringItems(
                    snapshot: context.previousDrafts,
                    current: store.materialSheetDrafts,
                    deletedIDs: Set([context.archivedDraft.id])
                ))
                self.selectedDraftID = context.previousSelectedDraftID
                loadSelectedDraftIntoEditor()
                store.scheduleSave()
            },
            audit: UndoableDeletionAuditContext(
                summary: String(localized: "归档材料单草稿"),
                detail: draftDisplayName(context.archivedDraft),
                source: "MaterialSheetView"
            )
        )
    }

    func ensureDraftSelection() {
        if activeMaterialSheetDrafts.isEmpty {
            selectedDraftID = nil
            isApplyingDraftState = true
            sheetItems = []
            exportProjectName = ""
            exportPreparer = ""
            itemExpanded.removeAll()
            rowPhotoSelections.removeAll()
            pendingDeleteSheetItemIDs.removeAll()
            isApplyingDraftState = false
            return
        }
        selectedDraftID = MaterialSheetLogicHelpers.resolvedSelectedDraftID(
            currentSelectedDraftID: selectedDraftID,
            activeDraftIDs: activeMaterialSheetDraftIDs
        )
    }

    func loadSelectedDraftIntoEditor() {
        guard let selectedDraft else { return }
        let editorState = MaterialSheetLogicHelpers.draftEditorState(
            draft: selectedDraft,
            projects: store.projects
        )
        isApplyingDraftState = true
        sheetItems = editorState.sheetItems
        exportProjectName = editorState.exportProjectName
        exportPreparer = editorState.exportPreparer
        itemExpanded.removeAll()
        rowPhotoSelections.removeAll()
        pendingDeleteSheetItemIDs.removeAll()
        isApplyingDraftState = false
    }

    func persistCurrentDraft() {
        guard !isApplyingDraftState,
              let drafts = MaterialSheetLogicHelpers.persistingDrafts(
                selectedDraftID: selectedDraftID,
                drafts: store.materialSheetDrafts,
                sheetItems: sheetItems,
                exportProjectName: exportProjectName,
                exportPreparer: exportPreparer,
                exportDate: Formatters.date.string(from: Date()),
                now: Formatters.now()
              ) else { return }
        store.replaceMaterialSheetDrafts(drafts)
        store.scheduleSave()
    }
}
