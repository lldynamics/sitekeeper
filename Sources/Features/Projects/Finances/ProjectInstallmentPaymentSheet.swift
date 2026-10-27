import SwiftUI

struct ProjectInstallmentPaymentSheet: View {
    let projectID: UUID
    let plan: ProjectPaymentPlan
    let installment: PaymentInstallmentSummary
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var recordID = UUID()
    @State private var amount = ""
    @State private var date = Date()
    @State private var invoiceNumber = ""
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(installment.installment.title) {
                    LabeledContent(AppLocalization.string("未结金额"), value: ReportBuilder.money(installment.remaining))
                    TextField(AppLocalization.string("本次金额"), text: $amount).keyboardType(.decimalPad)
                        .accessibilityIdentifier("payment.actual.amount")
                    DatePicker(AppLocalization.string("实际收付日期"), selection: $date, displayedComponents: .date)
                    TextField(AppLocalization.string("票据编号"), text: $invoiceNumber)
                    TextField(AppLocalization.string("备注"), text: $note, axis: .vertical)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(Color.appRisk) } }
            }
            .navigationTitle(AppLocalization.string("登记实际收付"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.string("取消")) { dismiss() }.disabled(isSaving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("保存")) { Task { await save() } }.disabled(isSaving)
                        .accessibilityIdentifier("payment.actual.save")
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear { if amount.isEmpty { amount = installment.remaining.wireText } }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let record = ProjectFinancialRecord(id: recordID, projectId: projectID, date: .instant(date), direction: plan.direction,
            category: plan.direction == .income ? .collection : .receipt, amount: MoneyValue(storage: DecimalFieldStorage(text: amount)),
            counterparty: plan.counterparty, invoiceNumber: invoiceNumber, status: .active, note: note,
            paymentAllocation: ProjectPaymentAllocation(planID: plan.id, installmentID: installment.id))
        do {
            try await ProjectPaymentService.recordPayment(record, store: store)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
