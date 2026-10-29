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

    private var hasDuplicateIdentities: Bool {
        guard let project = store.projects.first(where: { $0.id == projectID }) else { return false }
        let planIDs = project.paymentPlans.map(\.id)
        let installmentIDs = project.paymentPlans.flatMap { $0.installments.map(\.id) }
        return Set(planIDs).count != planIDs.count || Set(installmentIDs).count != installmentIDs.count
    }

    var body: some View {
        List {
            if let project = store.projects.first(where: { $0.id == projectID }) {
                receivableSection(project)
            }
            Section {
                Text(AppLocalization.string("计划金额不计入经营汇总，只有登记的正式收付才会计入。"))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(AppLocalization.string("新增收付计划"), systemImage: "plus.circle") {
                    editingPlan = PlanSelection(plan: ProjectPaymentPlan(title: "", direction: .income, counterparty: "", installments: []), expected: nil)
                }.accessibilityIdentifier("payment.plan.add")
            }
            ForEach(presentationRows(summaries, identity: { $0.id })) { row in
                let summary = row.value
                Section {
                    Button { editingPlan = PlanSelection(plan: summary.plan, expected: summary.plan) } label: {
                        Label(summary.plan.title, systemImage: summary.plan.isArchived ? "archivebox" : "pencil")
                    }
                    .disabled(hasDuplicateIdentities)
                    LabeledContent(summary.plan.direction.displayName, value: planValue(summary.total, valid: summary.isValid && !hasDuplicateIdentities))
                    LabeledContent(AppLocalization.string("已收付"), value: planValue(summary.paid, valid: summary.isValid && !hasDuplicateIdentities))
                    LabeledContent(AppLocalization.string("未结金额"), value: planValue(summary.remaining, valid: summary.isValid && !hasDuplicateIdentities))
                    if !summary.isValid || summary.overpaid.isPositive || hasDuplicateIdentities {
                        Text(AppLocalization.string("金额或关联记录异常，请核对账目后再登记收付。"))
                            .foregroundStyle(Color.appRisk)
                    }
                    ForEach(presentationRows(summary.installments, identity: { $0.id })) { row in
                        let installment = row.value
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(installment.installment.title).font(.headline)
                                if installment.installment.isRetention { Text(AppLocalization.string("质保金")).font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(installment.installment.dueDate.storageText).font(.caption).foregroundStyle(.secondary)
                            LabeledContent(AppLocalization.string("已收付"), value: planValue(installment.paid, valid: installment.isValid && !hasDuplicateIdentities))
                            LabeledContent(AppLocalization.string("未结金额"), value: planValue(installment.remaining, valid: installment.isValid && !hasDuplicateIdentities))
                            if installment.remaining.isPositive, summary.isValid, !summary.overpaid.isPositive,
                               !summary.plan.isArchived, !hasDuplicateIdentities {
                                Button(AppLocalization.string("登记实际收付")) {
                                    payment = PaymentSelection(plan: summary.plan, installment: installment)
                                }
                                .accessibilityIdentifier("payment.installment.pay.\(installment.id)")
                            } else if installment.isValid, installment.remaining.isZero, !hasDuplicateIdentities {
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

    private func receivableSection(_ project: Project) -> some View {
        let records = store.projectStore.projectFinancialRecords(for: projectID)
        let context = store.projectStore.dayContext
        let schedule = ProjectReceivableScheduleSummary(project: project, records: records,
                                                        today: context.day, timeZone: context.calendar.timeZone)
        let paid = ProjectFinancialMetrics.paidAmount(project: project, records: records)
        let unpaid = project.contractAmount.isValid && paid.isValid
            ? ProjectFinancialMetrics.unpaidAmount(contractAmount: project.contractAmount, paidAmount: paid) : nil
        return Section(AppLocalization.string("business_scope_receivable_plans")) {
            LabeledContent(AppLocalization.string("business_scope_contract_unpaid"), value: optionalMoney(unpaid))
            switch schedule.state {
            case .ready:
                LabeledContent(AppLocalization.string("business_scope_due_plan"), value: optionalMoney(schedule.dueUnpaidAmount))
                LabeledContent(AppLocalization.string("business_scope_due_today"), value: optionalMoney(schedule.dueTodayUnpaidAmount))
                LabeledContent(AppLocalization.string("business_scope_overdue"), value: optionalMoney(schedule.overdueUnpaidAmount))
                LabeledContent(AppLocalization.string("business_scope_future_plan"), value: optionalMoney(schedule.futureUnpaidAmount))
                LabeledContent(AppLocalization.string("business_scope_retention"), value: optionalMoney(schedule.retentionUnpaidAmount))
            case .noActiveIncomePlan:
                Text(AppLocalization.string("business_scope_no_plan"))
            case .needsReview:
                Label(AppLocalization.string("business_scope_plan_review"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.appWarning)
                ForEach(reviewReasons(schedule), id: \.self) { reason in
                    Text(reviewReasonText(reason)).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Text(AppLocalization.string("business_scope_plan_note"))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("payment.receivable-summary")
    }

    private func reviewReasons(_ summary: ProjectReceivableScheduleSummary) -> [ProjectReceivableScheduleSummary.ReviewReason] {
        let order: [ProjectReceivableScheduleSummary.ReviewReason] = [
            .multipleActiveIncomePlans, .duplicateIdentity, .invalidPlan, .overpaidPlan,
            .invalidAllocation, .invalidCollectionAmount, .unallocatedCollections, .historicalManualPaid
        ]
        return order.filter { summary.reviewReasons.contains($0) }
    }

    private func reviewReasonText(_ reason: ProjectReceivableScheduleSummary.ReviewReason) -> String {
        switch reason {
        case .multipleActiveIncomePlans: return AppLocalization.string("business_scope_review_multiple")
        case .duplicateIdentity: return AppLocalization.string("business_scope_review_duplicate")
        case .invalidPlan: return AppLocalization.string("business_scope_review_invalid_plan")
        case .overpaidPlan: return AppLocalization.string("business_scope_review_overpaid")
        case .invalidAllocation: return AppLocalization.string("business_scope_review_allocation")
        case .invalidCollectionAmount: return AppLocalization.string("business_scope_review_collection")
        case .unallocatedCollections: return AppLocalization.string("business_scope_review_unallocated")
        case .historicalManualPaid: return AppLocalization.string("business_scope_review_manual")
        }
    }

    private func optionalMoney(_ value: MoneyValue?) -> String {
        value.map(ReportBuilder.money) ?? AppLocalization.string("cost_basis_unknown")
    }

    private func planValue(_ value: MoneyValue, valid: Bool) -> String {
        valid && value.isValid ? ReportBuilder.money(value) : AppLocalization.string("cost_basis_unknown")
    }

    /// A restored corrupt snapshot can contain duplicate IDs. Occurrence is
    /// scoped to each semantic ID, and editing remains disabled until reviewed.
    private func presentationRows<Value>(_ values: [Value], identity: (Value) -> UUID) -> [PresentationRow<Value>] {
        var occurrences: [UUID: Int] = [:]
        return values.map { value in
            let base = identity(value)
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            return PresentationRow(id: "\(base.uuidString)-\(occurrence)", value: value)
        }
    }

    private struct PresentationRow<Value>: Identifiable {
        let id: String
        let value: Value
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
