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
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("工程") {
                    TextField("工程名称", text: $name)
                        .focused($isInputFocused)
                    TextField("项目地址", text: $location, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isInputFocused)
                    TextField("负责人", text: $managerName)
                        .focused($isInputFocused)
                }
                Section("客户") {
                    TextField("客户姓名/单位", text: $customerName)
                        .focused($isInputFocused)
                    TextField("客户电话", text: $customerPhone)
                        .keyboardType(.phonePad)
                        .focused($isInputFocused)
                }
                Section("工期") {
                    TextField("开工日期(yyyy-MM-dd)", text: $startDate)
                        .focused($isInputFocused)
                    TextField("预计完工(yyyy-MM-dd)", text: $expectedEndDate)
                        .focused($isInputFocused)
                }
                Section("合同") {
                    TextField("合同金额（元）", text: $contractAmount)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)
                    Picker("收款状态", selection: $paymentStatus) {
                        ForEach(PaymentStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
                        }
                    }
                }
            }
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
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
                        updated.contractAmount = contractAmount
                        updated.paymentStatus = paymentStatus
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(!contractAmount.isEmpty && !InputValidator.nonNegativeNumber(contractAmount))
                }
                KeyboardDismissToolbar {
                    isInputFocused = false
                }
            }
        }
    }
}
