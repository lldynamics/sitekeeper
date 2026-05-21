import SwiftUI

struct ProjectDetailRiskStripView: View {
    let overdueCount: Int
    let unpaidAmount: Double
    let unpricedQuoteCount: Int
    let hasTodayLog: Bool
    var missingDocumentCategoryCount = 0
    var documentActionCount = 0
    var legacyDocumentCount = 0

    private var level: Color {
        if overdueCount > 0 ||
            unpaidAmount > 0 ||
            unpricedQuoteCount > 0 ||
            missingDocumentCategoryCount > 0 ||
            documentActionCount > 0 ||
            legacyDocumentCount > 0 ||
            !hasTodayLog {
            return overdueCount >= 2 || unpaidAmount > 10000 || missingDocumentCategoryCount >= 3 ? .appRisk : .appPrimaryAction
        }
        return .appSuccess
    }

    private var riskItems: [(text: String, tone: StatusChipTone)] {
        var items: [(String, StatusChipTone)] = []
        if overdueCount > 0 {
            items.append((String(format: String(localized: "延期 %lld"), Int64(overdueCount)), .risk))
        }
        if unpaidAmount > 0 {
            items.append((String(format: String(localized: "未收 %@"), ReportBuilder.money(unpaidAmount)), .primary))
        }
        if unpricedQuoteCount > 0 {
            items.append((String(format: String(localized: "待补报价 %lld"), Int64(unpricedQuoteCount)), .primary))
        }
        if missingDocumentCategoryCount > 0 {
            items.append((String(format: String(localized: "资料缺项 %lld 类"), Int64(missingDocumentCategoryCount)), .warning))
        }
        if documentActionCount > 0 {
            items.append((String(format: String(localized: "资料待处理 %lld"), Int64(documentActionCount)), .primary))
        }
        if legacyDocumentCount > 0 {
            items.append((String(format: String(localized: "旧资料待细分 %lld"), Int64(legacyDocumentCount)), .warning))
        }
        if !hasTodayLog {
            items.append((String(localized: "今日日志未写"), .risk))
        }
        return items
    }

    var body: some View {
        if riskItems.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(level)
                    Text(String(localized: "项目风险"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(level)
                    Spacer()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.tight) {
                        ForEach(riskItems.indices, id: \.self) { index in
                            let item = riskItems[index]
                            ProjectDetailRiskChipView(
                                text: item.text,
                                tone: item.tone
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(String(localized: "用于快速判断延期、回款、报价、日志和资料缺项风险"))
        }
    }
}

private struct ProjectDetailRiskChipView: View {
    let text: String
    let tone: StatusChipTone

    var body: some View {
        StatusChip(text: text, tone: tone, compact: true)
            .accessibilityLabel(text)
            .accessibilityValue(String(localized: "需要关注"))
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
                Text("\(String(localized: "明日")): \(log.tomorrowPlan)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !log.qualityIssue.isEmpty {
                Text("\(String(localized: "质量")): \(log.qualityIssue)")
                    .font(.caption2)
                    .foregroundStyle(.appRisk)
                    .lineLimit(1)
            }
            if !log.photoAttachments.isEmpty {
                Label(
                    String(format: String(localized: "%lld 张照片"), Int64(log.photoAttachments.count)),
                    systemImage: "camera.fill"
                )
                    .font(.caption2)
                    .foregroundStyle(Color.appDoc)
            }
            if !log.linkedConstructionMethodIDs.isEmpty {
                Label(
                    String(
                        format: String(localized: "关联工艺 %lld 条"),
                        Int64(log.linkedConstructionMethodIDs.count)
                    ),
                    systemImage: "link.badge.plus"
                )
                    .font(.caption2)
                    .foregroundStyle(Color.appPrimaryAction)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
