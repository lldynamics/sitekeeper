import Foundation

struct PaymentInstallmentSummary: Identifiable {
    var id: UUID { installment.id }
    let installment: ProjectPaymentInstallment
    let paid: MoneyValue
    let remaining: MoneyValue
    let overpaid: MoneyValue
    let isValid: Bool
}

struct PaymentPlanSummary: Identifiable {
    var id: UUID { plan.id }
    let plan: ProjectPaymentPlan
    let installments: [PaymentInstallmentSummary]
    let total: MoneyValue
    let paid: MoneyValue
    let remaining: MoneyValue
    let overpaid: MoneyValue
    let isValid: Bool

    var nextDue: PaymentInstallmentSummary? {
        installments.filter { $0.isValid && $0.remaining.isPositive }
            .min { $0.installment.dueDate < $1.installment.dueDate }
    }
}

enum ProjectPaymentMetrics {
    static func summaries(project: Project, records: [ProjectFinancialRecord]) -> [PaymentPlanSummary] {
        let allocated = Dictionary(grouping: records.filter { $0.projectId == project.id && $0.paymentAllocation != nil }) {
            $0.paymentAllocation!.installmentID
        }
        return project.paymentPlans.map { plan in
            let installments = plan.installments.map { installment in
                let payments = (allocated[installment.id] ?? []).filter { $0.paymentAllocation?.planID == plan.id && $0.countsInBusinessMetrics }
                let valid = installment.amount.isPositive && installment.dueDate.calendarDay() != nil
                    && !installment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && Set(payments.map(\.id)).count == payments.count
                    && payments.allSatisfy { $0.amount.isPositive && $0.direction == plan.direction && $0.category != .refund }
                let paid = valid ? payments.reduce(MoneyValue.zero) { $0 + $1.amount } : .empty
                let remaining = valid ? positiveDifference(installment.amount, paid) : .empty
                let overpaid = valid ? positiveDifference(paid, installment.amount) : .empty
                return PaymentInstallmentSummary(installment: installment, paid: paid, remaining: remaining, overpaid: overpaid,
                    isValid: valid && paid.isValid && remaining.isValid && overpaid.isValid)
            }
            let total = installments.reduce(MoneyValue.zero) { $0 + $1.installment.amount }
            let paid = installments.reduce(MoneyValue.zero) { $0 + $1.paid }
            let remaining = installments.reduce(MoneyValue.zero) { $0 + $1.remaining }
            let overpaid = installments.reduce(MoneyValue.zero) { $0 + $1.overpaid }
            return PaymentPlanSummary(plan: plan, installments: installments, total: total, paid: paid, remaining: remaining, overpaid: overpaid,
                isValid: !installments.isEmpty && installments.allSatisfy(\.isValid) && [total, paid, remaining, overpaid].allSatisfy(\.isValid))
        }
    }

    static func validate(_ plan: ProjectPaymentPlan, in project: Project, records: [ProjectFinancialRecord]) throws {
        guard !plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !plan.installments.isEmpty,
              plan.installments.count <= 120,
              Set(plan.installments.map(\.id)).count == plan.installments.count,
              plan.installments.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.amount.isPositive && $0.dueDate.calendarDay() != nil }),
              plan.installments.reduce(MoneyValue.zero, { $0 + $1.amount }).isValid else { throw BusinessWorkflowError.invalidInput }
        let otherIDs = Set(project.paymentPlans.filter { $0.id != plan.id }.flatMap { $0.installments.map(\.id) })
        guard !plan.installments.contains(where: { otherIDs.contains($0.id) }) else { throw BusinessWorkflowError.invalidInput }
        if let previous = project.paymentPlans.first(where: { $0.id == plan.id }) {
            let linked = records.filter { $0.projectId == project.id && $0.paymentAllocation?.planID == plan.id }
            let newIDs = Set(plan.installments.map(\.id))
            guard linked.isEmpty || (previous.direction == plan.direction && linked.allSatisfy { newIDs.contains($0.paymentAllocation!.installmentID) }) else {
                throw BusinessWorkflowError.invalidAllocation
            }
            var proposed = project
            proposed.paymentPlans = [plan]
            guard summaries(project: proposed, records: records).allSatisfy({ $0.isValid && !$0.overpaid.isPositive }) else { throw BusinessWorkflowError.invalidAllocation }
        }
    }

    static func validateAllocation(_ record: ProjectFinancialRecord, projects: [Project], records: [ProjectFinancialRecord]) throws {
        guard let allocation = record.paymentAllocation else { return }
        guard let project = projects.first(where: { $0.id == record.projectId }),
              let plan = project.paymentPlans.first(where: { $0.id == allocation.planID }),
              let installment = plan.installments.first(where: { $0.id == allocation.installmentID }),
              record.direction == plan.direction, record.category != .refund, record.amount.isPositive else { throw BusinessWorkflowError.invalidAllocation }
        // Draft/archived records retain provenance, but do not settle a plan.
        guard record.countsInBusinessMetrics else { return }
        if plan.isArchived {
            // Historical invoice/note corrections may reduce an existing payment;
            // archiving must never permit a new or larger payment.
            guard let original = records.first(where: { $0.id == record.id }), original.countsInBusinessMetrics,
                  original.paymentAllocation == record.paymentAllocation, original.direction == record.direction,
                  record.amount <= original.amount else { throw BusinessWorkflowError.invalidAllocation }
        }
        var scope = project
        scope.paymentPlans = [plan]
        let withoutCurrent = records.filter { $0.id != record.id }
        guard let planSummary = summaries(project: scope, records: withoutCurrent).first,
              planSummary.isValid, !planSummary.overpaid.isPositive,
              let summary = planSummary.installments.first(where: { $0.id == installment.id }), summary.isValid else {
            throw BusinessWorkflowError.invalidAllocation
        }
        guard summary.remaining.isPositive else { throw BusinessWorkflowError.settledInstallment }
        guard record.amount <= summary.remaining else { throw BusinessWorkflowError.invalidAllocation }
    }

    private static func positiveDifference(_ lhs: MoneyValue, _ rhs: MoneyValue) -> MoneyValue {
        let result = lhs - rhs
        guard let value = result.optionalDecimal else { return .empty }
        return MoneyValue(max(.zero, value))
    }
}
