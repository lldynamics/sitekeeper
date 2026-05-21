import SwiftUI

struct ProjectBusinessSummary {
    var quoteTotal: Double
    var contractAmount: Double
    var paidAmount: Double
    var receivableAmount: Double
    var receivableAgeDays: Int?
    var recentCollection: CollectionSnapshot?
    var materialCost: Double
    var laborCostAmount: Double
    var pendingMaterialCount: Int
    var unpricedQuoteCount: Int

    var estimatedProfit: Double {
        contractAmount - materialCost - laborCostAmount
    }

    var pendingCount: Int {
        pendingMaterialCount + unpricedQuoteCount
    }

    var unpaidAmount: Double {
        max(contractAmount - paidAmount, 0)
    }
}

struct ProjectBusinessCardsView: View {
    let summary: ProjectBusinessSummary
    var onOpenCore: (() -> Void)? = nil
    var onOpenInsight: (() -> Void)? = nil

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: AppSpacing.tight), GridItem(.flexible(), spacing: AppSpacing.tight)],
            spacing: AppSpacing.tight
        ) {
            ProjectBusinessMetricCard(
                title: "经营核心",
                systemImage: "chart.bar.xaxis",
                tint: .appDoc,
                metrics: [
                    .init(title: "报价", value: ReportBuilder.money(summary.quoteTotal), color: .appPrimaryAction),
                    .init(title: "合同", value: ReportBuilder.money(summary.contractAmount)),
                    .init(title: "已收", value: ReportBuilder.money(summary.paidAmount), color: .appSuccess),
                    .init(title: "未收", value: ReportBuilder.money(summary.unpaidAmount), color: summary.unpaidAmount > 0 ? .appPrimaryAction : .secondary),
                    .init(title: "材料成本", value: ReportBuilder.money(summary.materialCost), color: .appDoc),
                    .init(title: "人工成本", value: ReportBuilder.money(summary.laborCostAmount), color: .appWarning),
                    .init(title: "毛利估算", value: ReportBuilder.money(summary.estimatedProfit), color: summary.estimatedProfit >= 0 ? .appSuccess : .appRisk),
                    .init(title: "待补", value: "\(summary.pendingCount)", color: summary.pendingCount > 0 ? .appPrimaryAction : .secondary)
                ],
                action: onOpenCore
            )

            ProjectBusinessMetricCard(
                title: "经营洞察",
                systemImage: "waveform.path.ecg",
                tint: .appPrimaryAction,
                metrics: [
                    .init(title: "应收账龄", value: receivableAgeText(summary), color: receivableAgeColor(summary)),
                    .init(title: "最近回款", value: recentCollectionText(summary), color: recentCollectionColor(summary)),
                    .init(title: "成本异常", value: costAnomalyText(summary), color: costAnomalyColor(summary)),
                    .init(title: "利润风险", value: profitRiskText(summary), color: profitRiskColor(summary))
                ],
                action: onOpenInsight
            )
        }
    }

    private func receivableAgeText(_ summary: ProjectBusinessSummary) -> String {
        guard summary.receivableAmount > 0 else { return "无应收" }
        guard let days = summary.receivableAgeDays else { return "未填完工日" }
        if days == 0 {
            return DashboardSubtitleBuilder.moneySummary(
                "未到期",
                amount: ReportBuilder.money(summary.receivableAmount)
            )
        }
        return DashboardSubtitleBuilder.moneySummary(
            "\(days)天",
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
        guard let collection = summary.recentCollection else { return "暂无回款" }
        return DashboardSubtitleBuilder.datedAmount(
            collection.date,
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
        guard summary.contractAmount > 0 else { return "缺合同金额" }
        guard totalCost > 0 else {
            return pendingCount > 0 ? "待补 \(pendingCount) 项" : "未录成本"
        }
        let ratio = totalCost / summary.contractAmount
        if ratio > 1 {
            return "超合同 \(ReportBuilder.money(totalCost - summary.contractAmount))"
        }
        if ratio >= 0.85 {
            return "成本占比 \(percent(ratio))"
        }
        if pendingCount > 0 {
            return "待补 \(pendingCount) 项"
        }
        return "正常 \(percent(ratio))"
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
        guard summary.contractAmount > 0 else { return "缺合同金额" }
        let profit = summary.estimatedProfit
        let margin = profit / summary.contractAmount
        if profit < 0 {
            return "亏损 \(ReportBuilder.money(abs(profit)))"
        }
        if margin < 0.10 {
            return "低毛利 \(percent(margin))"
        }
        if margin < 0.20 {
            return "关注 \(percent(margin))"
        }
        return "健康 \(percent(margin))"
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

    private func percent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value * 100))%"
    }
}

private struct ProjectBusinessCardMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    var color: Color = .primary
}

private struct ProjectBusinessMetricCard: View {
    let title: String
    let systemImage: String
    let tint: Color
    let metrics: [ProjectBusinessCardMetric]
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
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

            ForEach(metrics) { metric in
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
        .frame(maxWidth: .infinity, minHeight: 158, alignment: .topLeading)
        .padding(AppSpacing.normal)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.tight, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}
