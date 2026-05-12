import SwiftUI

struct ProjectDetailRiskStripView: View {
    let overdueCount: Int
    let unpaidAmount: Double
    let unpricedQuoteCount: Int
    let hasTodayLog: Bool

    private var level: Color {
        if overdueCount > 0 || unpaidAmount > 0 || unpricedQuoteCount > 0 || !hasTodayLog {
            return overdueCount >= 2 || unpaidAmount > 10000 ? .appRisk : .appPrimaryAction
        }
        return .appSuccess
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(level)
                Text("项目风险")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(level)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.tight) {
                    ProjectDetailRiskChipView(
                        text: "延期 \(overdueCount)",
                        color: overdueCount > 0 ? .appRisk : .appSuccess,
                        hasRisk: overdueCount > 0
                    )
                    ProjectDetailRiskChipView(
                        text: "未收 \(ReportBuilder.money(unpaidAmount))",
                        color: unpaidAmount > 0 ? .appPrimaryAction : .appSuccess,
                        hasRisk: unpaidAmount > 0
                    )
                    ProjectDetailRiskChipView(
                        text: "待补报价 \(unpricedQuoteCount)",
                        color: unpricedQuoteCount > 0 ? .appPrimaryAction : .appSuccess,
                        hasRisk: unpricedQuoteCount > 0
                    )
                    ProjectDetailRiskChipView(
                        text: hasTodayLog ? "今日日志已写" : "今日日志未写",
                        color: hasTodayLog ? .appSuccess : .appRisk,
                        hasRisk: !hasTodayLog
                    )
                }
                .padding(.vertical, 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("用于快速判断延期、回款、报价和日志填写风险")
    }
}

private struct ProjectDetailRiskChipView: View {
    let text: String
    let color: Color
    let hasRisk: Bool

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(hasRisk ? .white : color)
            .padding(.horizontal, AppSpacing.tight)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hasRisk ? color : color.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(hasRisk ? color : color.opacity(0.35), lineWidth: 0.5)
            )
            .accessibilityLabel(text)
            .accessibilityValue(hasRisk ? "需要关注" : "正常")
    }
}

struct ProjectDetailLogRowView: View {
    let log: DailyLog

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(log.date)
                    .font(.caption.weight(.medium))
                Text(log.weather)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if !log.confirmer.isEmpty {
                    Text(log.confirmer)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(log.content)
                .font(.caption)
                .lineLimit(2)
            if !log.tomorrowPlan.isEmpty {
                Text("明日: \(log.tomorrowPlan)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !log.qualityIssue.isEmpty {
                Text("质量: \(log.qualityIssue)")
                    .font(.caption2)
                    .foregroundStyle(.appRisk)
                    .lineLimit(1)
            }
            if !log.photoAttachments.isEmpty {
                Label("\(log.photoAttachments.count) 张照片", systemImage: "camera.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.appDoc)
            }
            if !log.linkedConstructionMethodIDs.isEmpty {
                Label("关联工艺 \(log.linkedConstructionMethodIDs.count) 条", systemImage: "link.badge.plus")
                    .font(.caption2)
                    .foregroundStyle(Color.appPrimaryAction)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
