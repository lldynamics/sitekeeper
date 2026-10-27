import Foundation

extension MaterialLibraryLogicHelpers {
    static func computeAppendComputation(
        contexts: [PendingMaterialAppendContext],
        quantityText: String,
        noteText: String,
        targetMode: MaterialSheetTargetMode,
        targetDraftID: UUID?,
        targetProjectID: UUID?,
        draftTitleInput: String,
        drafts: [MaterialSheetDraft],
        projects: [Project],
        now: BusinessDateValue,
        unitPriceResolver: (PendingMaterialAppendContext) -> String
    ) -> AppendComputationResult {
        let validation = appendQuantityValidation(quantityText)
        guard validation.isValid, let quantity = validation.decimalValue else {
            return .failure(
                message: validation.errorMessage ?? AppLocalization.string("数量格式不正确"),
                nextPendingTargetMode: targetMode,
                nextPendingDraftID: targetDraftID
            )
        }
        let validQuantity = NSDecimalNumber(decimal: quantity).stringValue
        let note = contexts.count == 1 ? noteText.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let draftItems = contexts.map { context in
            MaterialSheetDraftItem(
                name: context.name,
                specification: context.specification,
                unit: context.unit,
                quantity: NumericInputSupport.quantity(validQuantity),
                unitPrice: NumericInputSupport.money(unitPriceResolver(context).trimmingCharacters(in: .whitespacesAndNewlines)),
                supplier: context.defaultSupplier,
                note: note
            )
        }

        switch targetMode {
        case .existing:
            return appendToExistingDraft(draftItems, targetDraftID: targetDraftID, drafts: drafts, now: now)
        case .create:
            return appendToNewDraft(draftItems, titleInput: draftTitleInput, projectID: targetProjectID,
                                    drafts: drafts, projects: projects, now: now)
        }
    }

    private static func appendToExistingDraft(
        _ items: [MaterialSheetDraftItem], targetDraftID: UUID?, drafts: [MaterialSheetDraft], now: BusinessDateValue
    ) -> AppendComputationResult {
        var mutableDrafts = drafts
        guard let targetDraftID,
              let draftIndex = mutableDrafts.firstIndex(where: { $0.id == targetDraftID }) else {
            return .failure(
                message: "未找到可用材料单，请切换到“新建材料单”后重试",
                nextPendingTargetMode: .create,
                nextPendingDraftID: nil
            )
        }
        mutableDrafts[draftIndex].items.insert(contentsOf: items, at: 0)
        mutableDrafts[draftIndex].updatedAt = now
        let target = mutableDrafts[draftIndex]
        return .success(appendResult(drafts: mutableDrafts, target: target))
    }

    private static func appendToNewDraft(
        _ items: [MaterialSheetDraftItem], titleInput: String, projectID: UUID?,
        drafts: [MaterialSheetDraft], projects: [Project], now: BusinessDateValue
    ) -> AppendComputationResult {
        let resolvedTitle = resolvedMaterialSheetDraftTitle(inputTitle: titleInput, projectId: projectID, projects: projects)
        let newDraft = MaterialSheetDraft(
            title: resolvedTitle,
            projectId: projectID,
            exportProjectName: projectName(for: projectID, projects: projects) ?? "",
            items: items,
            createdAt: now,
            updatedAt: now
        )
        var mutableDrafts = drafts
        mutableDrafts.insert(newDraft, at: 0)
        return .success(appendResult(drafts: mutableDrafts, target: newDraft))
    }

    private static func appendResult(drafts: [MaterialSheetDraft], target: MaterialSheetDraft) -> AppendComputation {
        AppendComputation(
            drafts: drafts,
            targetDraftID: target.id,
            targetTitle: target.title,
            lastProjectIDRaw: target.projectId?.uuidString ?? "",
            nextPendingTargetMode: .existing,
            nextPendingDraftID: target.id,
            nextSelectedDefaultDraftID: target.id
        )
    }
}
