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
        let activeRecords = records.filter { $0.projectId == project.id && $0.countsInBusinessMetrics }
        var reasons = Self.initialReviewReasons(
            project: project,
            activePlans: activePlans,
            plansByID: plansByID,
            activeRecords: activeRecords
        )
        let allocatedCollections = Self.collectAllocatedRecords(
            activeRecords: activeRecords,
            plansByID: plansByID,
            hasActivePlans: !activePlans.isEmpty,
            reasons: &reasons
        )
        if !activePlans.isEmpty {
            Self.validateCollectionTotals(project: project, activeRecords: activeRecords, reasons: &reasons)
        }
        let buckets = Self.evaluateActivePlanBuckets(
            project: project,
            activePlans: activePlans,
            allocatedCollections: allocatedCollections,
            today: today,
            timeZone: timeZone,
            reasons: &reasons
        )
        reviewReasons = reasons
        state = !reasons.isEmpty ? .needsReview : activePlans.isEmpty ? .noActiveIncomePlan : .ready
        let ready = state == .ready
        planID = activePlans.count == 1 ? activePlans.first?.id : nil
        dueUnpaidAmount = ready ? buckets.due : nil
        futureUnpaidAmount = ready ? buckets.future : nil
        overdueUnpaidAmount = ready ? buckets.overdue : nil
        dueTodayUnpaidAmount = ready ? buckets.dueToday : nil
        retentionUnpaidAmount = ready ? buckets.retention : nil
        oldestOverdueDays = ready ? buckets.oldestOverdueDays : nil
    }

    private struct ScheduleBuckets {
        var due = MoneyValue.zero
        var future = MoneyValue.zero
        var overdue = MoneyValue.zero
        var dueToday = MoneyValue.zero
        var retention = MoneyValue.zero
        var oldestOverdueDays: Int?
    }

    private static func initialReviewReasons(
        project: Project,
        activePlans: [ProjectPaymentPlan],
        plansByID: [UUID: [ProjectPaymentPlan]],
        activeRecords: [ProjectFinancialRecord]
    ) -> Set<ReviewReason> {
        var reasons: Set<ReviewReason> = []
        if activePlans.count > 1 { reasons.insert(.multipleActiveIncomePlans) }
        let installmentIDs = project.paymentPlans.flatMap { $0.installments.map(\.id) }
        if plansByID.values.contains(where: { $0.count > 1 }) || Set(installmentIDs).count != installmentIDs.count {
            reasons.insert(.duplicateIdentity)
        }
        let relevantRecords = activeRecords.filter { $0.paymentAllocation != nil || $0.isCollectionIncome }
        if Set(relevantRecords.map(\.id)).count != relevantRecords.count {
            reasons.insert(.duplicateIdentity)
        }
        return reasons
    }

    private static func collectAllocatedRecords(
        activeRecords: [ProjectFinancialRecord],
        plansByID: [UUID: [ProjectPaymentPlan]],
        hasActivePlans: Bool,
        reasons: inout Set<ReviewReason>
    ) -> [ProjectFinancialRecord] {
        var allocatedCollections: [ProjectFinancialRecord] = []
        for record in activeRecords {
            guard let allocation = record.paymentAllocation else {
                if hasActivePlans, record.isCollectionIncome, record.amount.isPositive {
                    reasons.insert(.unallocatedCollections)
                }
                continue
            }
            guard let plan = uniqueAllocatedPlan(allocation, plansByID: plansByID) else {
                reasons.insert(.invalidAllocation)
                continue
            }
            // A collection linked to a historical or payable plan is not
            // allocated to this active income plan. Never silently apply it.
            guard !plan.isArchived, plan.direction == .income else {
                if hasActivePlans, record.isCollectionIncome { reasons.insert(.unallocatedCollections) }
                continue
            }
            guard record.isCollectionIncome, record.amount.isPositive else {
                reasons.insert(.invalidAllocation)
                continue
            }
            allocatedCollections.append(record)
        }
        return allocatedCollections
    }

    private static func uniqueAllocatedPlan(
        _ allocation: ProjectPaymentAllocation,
        plansByID: [UUID: [ProjectPaymentPlan]]
    ) -> ProjectPaymentPlan? {
        guard let matches = plansByID[allocation.planID], matches.count == 1,
              let plan = matches.first,
              plan.installments.filter({ $0.id == allocation.installmentID }).count == 1 else {
            return nil
        }
        return plan
    }

    private static func validateCollectionTotals(
        project: Project,
        activeRecords: [ProjectFinancialRecord],
        reasons: inout Set<ReviewReason>
    ) {
        let collections = activeRecords.filter(\.isCollectionIncome)
        let recorded = ProjectFinancialMetrics.collectionAmount(collections)
        if collections.contains(where: { !$0.amount.isValid || !$0.amount.isPositive }) || !recorded.isValid {
            reasons.insert(.invalidCollectionAmount)
        }
        guard !recorded.isPositive else { return }
        if project.paidAmount.isPositive { reasons.insert(.historicalManualPaid) }
        if !project.paidAmount.isValid && !project.paidAmount.isEmpty { reasons.insert(.invalidCollectionAmount) }
    }

    private static func evaluateActivePlanBuckets(
        project: Project,
        activePlans: [ProjectPaymentPlan],
        allocatedCollections: [ProjectFinancialRecord],
        today: CalendarDay,
        timeZone: TimeZone,
        reasons: inout Set<ReviewReason>
    ) -> ScheduleBuckets {
        guard activePlans.count == 1, let plan = activePlans.first else { return ScheduleBuckets() }
        var scope = project
        scope.paymentPlans = [plan]
        let summary = ProjectPaymentMetrics.summaries(project: scope, records: allocatedCollections).first
        let validShape = !plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && plan.installments.count <= 120
        guard let summary, summary.isValid, validShape else {
            reasons.insert(.invalidPlan)
            return ScheduleBuckets()
        }
        if summary.overpaid.isPositive { reasons.insert(.overpaidPlan) }
        return accumulateInstallmentBuckets(summary: summary, today: today, timeZone: timeZone, reasons: &reasons)
    }

    private static func accumulateInstallmentBuckets(
        summary: PaymentPlanSummary,
        today: CalendarDay,
        timeZone: TimeZone,
        reasons: inout Set<ReviewReason>
    ) -> ScheduleBuckets {
        var buckets = ScheduleBuckets()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        for item in summary.installments {
            guard let day = item.installment.dueDate.calendarDay(in: timeZone) else {
                reasons.insert(.invalidPlan)
                continue
            }
            if day <= today { buckets.due += item.remaining } else { buckets.future += item.remaining }
            if day == today { buckets.dueToday += item.remaining }
            if day < today {
                buckets.overdue += item.remaining
                if item.remaining.isPositive, let start = day.date(in: timeZone), let end = today.date(in: timeZone),
                   let age = calendar.dateComponents([.day], from: start, to: end).day {
                    buckets.oldestOverdueDays = max(buckets.oldestOverdueDays ?? age, age)
                }
            }
            if item.installment.isRetention { buckets.retention += item.remaining }
        }
        if ![buckets.due, buckets.future, buckets.overdue, buckets.dueToday, buckets.retention].allSatisfy(\.isValid) {
            reasons.insert(.invalidPlan)
        }
        return buckets
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
                    && payments.allSatisfy { $0.amount.isPositive && isEligiblePayment($0, for: plan) }
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
        guard isEligiblePayment(record, for: plan) else { throw BusinessWorkflowError.invalidAllocation }
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

    private static func isEligiblePayment(_ record: ProjectFinancialRecord, for plan: ProjectPaymentPlan) -> Bool {
        guard record.direction == plan.direction, record.category != .refund else { return false }
        // Income installments settle on the same collections as contract and
        // receivable metrics. Persisted request/other links require review.
        return plan.direction == .expense || record.isCollectionIncome
    }

    private static func positiveDifference(_ lhs: MoneyValue, _ rhs: MoneyValue) -> MoneyValue {
        let result = lhs - rhs
        guard let value = result.optionalDecimal else { return .empty }
        return MoneyValue(max(.zero, value))
    }
}
