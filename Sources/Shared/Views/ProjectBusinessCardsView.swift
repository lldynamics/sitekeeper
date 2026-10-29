import SwiftUI

struct ProjectBusinessSummary {
    var quoteTotal: MoneyValue
    var contractAmount: MoneyValue
    var paidAmount: MoneyValue
    var receivableAmount: MoneyValue
    /// Kept for older benchmark adapters; completion dates are not payment aging.
    var receivableAgeDays: Int? = nil
    var recentCollection: CollectionSnapshot?
    var materialCost: MoneyValue
    var laborCostAmount: MoneyValue
    var pendingMaterialCount: Int
    var unpricedQuoteCount: Int
    var scope: ProjectBusinessScope? = nil

    var estimatedProfit: MoneyValue {
        contractAmount - materialCost - laborCostAmount
    }

    var pendingCount: Int {
        pendingMaterialCount + unpricedQuoteCount
    }

    var unpaidAmount: MoneyValue {
        receivableAmount
    }
}

/// Optional values represent incomplete or ambiguous inputs, never zero.
struct ProjectBusinessScope {
    let contractAmount: MoneyValue?
    let contractUnpaid: MoneyValue?
    let selectedQuoteAmount: MoneyValue?
    let hasQuotes: Bool
    let quoteProjectsNeedingReview: Int
    let materialEstimate: MoneyValue?
    let laborEstimate: MoneyValue?
    let formalExpense: MoneyValue?
    let formalExpenseCount: Int
    let estimatedProfit: MoneyValue?
    let duePlanAmount: MoneyValue?
    let futurePlanAmount: MoneyValue?
    let readyPlanCount: Int
    let plansNeedingReview: Int
    let projectsWithoutPlan: Int
}

