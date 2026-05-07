import SwiftUI

struct ProjectDetailRiskStripView: View {
    let overdueCount: Int
    let unpaidAmount: Double
    let unpricedQuoteCount: Int
    let hasTodayLog: Bool

    private var level: Color {
        if overdueCount > 0 || unpaidAmount > 0 || unpricedQuoteCount > 0 || !hasTodayLog {
            return overdueCount >= 2 || unpaidAmount > 10000 ? .red : .orange
        }
        return .green
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
                HStack(spacing: 8) {
                    ProjectDetailRiskChipView(
                        text: "延期 \(overdueCount)",
                        color: overdueCount > 0 ? .red : .green
                    )
                    ProjectDetailRiskChipView(
                        text: "未收 \(ReportBuilder.money(unpaidAmount))",
                        color: unpaidAmount > 0 ? .orange : .green
                    )
                    ProjectDetailRiskChipView(
                        text: "待补报价 \(unpricedQuoteCount)",
                        color: unpricedQuoteCount > 0 ? .orange : .green
                    )
                    ProjectDetailRiskChipView(
                        text: hasTodayLog ? "今日日志已写" : "今日日志未写",
                        color: hasTodayLog ? .green : .red
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

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.14)))
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
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            if !log.photoAttachments.isEmpty {
                Label("\(log.photoAttachments.count) 张照片", systemImage: "camera.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
