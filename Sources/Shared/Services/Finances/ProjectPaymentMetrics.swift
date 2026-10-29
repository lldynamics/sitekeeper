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

/// An independent view of one receivable schedule, never a partition of contract
/// unpaid. Ambiguous receipts stay unassigned instead of being spread over dates.
struct ProjectReceivableScheduleSummary {
    enum State: Equatable { case noActiveIncomePlan, ready, needsReview }
    enum ReviewReason: Hashable {
        case multipleActiveIncomePlans, duplicateIdentity, invalidPlan, overpaidPlan
        case invalidAllocation, invalidCollectionAmount, unallocatedCollections, historicalManualPaid
    }

    let state: State
    let reviewReasons: Set<ReviewReason>
    let planID: UUID?
    /// Includes today; overdue and today below are disjoint subsets.
    let dueUnpaidAmount: MoneyValue?
    let futureUnpaidAmount: MoneyValue?
    let overdueUnpaidAmount: MoneyValue?
    let dueTodayUnpaidAmount: MoneyValue?
    /// A subset of due plus future, not another amount to add to that total.
    let retentionUnpaidAmount: MoneyValue?
    let oldestOverdueDays: Int?

    init(project: Project, records: [ProjectFinancialRecord], today: CalendarDay, timeZone: TimeZone) {
        let activePlans = project.paymentPlans.filter { $0.direction == .income && !$0.isArchived }
        let plansByID = Dictionary(grouping: project.paymentPlans, by: \.id)
        let installmentIDs = project.paymentPlans.flatMap { $0.installments.map(\.id) }
        let activeRecords = records.filter { $0.projectId == project.id && $0.countsInBusinessMetrics }
        var reasons: Set<ReviewReason> = []
        if activePlans.count > 1 { reasons.insert(.multipleActiveIncomePlans) }
        if plansByID.values.contains(where: { $0.count > 1 }) || Set(installmentIDs).count != installmentIDs.count {
            reasons.insert(.duplicateIdentity)
        }
        let relevantRecords = activeRecords.filter { $0.paymentAllocation != nil || $0.isCollectionIncome }
        if Set(relevantRecords.map(\.id)).count != relevantRecords.count { reasons.insert(.duplicateIdentity) }

        var allocatedCollections: [ProjectFinancialRecord] = []
        for record in activeRecords {
            guard let allocation = record.paymentAllocation else {
                if !activePlans.isEmpty, record.isCollectionIncome, record.amount.isPositive {
                    reasons.insert(.unallocatedCollections)
                }
                continue
            }
            guard let matches = plansByID[allocation.planID], matches.count == 1,
                  let plan = matches.first,
                  plan.installments.filter({ $0.id == allocation.installmentID }).count == 1 else {
                reasons.insert(.invalidAllocation)
                continue
            }
            // A collection linked to a historical or payable plan is not
            // allocated to this active income plan. Never silently apply it.
            guard !plan.isArchived, plan.direction == .income else {
                if !activePlans.isEmpty, record.isCollectionIncome { reasons.insert(.unallocatedCollections) }
                continue
            }
            guard record.isCollectionIncome, record.amount.isPositive else {
                reasons.insert(.invalidAllocation)
                continue
            }
            allocatedCollections.append(record)
        }
        if !activePlans.isEmpty {
            let collections = activeRecords.filter(\.isCollectionIncome)
            let recorded = ProjectFinancialMetrics.collectionAmount(collections)
            if collections.contains(where: { !$0.amount.isValid || !$0.amount.isPositive }) || !recorded.isValid {
                reasons.insert(.invalidCollectionAmount)
            }
            if !recorded.isPositive {
                if project.paidAmount.isPositive { reasons.insert(.historicalManualPaid) }
                if !project.paidAmount.isValid && !project.paidAmount.isEmpty { reasons.insert(.invalidCollectionAmount) }
            }
        }

        var due = MoneyValue.zero, future = MoneyValue.zero, overdue = MoneyValue.zero
        var dueToday = MoneyValue.zero, retention = MoneyValue.zero
        var oldest: Int?
        if activePlans.count == 1, let plan = activePlans.first {
            var scope = project
            scope.paymentPlans = [plan]
            let summary = ProjectPaymentMetrics.summaries(project: scope, records: allocatedCollections).first
            let validShape = !plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && plan.installments.count <= 120
            if let summary, summary.isValid, validShape {
                if summary.overpaid.isPositive { reasons.insert(.overpaidPlan) }
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = timeZone
                for item in summary.installments {
                    guard let day = item.installment.dueDate.calendarDay(in: timeZone) else {
                        reasons.insert(.invalidPlan)
                        continue
                    }
                    if day <= today { due += item.remaining } else { future += item.remaining }
                    if day == today { dueToday += item.remaining }
                    if day < today {
                        overdue += item.remaining
                        if item.remaining.isPositive, let start = day.date(in: timeZone), let end = today.date(in: timeZone),
                           let age = calendar.dateComponents([.day], from: start, to: end).day {
                            oldest = max(oldest ?? age, age)
                        }
                    }
                    if item.installment.isRetention { retention += item.remaining }
                }
                if ![due, future, overdue, dueToday, retention].allSatisfy(\.isValid) { reasons.insert(.invalidPlan) }
            } else {
                reasons.insert(.invalidPlan)
            }
        }
        reviewReasons = reasons
        state = !reasons.isEmpty ? .needsReview : activePlans.isEmpty ? .noActiveIncomePlan : .ready
        let ready = state == .ready
        planID = activePlans.count == 1 ? activePlans.first?.id : nil
        dueUnpaidAmount = ready ? due : nil
        futureUnpaidAmount = ready ? future : nil
        overdueUnpaidAmount = ready ? overdue : nil
        dueTodayUnpaidAmount = ready ? dueToday : nil
        retentionUnpaidAmount = ready ? retention : nil
        oldestOverdueDays = ready ? oldest : nil
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
