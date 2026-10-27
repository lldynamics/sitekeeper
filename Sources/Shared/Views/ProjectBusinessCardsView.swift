import SwiftUI

struct ProjectBusinessSummary {
    var quoteTotal: MoneyValue
    var contractAmount: MoneyValue
    var paidAmount: MoneyValue
    var receivableAmount: MoneyValue
    var receivableAgeDays: Int?
    var recentCollection: CollectionSnapshot?
    var materialCost: MoneyValue
    var laborCostAmount: MoneyValue
    var pendingMaterialCount: Int
    var unpricedQuoteCount: Int

    var estimatedProfit: MoneyValue {
        contractAmount - materialCost - laborCostAmount
    }

    var pendingCount: Int {
        pendingMaterialCount + unpricedQuoteCount
    }

    var unpaidAmount: MoneyValue {
        ProjectFinancialMetrics.unpaidAmount(contractAmount: contractAmount, paidAmount: paidAmount)
    }
}

struct ProjectBusinessCardsView: View {
    let summary: ProjectBusinessSummary
    var onOpenCore: (() -> Void)? = nil
    var onOpenInsight: (() -> Void)? = nil
    var onOpenReceivableAging: (() -> Void)? = nil
    var onOpenRecentCollection: (() -> Void)? = nil
    var onOpenCostAnomaly: (() -> Void)? = nil
    var onOpenProfitRisk: (() -> Void)? = nil

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: AppSpacing.tight), GridItem(.flexible(), spacing: AppSpacing.tight)],
            spacing: AppSpacing.tight
        ) {
            ProjectBusinessMetricCard(
                title: AppLocalization.string("project.business.core.title"),
                systemImage: "chart.bar.xaxis",
                tint: .appDoc,
                metrics: [
                    .init(title: AppLocalization.string("project.business.quote"), value: ReportBuilder.money(summary.quoteTotal), color: .appPrimaryAction),
                    .init(title: AppLocalization.string("project.business.contract"), value: ReportBuilder.money(summary.contractAmount)),
                    .init(title: AppLocalization.string("project.business.collected"), value: ReportBuilder.money(summary.paidAmount), color: .appSuccess),
                    .init(title: AppLocalization.string("project.business.uncollected"), value: ReportBuilder.money(summary.unpaidAmount), color: summary.unpaidAmount > 0 ? .appPrimaryAction : .secondary),
                    .init(title: AppLocalization.string("project.business.materialCost"), value: ReportBuilder.money(summary.materialCost), color: .appDoc),
                    .init(title: AppLocalization.string("project.business.laborCost"), value: ReportBuilder.money(summary.laborCostAmount), color: .appWarning),
                    .init(title: AppLocalization.string("project.business.estimatedGrossProfit"), value: ReportBuilder.money(summary.estimatedProfit), color: summary.estimatedProfit >= 0 ? .appSuccess : .appRisk),
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
                        title: AppLocalization.string("project.business.receivableAge"),
                        value: receivableAgeText(summary),
                        color: receivableAgeColor(summary),
                        action: onOpenReceivableAging,
                        accessibilityIdentifier: "dashboard-business-receivable-aging"
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

    private func receivableAgeText(_ summary: ProjectBusinessSummary) -> String {
        guard summary.receivableAmount > 0 else { return AppLocalization.string("project.business.noReceivable") }
        guard let days = summary.receivableAgeDays else { return AppLocalization.string("project.business.missingCompletionDate") }
        if days == 0 {
            return DashboardSubtitleBuilder.moneySummary(
                AppLocalization.string("project.business.notDue"),
                amount: ReportBuilder.money(summary.receivableAmount)
            )
        }
        return DashboardSubtitleBuilder.moneySummary(
            String(format: AppLocalization.string("project.business.days"), Int64(days)),
            amount: ReportBuilder.money(summary.receivableAmount)
        )
    }

    private func receivableAgeColor(_ summary: ProjectBusinessSummary) -> Color {
        guard summary.receivableAmount > 0 else { return .appSuccess }
        guard let days = summary.receivableAgeDays else { return .appPrimaryAction }
        if days >= 60 { return .appRisk }
        if days >= 30 { return .appPrimaryAction }
        if days > 0 { return .appDoc }
        return .secondary
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
        let totalCost = summary.materialCost + summary.laborCostAmount
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
        let totalCost = summary.materialCost + summary.laborCostAmount
        guard summary.contractAmount > 0 else { return .appPrimaryAction }
        guard totalCost > 0 else { return summary.pendingCount > 0 ? .appPrimaryAction : .secondary }
        let ratio = totalCost / summary.contractAmount
        if ratio > 1 { return .appRisk }
        if ratio >= 0.85 { return .appPrimaryAction }
        if summary.pendingCount > 0 { return .appPrimaryAction }
        return .appSuccess
    }

    private func profitRiskText(_ summary: ProjectBusinessSummary) -> String {
        guard summary.contractAmount > 0 else { return AppLocalization.string("project.business.missingContractAmount") }
        let profit = summary.estimatedProfit
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
        guard summary.contractAmount > 0 else { return .appPrimaryAction }
        let profit = summary.estimatedProfit
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
            RoundedRectangle(cornerRadius: AppSpacing.tight, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}
