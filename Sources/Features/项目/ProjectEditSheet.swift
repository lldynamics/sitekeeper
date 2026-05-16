import SwiftUI

struct ProjectEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: Project
    let onSave: (Project) -> Void

    @State private var name: String
    @State private var location: String
    @State private var customerName: String
    @State private var customerPhone: String
    @State private var managerName: String
    @State private var startDate: String
    @State private var expectedEndDate: String
    @State private var contractAmount: String
    @State private var paymentStatus: PaymentStatus
    @State private var requiredDocumentCategories: Set<ProjectDocumentCategory>
    @FocusState private var isInputFocused: Bool

    init(project: Project, onSave: @escaping (Project) -> Void) {
        self.project = project
        self.onSave = onSave
        _name = State(initialValue: project.name)
        _location = State(initialValue: project.location)
        _customerName = State(initialValue: project.customerName)
        _customerPhone = State(initialValue: project.customerPhone)
        _managerName = State(initialValue: project.managerName)
        _startDate = State(initialValue: project.startDate)
        _expectedEndDate = State(initialValue: project.expectedEndDate)
        _contractAmount = State(initialValue: project.contractAmount)
        _paymentStatus = State(initialValue: project.paymentStatus)
        _requiredDocumentCategories = State(initialValue: Set(project.requiredDocumentCategories))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "工程")) {
                    TextField(String(localized: "工程名称"), text: $name)
                        .focused($isInputFocused)
                    TextField(String(localized: "项目地址"), text: $location, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isInputFocused)
                    TextField(String(localized: "负责人"), text: $managerName)
                        .focused($isInputFocused)
                }
                Section(String(localized: "客户")) {
                    TextField(String(localized: "客户姓名/单位"), text: $customerName)
                        .focused($isInputFocused)
                    TextField(String(localized: "客户电话"), text: $customerPhone)
                        .keyboardType(.phonePad)
                        .focused($isInputFocused)
                }
                ProjectDocumentChecklistTemplateSection(selectedCategories: $requiredDocumentCategories)
                Section(String(localized: "工期")) {
                    TextField(String(localized: "开工日期(yyyy-MM-dd)"), text: $startDate)
                        .focused($isInputFocused)
                    TextField(String(localized: "预计完工(yyyy-MM-dd)"), text: $expectedEndDate)
                        .focused($isInputFocused)
                }
                Section(String(localized: "合同")) {
                    TextField(String(localized: "合同金额（元）"), text: $contractAmount.numericInput(.amount))
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)
                    NumericInputValidationHint(
                        validation: InputValidator.validate(
                            contractAmount,
                            kind: .amount,
                            requirement: .optionalNonNegative
                        ),
                        alignment: .leading
                    )
                    Picker(String(localized: "收款状态"), selection: $paymentStatus) {
                        ForEach(PaymentStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "编辑资料"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        isInputFocused = false
                        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        var updated = project
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.location = location
                        updated.customerName = customerName
                        updated.customerPhone = customerPhone
                        updated.managerName = managerName
                        updated.startDate = startDate
                        updated.expectedEndDate = expectedEndDate
                        updated.contractAmount = NumericInputSupport.normalizedStorageText(contractAmount, kind: .amount)
                        updated.paymentStatus = paymentStatus
                        updated.requiredDocumentCategories = ProjectDocumentCategory.normalizedConstructionArchiveRequirements(
                            Array(requiredDocumentCategories)
                        )
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(
                        requiredDocumentCategories.isEmpty ||
                        !InputValidator.validate(contractAmount, kind: .amount, requirement: .optionalNonNegative).isValid
                    )
                }
                KeyboardDismissToolbar {
                    isInputFocused = false
                }
            }
        }
    }
}
