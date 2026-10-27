import SwiftUI

struct ProjectEditSheet: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable var draft: ProjectEditDraft
    @FocusState private var focusedField: ProjectEditDraft.Field?
    let onSave: (Project) -> Void

    private var savedDocumentChecklistTemplates: [ProjectDocumentChecklistTemplate] {
        ProjectDocumentChecklistTemplate.customTemplates(from: store.templates)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.string("工程")) {
                    TextField(AppLocalization.string("工程名称"), text: $draft.name)
                        .focused($focusedField, equals: .name)
                    TextField(AppLocalization.string("项目地址"), text: $draft.location, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .location)
                    TextField(AppLocalization.string("负责人"), text: $draft.managerName)
                        .focused($focusedField, equals: .managerName)
                }
                Section(AppLocalization.string("客户")) {
                    TextField(AppLocalization.string("客户姓名/单位"), text: $draft.customerName)
                        .focused($focusedField, equals: .customerName)
                    TextField(AppLocalization.string("客户电话"), text: $draft.customerPhone)
                        .keyboardType(.phonePad)
                        .focused($focusedField, equals: .customerPhone)
                }
                ProjectDocumentChecklistTemplateSection(
                    selectedCategories: $draft.requiredDocumentCategories,
                    recommendationStage: $draft.recommendationStage,
                    customTemplates: savedDocumentChecklistTemplates
                )
                Section(AppLocalization.string("工期")) {
                    OptionalProjectDatePicker(AppLocalization.string("开工日期"), value: $draft.startDate)
                    OptionalProjectDatePicker(AppLocalization.string("预计完工"), value: $draft.expectedEndDate)
                }
                Section(AppLocalization.string("合同")) {
                    TextField(AppLocalization.string("合同金额（元）"), text: $draft.contractAmount.numericInput(.amount))
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .contractAmount)
                    NumericInputValidationHint(
                        validation: InputValidator.validate(
                            draft.contractAmount,
                            kind: .amount,
                            requirement: .optionalNonNegative
                        ),
                        alignment: .leading
                    )
                    Picker(AppLocalization.string("收款状态"), selection: $draft.paymentStatus) {
                        ForEach(PaymentStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                }
            }
            .navigationTitle(AppLocalization.string("编辑资料"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("保存")) {
                        focusedField = nil
                        draft.focusedField = nil
                        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        guard let current = store.projects.first(where: { $0.id == draft.original.id }) else { return }
                        onSave(draft.updatedProject(basedOn: current))
                        dismiss()
                    }
                    .disabled(
                        draft.requiredDocumentCategories.isEmpty ||
                        !InputValidator.validate(draft.contractAmount, kind: .amount, requirement: .optionalNonNegative).isValid
                    )
                }
            }
            .appKeyboardToolbar {
                KeyboardDismissToolbar {
                    focusedField = nil
                    draft.focusedField = nil
                    AppKeyboard.dismiss()
                }
            }
        }
        .onAppear { focusedField = draft.focusedField }
        .onChange(of: focusedField) { _, field in draft.focusedField = field }
    }
}
