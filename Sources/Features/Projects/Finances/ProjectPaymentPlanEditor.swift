import SwiftUI

struct ProjectPaymentPlanEditor: View {
    let projectID: UUID
    let expected: ProjectPaymentPlan?
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var plan: ProjectPaymentPlan
    @State private var amounts: [UUID: String]
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(projectID: UUID, plan: ProjectPaymentPlan, expected: ProjectPaymentPlan?) {
        self.projectID = projectID
        self.expected = expected
        _plan = State(initialValue: plan)
        _amounts = State(initialValue: Dictionary(uniqueKeysWithValues: plan.installments.map { ($0.id, $0.amount.wireText) }))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(AppLocalization.string("收付计划")) {
                    TextField(AppLocalization.string("计划名称"), text: $plan.title).accessibilityIdentifier("payment.plan.title")
                    Picker(AppLocalization.string("收支"), selection: $plan.direction) {
                        Text(ProjectFinancialDirection.income.displayName).tag(ProjectFinancialDirection.income)
                        Text(ProjectFinancialDirection.expense.displayName).tag(ProjectFinancialDirection.expense)
                    }
                    TextField(AppLocalization.string("往来单位"), text: $plan.counterparty)
                    Toggle(AppLocalization.string("启用到期提醒"), isOn: $plan.remindersEnabled)
                    if expected != nil { Toggle(AppLocalization.string("归档计划"), isOn: $plan.isArchived) }
                }
                ForEach($plan.installments) { $installment in
                    Section {
                        TextField(AppLocalization.string("期次名称"), text: $installment.title)
                        TextField(AppLocalization.string("金额"), text: Binding(
                            get: { amounts[installment.id] ?? "" }, set: { amounts[installment.id] = $0 }
                        )).keyboardType(.decimalPad)
                        OptionalProjectDatePicker(AppLocalization.string("到期日期"), value: $installment.dueDate)
                        Toggle(AppLocalization.string("质保金"), isOn: $installment.isRetention)
                        if !store.projectFinancialRecords.contains(where: { $0.paymentAllocation?.installmentID == installment.id }) {
                            Button(AppLocalization.string("删除期次"), role: .destructive) {
                                plan.installments.removeAll { $0.id == installment.id }
                            }
                        }
                    }
                }
                Section {
                    Button(AppLocalization.string("添加期次"), systemImage: "plus") {
                        plan.installments.append(ProjectPaymentInstallment(title: "", dueDate: .today(), amount: .empty))
                    }.disabled(plan.installments.count >= 120)
                    Text(AppLocalization.string("已有关联收付的期次不能删除；归档计划保留全部历史记录。"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(Color.appRisk) } }
            }
            .navigationTitle(AppLocalization.string("收付计划"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.string("取消")) { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("保存")) { Task { await save() } }.disabled(isSaving)
                        .accessibilityIdentifier("payment.plan.save")
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var value = plan
        for index in value.installments.indices {
            value.installments[index].amount = MoneyValue(storage: DecimalFieldStorage(text: amounts[value.installments[index].id] ?? ""))
        }
        do {
            try await ProjectPaymentService.savePlan(value, projectID: projectID, expected: expected, store: store)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