struct ProjectBusinessCardsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let summary: ProjectBusinessSummary
    var onOpenCore: (() -> Void)? = nil
    var onOpenInsight: (() -> Void)? = nil
    var onOpenReceivableAging: (() -> Void)? = nil
    var onOpenRecentCollection: (() -> Void)? = nil
    var onOpenCostAnomaly: (() -> Void)? = nil
    var onOpenProfitRisk: (() -> Void)? = nil

    var body: some View {
        LazyVGrid(
            columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible(), spacing: AppSpacing.tight)]
                : [GridItem(.adaptive(minimum: 240), spacing: AppSpacing.tight)],
            spacing: AppSpacing.tight
        ) {
            ProjectBusinessMetricCard(
                title: AppLocalization.string("project.business.core.title"),
                systemImage: "chart.bar.xaxis",
                tint: .appDoc,
                metrics: [
                    .init(title: AppLocalization.string("business_scope_selected_quote"), value: selectedQuoteText(summary), color: .appPrimaryAction),
                    .init(title: AppLocalization.string("project.business.contract"), value: optionalMoney(summary.scope?.contractAmount)),
                    .init(title: AppLocalization.string("project.business.collected"), value: ReportBuilder.money(summary.paidAmount), color: .appSuccess),
                    .init(title: AppLocalization.string("business_scope_contract_unpaid"), value: optionalMoney(summary.scope?.contractUnpaid), color: summary.unpaidAmount > 0 ? .appPrimaryAction : .secondary),
                    .init(title: AppLocalization.string("cost_basis_material"), value: optionalMoney(summary.scope?.materialEstimate), color: .appDoc),
                    .init(title: AppLocalization.string("cost_basis_labor"), value: optionalMoney(summary.scope?.laborEstimate), color: .appWarning),
                    .init(title: AppLocalization.string("cost_basis_expense"), value: expenseText(summary), color: .appFinance),
                    .init(title: AppLocalization.string("project.business.estimatedGrossProfit"), value: optionalMoney(summary.scope?.estimatedProfit), color: profitColor(summary)),
                    .init(title: AppLocalization.string("project.business.pending"), value: "\(summary.pendingCount)", color: summary.pendingCount > 0 ? .appPrimaryAction : .secondary)
                ],
                action: onOpenCore
            )

            ProjectBusinessMetricCard(
                title: AppLocalization.string("project.business.insights.title"),
                systemImage: "waveform.path.ecg",
                tint: .appPrimaryAction,
                metrics: [
                    .init(
                        title: AppLocalization.string("business_scope_due_plan"),
                        value: planAmountText(summary, isDue: true),
                        color: planAmountColor(summary),
                        action: onOpenReceivableAging,
                        accessibilityIdentifier: "dashboard-business-receivable-aging"
                    ),
                    .init(
                        title: AppLocalization.string("business_scope_future_plan"),
                        value: planAmountText(summary, isDue: false),
                        color: planAmountColor(summary),
                        action: onOpenReceivableAging,
                        accessibilityIdentifier: "dashboard-business-receivable-future"
                    ),
                    .init(
                        title: AppLocalization.string("business_scope_plan_coverage"),
                        value: planCoverageText(summary),
                        color: planAmountColor(summary),
                        action: onOpenReceivableAging,
                        accessibilityIdentifier: "dashboard-business-receivable-review"
                    ),
                    .init(
                        title: AppLocalization.string("project.business.recentCollection"),
                        value: recentCollectionText(summary),
                        color: recentCollectionColor(summary),
                        action: onOpenRecentCollection,
                        accessibilityIdentifier: "dashboard-business-recent-collection"
                    ),
                    .init(
                        title: AppLocalization.string("project.business.costException"),
                        value: costAnomalyText(summary),
                        color: costAnomalyColor(summary),
                        action: onOpenCostAnomaly,
                        accessibilityIdentifier: "dashboard-business-cost-anomaly"
                    ),
                    .init(
                        title: AppLocalization.string("project.business.profitRisk"),
                        value: profitRiskText(summary),
                        color: profitRiskColor(summary),
                        action: onOpenProfitRisk,
                        accessibilityIdentifier: "dashboard-business-profit-risk"
                    )
                ],
                action: onOpenInsight
            )
        }
    }

    private func optionalMoney(_ amount: MoneyValue?) -> String {
        amount.map(ReportBuilder.money) ?? AppLocalization.string("cost_basis_unknown")
    }

    private func selectedQuoteText(_ summary: ProjectBusinessSummary) -> String {
        guard let scope = summary.scope else { return AppLocalization.string("cost_basis_unknown") }
        guard scope.hasQuotes else { return AppLocalization.string("business_scope_no_quotes") }
        if scope.quoteProjectsNeedingReview > 0 {
            return String(format: AppLocalization.string("business_scope_projects_review"), Int64(scope.quoteProjectsNeedingReview))
        }
        return optionalMoney(scope.selectedQuoteAmount)
    }

    private func expenseText(_ summary: ProjectBusinessSummary) -> String {
        guard let scope = summary.scope else { return AppLocalization.string("cost_basis_unknown") }
        guard scope.formalExpenseCount > 0 else { return AppLocalization.string("cost_basis_no_expenses") }
        return optionalMoney(scope.formalExpense)
    }

    private func profitColor(_ summary: ProjectBusinessSummary) -> Color {
        guard let profit = summary.scope?.estimatedProfit else { return .appWarning }
        return profit >= 0 ? .appSuccess : .appRisk
    }

    private func planAmountText(_ summary: ProjectBusinessSummary, isDue: Bool) -> String {
        guard let scope = summary.scope else { return AppLocalization.string("cost_basis_unknown") }
        if scope.plansNeedingReview > 0 { return AppLocalization.string("business_scope_plan_review") }
        guard scope.readyPlanCount > 0 else { return AppLocalization.string("business_scope_no_plan") }
        return optionalMoney(isDue ? scope.duePlanAmount : scope.futurePlanAmount)
    }

    private func planCoverageText(_ summary: ProjectBusinessSummary) -> String {
        guard let scope = summary.scope else { return AppLocalization.string("cost_basis_unknown") }
        return String(format: AppLocalization.string("business_scope_plan_coverage_format"),
                      Int64(scope.projectsWithoutPlan), Int64(scope.plansNeedingReview))
    }

    private func planAmountColor(_ summary: ProjectBusinessSummary) -> Color {
        guard let scope = summary.scope else { return .appWarning }
        if scope.plansNeedingReview > 0 || scope.projectsWithoutPlan > 0 { return .appWarning }
        return (scope.duePlanAmount?.isPositive ?? false) ? .appFinance : .secondary
    }

    private func recentCollectionText(_ summary: ProjectBusinessSummary) -> String {
        guard let collection = summary.recentCollection else { return AppLocalization.string("project.business.noRecentCollection") }
        return DashboardSubtitleBuilder.datedAmount(
            collection.date.storageText,
            amount: ReportBuilder.money(collection.amount),
            projectName: collection.projectName
        )
    }

    private func recentCollectionColor(_ summary: ProjectBusinessSummary) -> Color {
        summary.recentCollection == nil ? .secondary : .appSuccess
    }

    private func costAnomalyText(_ summary: ProjectBusinessSummary) -> String {
        guard let material = summary.scope?.materialEstimate, let labor = summary.scope?.laborEstimate,
              summary.scope?.contractAmount != nil else { return AppLocalization.string("cost_basis_unknown") }
        let totalCost = material + labor
        guard totalCost.isValid else { return AppLocalization.string("cost_basis_unknown") }
        let pendingCount = summary.pendingCount
        guard summary.contractAmount > 0 else { return AppLocalization.string("project.business.missingContractAmount") }
        guard totalCost > 0 else {
            return pendingCount > 0
                ? String(format: AppLocalization.string("project.business.pendingItems"), Int64(pendingCount))
                : AppLocalization.string("project.business.noCostRecorded")
        }
        let ratio = totalCost / summary.contractAmount
        if ratio > 1 {
            return String(
                format: AppLocalization.string("project.business.overContract"),
                ReportBuilder.money(totalCost - summary.contractAmount)
            )
        }
        if ratio >= 0.85 {
            return String(format: AppLocalization.string("project.business.costRatio"), percent(ratio))
        }
        if pendingCount > 0 {
            return String(format: AppLocalization.string("project.business.pendingItems"), Int64(pendingCount))
        }
        return String(format: AppLocalization.string("project.business.normalCostRatio"), percent(ratio))
    }

    private func costAnomalyColor(_ summary: ProjectBusinessSummary) -> Color {
        guard let material = summary.scope?.materialEstimate, let labor = summary.scope?.laborEstimate,
              summary.scope?.contractAmount != nil else { return .appWarning }
        let totalCost = material + labor
        guard totalCost.isValid else { return .appWarning }
        guard summary.contractAmount > 0 else { return .appPrimaryAction }
        guard totalCost > 0 else { return summary.pendingCount > 0 ? .appPrimaryAction : .secondary }
        let ratio = totalCost / summary.contractAmount
        if ratio > 1 { return .appRisk }
        if ratio >= 0.85 { return .appPrimaryAction }
        if summary.pendingCount > 0 { return .appPrimaryAction }
        return .appSuccess
    }

    private func profitRiskText(_ summary: ProjectBusinessSummary) -> String {
        guard let profit = summary.scope?.estimatedProfit else { return AppLocalization.string("cost_basis_unknown") }
        guard summary.contractAmount > 0 else { return AppLocalization.string("project.business.missingContractAmount") }
        let margin = profit / summary.contractAmount
        if profit < 0 {
            return String(format: AppLocalization.string("project.business.lossAmount"), ReportBuilder.money(profit.magnitude))
        }
        if margin < 0.10 {
            return String(format: AppLocalization.string("project.business.lowMargin"), percent(margin))
        }
        if margin < 0.20 {
            return String(format: AppLocalization.string("project.business.watchMargin"), percent(margin))
        }
        return String(format: AppLocalization.string("project.business.healthyMargin"), percent(margin))
    }

    private func profitRiskColor(_ summary: ProjectBusinessSummary) -> Color {
        guard let profit = summary.scope?.estimatedProfit else { return .appWarning }
        guard summary.contractAmount > 0 else { return .appPrimaryAction }
        let margin = profit / summary.contractAmount
        if profit < 0 { return .appRisk }
        if margin < 0.10 { return .appRisk }
        if margin < 0.20 { return .appPrimaryAction }
        return .appSuccess
    }

    private func percent(_ value: Decimal) -> String {
        value.formatted(.percent.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US_POSIX")))
    }
}

