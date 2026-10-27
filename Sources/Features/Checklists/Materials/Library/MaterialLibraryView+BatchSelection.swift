import SwiftUI

extension MaterialLibraryView {
    var selectedBatchMaterialContexts: [PendingMaterialAppendContext] {
        batchState.selectedMaterialContextsByKey.values
            .sorted { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    var pendingBatchAddContextID: UUID? {
        batchState.pendingBatchAddContext?.id
    }

    func toggleBatchMaterialSelection(_ context: PendingMaterialAppendContext) {
        batchState.selectedMaterialContextsByKey = MaterialLibraryLogicHelpers.toggledBatchSelection(
            selectedByKey: batchState.selectedMaterialContextsByKey,
            context: context
        )
    }

    func exitBatchSelectionMode() {
        batchState.isBatchSelectionMode = false
        batchState.selectedMaterialContextsByKey = [:]
        batchState.pendingBatchAddContext = nil
    }

    @ViewBuilder
    var batchAppendActionBar: some View {
        MaterialLibraryBatchAppendActionBar(
            selectedCount: selectedBatchMaterialContexts.count,
            onClear: {
                batchState.selectedMaterialContextsByKey = [:]
            },
            onOpenBatchAppend: {
                openBatchAppendSheet()
            }
        )
    }

    func openBatchAppendSheet() {
        let contexts = selectedBatchMaterialContexts
        guard !contexts.isEmpty else {
            operationMessage = "请先选择材料"
            return
        }
        batchState.pendingBatchAddQuantity = "1"
        appendState.pendingAddNote = ""
        appendState.pendingAddProjectId = nil
        applyDefaultAppendTarget()
        appendState.pendingAddDraftTitle = MaterialLibraryLogicHelpers.defaultMaterialSheetDraftTitle(
            projectId: appendState.pendingAddProjectId,
            projects: projects
        )
        batchState.pendingBatchAddContext = PendingBatchMaterialAppendContext(materials: contexts)
    }

    func handlePendingBatchAddContextChange(_: UUID?, _ newValue: UUID?) {
        if newValue != nil { return }
        flushDeferredOperationMessage()
    }
}
