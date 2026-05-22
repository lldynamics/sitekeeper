import SwiftUI

private struct MaterialLibrarySheetPresentationsModifier: ViewModifier {
    @Binding var showAddSheet: Bool
    let initialCategory: String?
    let availableCategories: [String]
    let onAddMaterial: (UserMaterial, String) -> Void

    @Binding var priceEditorContext: MaterialPriceEditorContext?
    let supplierProfiles: [SupplierProfile]
    let onSavePriceEntry: (MaterialPriceEntry) -> Void
    let onDeletePriceEntry: (MaterialPriceEntry) -> Void

    @Binding var pendingAddContext: PendingMaterialAppendContext?
    let activeMaterialSheetDrafts: [MaterialSheetDraft]
    let projects: [Project]
    let draftPickerTitle: (MaterialSheetDraft) -> String
    @Binding var pendingAddQuantity: String
    @Binding var pendingAddUnitPrice: String
    @Binding var pendingAddNote: String
    @Binding var pendingAddTargetMode: MaterialSheetTargetMode
    @Binding var pendingAddDraftID: UUID?
    @Binding var pendingAddDraftTitle: String
    @Binding var pendingAddProjectID: UUID?
    var appendMaterialFocusedField: FocusState<AppendMaterialField?>.Binding
    @Binding var operationMessage: String?
    let canAppendMaterialToSheet: Bool
    let onCancelAppend: () -> Void
    let onConfirmAppend: (PendingMaterialAppendContext) -> Bool
    let onEnsureExistingDraftSelectionForAppend: () -> Void

    @Binding var pendingBatchAddContext: PendingBatchMaterialAppendContext?
    @Binding var pendingBatchAddQuantity: String
    let onCancelBatchAppend: () -> Void
    let onConfirmBatchAppend: (PendingBatchMaterialAppendContext) -> Bool
    let onEnsureExistingDraftSelectionForBatch: () -> Void

    @Binding var showCategoryManager: Bool

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showAddSheet) {
                AddMaterialSheet(
                    initialCategory: initialCategory,
                    suggestedCategories: availableCategories,
                    onSave: onAddMaterial
                )
            }
            .sheet(item: $priceEditorContext) { context in
                MaterialPriceEditSheet(
                    entry: context.entry,
                    suppliers: supplierProfiles,
                    initialName: context.name,
                    initialSpecification: context.specification,
                    initialUnit: context.unit,
                    initialCategory: context.category
                ) { updated in
                    onSavePriceEntry(updated)
                } onDelete: { target in
                    onDeletePriceEntry(target)
                }
            }
            .sheet(item: $pendingAddContext) { context in
                MaterialLibraryAppendToSheetModal(
                    context: context,
                    activeMaterialSheetDrafts: activeMaterialSheetDrafts,
                    projects: projects,
                    draftPickerTitle: draftPickerTitle,
                    quantity: $pendingAddQuantity,
                    unitPrice: $pendingAddUnitPrice,
                    note: $pendingAddNote,
                    targetMode: $pendingAddTargetMode,
                    draftId: $pendingAddDraftID,
                    draftTitle: $pendingAddDraftTitle,
                    projectId: $pendingAddProjectID,
                    focusedField: appendMaterialFocusedField,
                    operationMessage: $operationMessage,
                    canAppendMaterialToSheet: canAppendMaterialToSheet,
                    onCancel: onCancelAppend,
                    onConfirm: {
                        onConfirmAppend(context)
                    },
                    onEnsureExistingDraftSelection: onEnsureExistingDraftSelectionForAppend
                )
            }
            .sheet(item: $pendingBatchAddContext) { context in
                MaterialLibraryBatchAppendSheet(
                    context: context,
                    activeMaterialSheetDrafts: activeMaterialSheetDrafts,
                    projects: projects,
                    draftPickerTitle: draftPickerTitle,
                    quantity: $pendingBatchAddQuantity,
                    targetMode: $pendingAddTargetMode,
                    draftId: $pendingAddDraftID,
                    draftTitle: $pendingAddDraftTitle,
                    projectId: $pendingAddProjectID,
                    operationMessage: $operationMessage,
                    canAppendMaterialToSheet: canAppendMaterialToSheet,
                    onCancel: onCancelBatchAppend,
                    onConfirm: {
                        onConfirmBatchAppend(context)
                    },
                    onEnsureExistingDraftSelection: onEnsureExistingDraftSelectionForBatch
                )
            }
            .sheet(isPresented: $showCategoryManager) {
                NavigationStack {
                    MaterialCategoryManagementView()
                }
            }
    }
}