private struct ProjectBusinessCardMetric: Identifiable {
    let title: String
    let value: String
    var color: Color = .primary
    var action: (() -> Void)? = nil
    var accessibilityIdentifier: String? = nil
    var id: String { title }
}

private struct ProjectBusinessMetricCard: View {
    let title: String
    let systemImage: String
    let tint: Color
    let metrics: [ProjectBusinessCardMetric]
    var action: (() -> Void)? = nil

    private var hasMetricActions: Bool {
        metrics.contains(where: { $0.action != nil })
    }

    var body: some View {
        Group {
            if let action, !hasMetricActions {
                Button(action: action) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            HStack(spacing: AppSpacing.tight * 0.75) {
                if let action, hasMetricActions {
                    Button(action: action) {
                        HStack(spacing: AppSpacing.tight * 0.75) {
                            Image(systemName: systemImage)
                                .foregroundStyle(tint)
                            Text(title)
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    if action != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(metrics) { metric in
                if let metricAction = metric.action {
                    Button(action: metricAction) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(metric.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: AppSpacing.tight)
                            Text(metric.value)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(metric.color)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(metric.accessibilityIdentifier ?? "")
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(metric.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: AppSpacing.tight)
                        Text(metric.value)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(metric.color)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .padding(AppSpacing.normal)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 0.5)
        )
    }
}
