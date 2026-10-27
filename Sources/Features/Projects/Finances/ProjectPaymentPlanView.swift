import SwiftUI

struct ProjectPaymentPlanView: View {
    let projectID: UUID
    @Environment(DataStore.self) private var store
    @State private var editingPlan: PlanSelection?
    @State private var payment: PaymentSelection?

    private var summaries: [PaymentPlanSummary] {
        guard let project = store.projects.first(where: { $0.id == projectID }) else { return [] }
        return ProjectPaymentMetrics.summaries(project: project, records: store.projectStore.projectFinancialRecords(for: projectID))
    }

    var body: some View {
        List {
            Section {
                Text(AppLocalization.string("计划金额不计入经营汇总，只有登记的正式收付才会计入。"))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(AppLocalization.string("新增收付计划"), systemImage: "plus.circle") {
                    editingPlan = PlanSelection(plan: ProjectPaymentPlan(title: "", direction: .income, counterparty: "", installments: []), expected: nil)
                }.accessibilityIdentifier("payment.plan.add")
            }
            ForEach(summaries) { summary in
                Section {
                    Button { editingPlan = PlanSelection(plan: summary.plan, expected: summary.plan) } label: {
                        Label(summary.plan.title, systemImage: summary.plan.isArchived ? "archivebox" : "pencil")
                    }
                    LabeledContent(summary.plan.direction.displayName, value: ReportBuilder.money(summary.total))
                    LabeledContent(AppLocalization.string("已收付"), value: ReportBuilder.money(summary.paid))
                    LabeledContent(AppLocalization.string("未结金额"), value: ReportBuilder.money(summary.remaining))
                    if !summary.isValid || summary.overpaid.isPositive {
                        Text(AppLocalization.string("金额或关联记录异常，请核对账目后再登记收付。"))
                            .foregroundStyle(Color.appRisk)
                    }
                    ForEach(summary.installments) { installment in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(installment.installment.title).font(.headline)
                                if installment.installment.isRetention { Text(AppLocalization.string("质保金")).font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(installment.installment.dueDate.storageText).font(.caption).foregroundStyle(.secondary)
                            LabeledContent(AppLocalization.string("已收付"), value: ReportBuilder.money(installment.paid))
                            LabeledContent(AppLocalization.string("未结金额"), value: ReportBuilder.money(installment.remaining))
                            if installment.remaining.isPositive, summary.isValid, !summary.overpaid.isPositive, !summary.plan.isArchived {
                                Button(AppLocalization.string("登记实际收付")) {
                                    payment = PaymentSelection(plan: summary.plan, installment: installment)
                                }
                                .accessibilityIdentifier("payment.installment.pay.\(installment.id)")
                            } else if installment.isValid, installment.remaining.isZero {
                                Label(AppLocalization.string("已结清"), systemImage: "checkmark.circle")
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(AppLocalization.string("分期收付款"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingPlan) { selection in
            ProjectPaymentPlanEditor(projectID: projectID, plan: selection.plan, expected: selection.expected)
        }
        .sheet(item: $payment) { selection in
            ProjectInstallmentPaymentSheet(projectID: projectID, plan: selection.plan, installment: selection.installment)
        }
    }

    private struct PaymentSelection: Identifiable {
        var id: UUID { installment.id }
        let plan: ProjectPaymentPlan
        let installment: PaymentInstallmentSummary
    }

    private struct PlanSelection: Identifiable {
        var id: UUID { plan.id }
        let plan: ProjectPaymentPlan
        let expected: ProjectPaymentPlan?
    }
}