extension View {
    func materialLibrarySheetPresentations(
        showAddSheet: Binding<Bool>,
        initialCategory: String?,
        availableCategories: [String],
        onAddMaterial: @escaping (UserMaterial, String) -> Void,
        priceEditorContext: Binding<MaterialPriceEditorContext?>,
        supplierProfiles: [SupplierProfile],
        onSavePriceEntry: @escaping (MaterialPriceEntry) -> Void,
        onDeletePriceEntry: @escaping (MaterialPriceEntry) -> Void,
        pendingAddContext: Binding<PendingMaterialAppendContext?>,
        activeMaterialSheetDrafts: [MaterialSheetDraft],
        projects: [Project],
        draftPickerTitle: @escaping (MaterialSheetDraft) -> String,
        pendingAddQuantity: Binding<String>,
        pendingAddUnitPrice: Binding<String>,
        pendingAddNote: Binding<String>,
        pendingAddTargetMode: Binding<MaterialSheetTargetMode>,
        pendingAddDraftID: Binding<UUID?>,
        pendingAddDraftTitle: Binding<String>,
        pendingAddProjectID: Binding<UUID?>,
        appendMaterialFocusedField: FocusState<AppendMaterialField?>.Binding,
        operationMessage: Binding<String?>,
        canAppendMaterialToSheet: Bool,
        onCancelAppend: @escaping () -> Void,
        onConfirmAppend: @escaping (PendingMaterialAppendContext) -> Bool,
        onEnsureExistingDraftSelectionForAppend: @escaping () -> Void,
        pendingBatchAddContext: Binding<PendingBatchMaterialAppendContext?>,
        pendingBatchAddQuantity: Binding<String>,
        onCancelBatchAppend: @escaping () -> Void,
        onConfirmBatchAppend: @escaping (PendingBatchMaterialAppendContext) -> Bool,
        onEnsureExistingDraftSelectionForBatch: @escaping () -> Void,
        showCategoryManager: Binding<Bool>
    ) -> some View {
        modifier(
            MaterialLibrarySheetPresentationsModifier(
                showAddSheet: showAddSheet,
                initialCategory: initialCategory,
                availableCategories: availableCategories,
                onAddMaterial: onAddMaterial,
                priceEditorContext: priceEditorContext,
                supplierProfiles: supplierProfiles,
                onSavePriceEntry: onSavePriceEntry,
                onDeletePriceEntry: onDeletePriceEntry,
                pendingAddContext: pendingAddContext,
                activeMaterialSheetDrafts: activeMaterialSheetDrafts,
                projects: projects,
                draftPickerTitle: draftPickerTitle,
                pendingAddQuantity: pendingAddQuantity,
                pendingAddUnitPrice: pendingAddUnitPrice,
                pendingAddNote: pendingAddNote,
                pendingAddTargetMode: pendingAddTargetMode,
                pendingAddDraftID: pendingAddDraftID,
                pendingAddDraftTitle: pendingAddDraftTitle,
                pendingAddProjectID: pendingAddProjectID,
                appendMaterialFocusedField: appendMaterialFocusedField,
                operationMessage: operationMessage,
                canAppendMaterialToSheet: canAppendMaterialToSheet,
                onCancelAppend: onCancelAppend,
                onConfirmAppend: onConfirmAppend,
                onEnsureExistingDraftSelectionForAppend: onEnsureExistingDraftSelectionForAppend,
                pendingBatchAddContext: pendingBatchAddContext,
                pendingBatchAddQuantity: pendingBatchAddQuantity,
                onCancelBatchAppend: onCancelBatchAppend,
                onConfirmBatchAppend: onConfirmBatchAppend,
                onEnsureExistingDraftSelectionForBatch: onEnsureExistingDraftSelectionForBatch,
                showCategoryManager: showCategoryManager
            )
        )
    }
}
