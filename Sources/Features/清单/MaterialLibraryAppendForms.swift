import SwiftUI

struct MaterialLibraryAppendToSheetForm: View {
    let context: PendingMaterialAppendContext
    let activeMaterialSheetDrafts: [MaterialSheetDraft]
    let projects: [Project]
    let draftPickerTitle: (MaterialSheetDraft) -> String
    @Binding var quantity: String
    @Binding var unitPrice: String
    @Binding var note: String
    @Binding var targetMode: MaterialSheetTargetMode
    @Binding var draftId: UUID?
    @Binding var draftTitle: String
    @Binding var projectId: UUID?
    @FocusState private var focusedField: AppendMaterialField?

    var body: some View {
        Form {
            Section(String(localized: "材料")) {
                LabeledContent(String(localized: "名称"), value: context.name)
                if !context.specification.isEmpty {
                    LabeledContent(String(localized: "规格"), value: context.specification)
                }
                LabeledContent(String(localized: "单位"), value: context.unit)
            }
            Section(String(localized: "添加参数")) {
                HStack {
                    TextField(String(localized: "数量"), text: $quantity)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .quantity)
                        .accessibilityIdentifier("material-library-append-quantity")
                    Text(context.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                NumericInputValidationHint(
                    validation: MaterialLibraryLogicHelpers.appendQuantityValidation(quantity),
                    showWhenEmpty: true,
                    alignment: .leading
                )
                HStack {
                    TextField(String(localized: "单价（可选）"), text: $unitPrice)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .unitPrice)
                    Text(String(format: String(localized: "元/%@"), context.unit))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField(String(localized: "备注（可选）"), text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .note)
            }
            Section(String(localized: "保存到材料单")) {
                if targetMode == .existing {
                    if activeMaterialSheetDrafts.isEmpty {
                        Text(String(localized: "暂无可用材料单，请新建一个材料单。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            targetMode = .create
                            projectId = nil
                        } label: {
                            Label(String(localized: "新建材料单"), systemImage: "plus.circle.fill")
                        }
                    } else {
                        LabeledContent(String(localized: "当前目标")) {
                            Text(selectedDraftTitle)
                                .multilineTextAlignment(.trailing)
                        }
                        Menu {
                            ForEach(activeMaterialSheetDrafts) { draft in
                                Button {
                                    targetMode = .existing
                                    draftId = draft.id
                                } label: {
                                    Label(
                                        draftPickerTitle(draft),
                                        systemImage: draft.id == draftId ? "checkmark.circle.fill" : "tray"
                                    )
                                }
                            }
                            Divider()
                            Button {
                                targetMode = .create
                                projectId = nil
                            } label: {
                                Label(String(localized: "新建材料单"), systemImage: "plus.circle.fill")
                            }
                        } label: {
                            Label(String(localized: "切换目标"), systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } else {
                    TextField(String(localized: "材料单名称"), text: $draftTitle)
                    Picker(String(localized: "归属项目"), selection: $projectId) {
                        Text(String(localized: "无归属")).tag(nil as UUID?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                    if !activeMaterialSheetDrafts.isEmpty {
                        Button {
                            targetMode = .existing
                            draftId = draftId ?? activeMaterialSheetDrafts.first?.id
                        } label: {
                            Label(String(localized: "改用已有材料单"), systemImage: "tray.full.fill")
                        }
                    }
                }
            }
        }
        .appKeyboardToolbar {
            KeyboardNavigationToolbar(
                focusedField: $focusedField,
                currentField: focusedField,
                fields: [.quantity, .unitPrice, .note]
            )
        }
    }

    private var selectedDraftTitle: String {
        guard let draftId,
              let draft = activeMaterialSheetDrafts.first(where: { $0.id == draftId }) else {
            return String(localized: "未选择材料单")
        }
        return draftPickerTitle(draft)
    }
}

struct MaterialLibraryAppendToSheetModal: View {
    let context: PendingMaterialAppendContext
    let activeMaterialSheetDrafts: [MaterialSheetDraft]
    let projects: [Project]
    let draftPickerTitle: (MaterialSheetDraft) -> String
    @Binding var quantity: String
    @Binding var unitPrice: String
    @Binding var note: String
    @Binding var targetMode: MaterialSheetTargetMode
    @Binding var draftId: UUID?
    @Binding var draftTitle: String
    @Binding var projectId: UUID?
    @Binding var operationMessage: String?
    let canAppendMaterialToSheet: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Bool
    let onEnsureExistingDraftSelection: () -> Void

    var body: some View {
        AppBusinessEditForm(
            title: String(localized: "materials.library.appendSheet.title"),
            cancelTitle: String(localized: "common.cancel"),
            primaryActionTitle: String(localized: "common.add"),
            isPrimaryActionDisabled: !canAppendMaterialToSheet || !MaterialLibraryLogicHelpers.appendQuantityValidation(quantity).isValid,
            onCancel: onCancel,
            onPrimaryAction: {
                guard onConfirm() else { return }
                onCancel()
            }
        ) {
            MaterialLibraryAppendToSheetForm(
                context: context,
                activeMaterialSheetDrafts: activeMaterialSheetDrafts,
                projects: projects,
                draftPickerTitle: draftPickerTitle,
                quantity: $quantity,
                unitPrice: $unitPrice,
                note: $note,
                targetMode: $targetMode,
                draftId: $draftId,
                draftTitle: $draftTitle,
                projectId: $projectId
            )
        }
        .onChange(of: targetMode) { _, mode in
            guard mode == .existing else { return }
            onEnsureExistingDraftSelection()
        }
        .operationToast(message: $operationMessage)
    }
}

struct MaterialLibraryBatchAppendForm: View {
    let context: PendingBatchMaterialAppendContext
    let activeMaterialSheetDrafts: [MaterialSheetDraft]
    let projects: [Project]
    let draftPickerTitle: (MaterialSheetDraft) -> String
    @Binding var quantity: String
    @Binding var targetMode: MaterialSheetTargetMode
    @Binding var draftId: UUID?
    @Binding var draftTitle: String
    @Binding var projectId: UUID?

    var body: some View {
        Form {
            Section(String(format: String(localized: "已选材料 (%d)"), context.materials.count)) {
                ForEach(context.materials.prefix(5)) { item in
                    Text(item.displayName)
                }
                if context.materials.count > 5 {
                    Text(String(format: String(localized: "其余 %d 项将在保存后一并加入"), context.materials.count - 5))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "添加参数")) {
                HStack {
                    TextField(String(localized: "数量"), text: $quantity)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("material-library-batch-quantity")
                    Text(String(localized: "每项"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                NumericInputValidationHint(
                    validation: MaterialLibraryLogicHelpers.appendQuantityValidation(quantity),
                    showWhenEmpty: true,
                    alignment: .leading
                )
            }

            Section(String(localized: "保存到材料单")) {
                if targetMode == .existing {
                    if activeMaterialSheetDrafts.isEmpty {
                        Text(String(localized: "暂无可用材料单，请新建一个材料单。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            targetMode = .create
                            projectId = nil
                        } label: {
                            Label(String(localized: "新建材料单"), systemImage: "plus.circle.fill")
                        }
                    } else {
                        LabeledContent(String(localized: "当前目标")) {
                            Text(selectedDraftTitle)
                                .multilineTextAlignment(.trailing)
                        }
                        Menu {
                            ForEach(activeMaterialSheetDrafts) { draft in
                                Button {
                                    targetMode = .existing
                                    draftId = draft.id
                                } label: {
                                    Label(
                                        draftPickerTitle(draft),
                                        systemImage: draft.id == draftId ? "checkmark.circle.fill" : "tray"
                                    )
                                }
                            }
                            Divider()
                            Button {
                                targetMode = .create
                                projectId = nil
                            } label: {
                                Label(String(localized: "新建材料单"), systemImage: "plus.circle.fill")
                            }
                        } label: {
                            Label(String(localized: "切换目标"), systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } else {
                    TextField(String(localized: "材料单名称"), text: $draftTitle)
                    Picker(String(localized: "归属项目"), selection: $projectId) {
                        Text(String(localized: "无归属")).tag(nil as UUID?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                    if !activeMaterialSheetDrafts.isEmpty {
                        Button {
                            targetMode = .existing
                            draftId = draftId ?? activeMaterialSheetDrafts.first?.id
                        } label: {
                            Label(String(localized: "改用已有材料单"), systemImage: "tray.full.fill")
                        }
                    }
                }
            }
        }
    }

    private var selectedDraftTitle: String {
        guard let draftId,
              let draft = activeMaterialSheetDrafts.first(where: { $0.id == draftId }) else {
            return String(localized: "未选择材料单")
        }
        return draftPickerTitle(draft)
    }
}

struct MaterialLibraryBatchAppendSheet: View {
    let context: PendingBatchMaterialAppendContext
    let activeMaterialSheetDrafts: [MaterialSheetDraft]
    let projects: [Project]
    let draftPickerTitle: (MaterialSheetDraft) -> String
    @Binding var quantity: String
    @Binding var targetMode: MaterialSheetTargetMode
    @Binding var draftId: UUID?
    @Binding var draftTitle: String
    @Binding var projectId: UUID?
    @Binding var operationMessage: String?
    let canAppendMaterialToSheet: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Bool
    let onEnsureExistingDraftSelection: () -> Void

    var body: some View {
        AppBusinessEditForm(
            title: String(localized: "materials.library.batchAppendSheet.title"),
            cancelTitle: String(localized: "common.cancel"),
            primaryActionTitle: String(localized: "common.add"),
            isPrimaryActionDisabled: !canAppendMaterialToSheet || !MaterialLibraryLogicHelpers.appendQuantityValidation(quantity).isValid,
            onCancel: onCancel,
            onPrimaryAction: {
                guard onConfirm() else { return }
                onCancel()
            }
        ) {
            MaterialLibraryBatchAppendForm(
                context: context,
                activeMaterialSheetDrafts: activeMaterialSheetDrafts,
                projects: projects,
                draftPickerTitle: draftPickerTitle,
                quantity: $quantity,
                targetMode: $targetMode,
                draftId: $draftId,
                draftTitle: $draftTitle,
                projectId: $projectId
            )
            .appKeyboardToolbar {
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
                }
            }
        }
        .onChange(of: targetMode) { _, mode in
            guard mode == .existing else { return }
            onEnsureExistingDraftSelection()
        }
        .operationToast(message: $operationMessage)
    }
}
