import SwiftUI

extension MaterialListView {
    func toggleSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    func requestDeleteMaterials(
        ids: [UUID],
        message: String,
        successMessage: String,
        endSelectionAfterDelete: Bool = false
    ) {
        let normalizedIDs = Set(ids)
        guard !normalizedIDs.isEmpty else { return }
        pendingDeletePlan = PendingMaterialDeletePlan(
            ids: normalizedIDs,
            message: message,
            successMessage: successMessage,
            endSelectionAfterDelete: endSelectionAfterDelete
        )
        showDeleteConfirm = true
    }

    func confirmDeleteMaterials(_ plan: PendingMaterialDeletePlan) {
        let targets = store.materialItems.filter { plan.ids.contains($0.id) }
        guard !targets.isEmpty else {
            pendingDeletePlan = nil
            return
        }
        let deletion = store.removeMaterialItems(
            ids: plan.ids,
            audit: DataStoreDeletionAuditContext(
                summary: String(localized: "删除材料"),
                detail: materialDeletionDetail(targets),
                source: "MaterialListView"
            )
        )
        guard !deletion.isEmpty else {
            pendingDeletePlan = nil
            return
        }

        let removedIDs = deletion.removedIDs(\.id)
        let selectionSnapshot = selection
        let isSelectingSnapshot = isSelecting

        selection.subtract(removedIDs)
        if plan.endSelectionAfterDelete {
            selection.removeAll()
            isSelecting = false
        } else if selection.isEmpty {
            isSelecting = false
        }
        operationMessage = nil
        undoableDeletion.queue(
            notice: $operationNotice,
            message: plan.successMessage,
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.restoreMaterialItems(from: deletion)
                selection = selectionSnapshot
                isSelecting = isSelectingSnapshot
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
        pendingDeletePlan = nil
    }

    func clearAllMaterials() {
        let ids = Set(store.materialItems.map(\.id))
        guard !ids.isEmpty else { return }
        let deletion = store.removeMaterialItems(
            ids: ids,
            audit: DataStoreDeletionAuditContext(
                summary: String(localized: "清空全部材料"),
                detail: String(format: String(localized: "已删除 %lld 条材料"), Int64(ids.count)),
                source: "MaterialListView"
            )
        )
        guard !deletion.isEmpty else { return }

        let selectionSnapshot = selection
        let isSelectingSnapshot = isSelecting
        selection.removeAll()
        isSelecting = false
        operationMessage = nil

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(localized: "已清空全部材料"),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.restoreMaterialItems(from: deletion)
                selection = selectionSnapshot
                isSelecting = isSelectingSnapshot
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    func materialDeletionDetail(_ items: [MaterialItem]) -> String {
        ListFormatter.localizedString(byJoining: items.map(\.name))
    }

    func applyBulkProject() {
        store.replaceMaterialItems(store.materialItems.map { item in
            var updated = item
            if selection.contains(item.id) {
                updated.projectId = bulkProjectId
            }
            return updated
        })
        selection.removeAll()
        isSelecting = false
        bulkProjectId = nil
        store.scheduleSave()
        operationMessage = String(localized: "已批量更新归属项目")
    }

    func openFocusedMaterialIfNeeded() {
        guard let focusedMaterialId, !didOpenFocusedMaterial,
              let item = store.materialItems.first(where: { $0.id == focusedMaterialId }) else { return }
        didOpenFocusedMaterial = true
        searchText = ""
        projectFilter = item.projectId
        Task { @MainActor in
            editingItem = item
        }
    }

    func addItem() {
        guard canAddMaterial else { return }
        store.appendMaterialItem(
            MaterialItem(
                name: newName,
                quantity: newQty,
                unit: newUnit,
                unitPrice: newUnitPrice,
                specification: newSpecification,
                brand: newBrand,
                supplier: newSupplier,
                purchaseStatus: newPurchaseStatus,
                arrivalDate: ProjectDateInput.normalizedStorageText(newArrivalDate),
                projectId: newProjectId
            )
        )
        store.scheduleSave()
        operationMessage = String(localized: "已添加材料")
        newName = ""
        newQty = ""
        newUnit = ""
        newUnitPrice = ""
        newProjectId = nil
        newSpecification = ""
        newBrand = ""
        newSupplier = ""
        newPurchaseStatus = .notPurchased
        newArrivalDate = ""
    }

    var canAddMaterial: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !newUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        InputValidator.validate(newQty, kind: .quantity, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(newUnitPrice, kind: .amount, requirement: .optionalNonNegative).isValid
    }

    func applyMaterialTemplate(_ template: ProjectTemplate) {
        guard let line = template.content
            .split(separator: "\n")
            .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else { return }
        let parsed = NumericInputSupport.parseMaterialTemplateLine(
            line,
            defaultNumber: "1",
            defaultUnit: String(localized: "材料默认单位")
        )
        newName = parsed.name.isEmpty ? template.name : parsed.name
        newQty = parsed.quantity
        newUnit = parsed.unit
        operationMessage = String(localized: "已套用材料模板")
    }
}
