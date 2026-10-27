import SwiftUI

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
                Text("\(AppLocalization.string("明日")): \(log.tomorrowPlan)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !log.qualityIssue.isEmpty {
                Text("\(AppLocalization.string("质量")): \(log.qualityIssue)")
                    .font(.caption2)
                    .foregroundStyle(.appRisk)
                    .lineLimit(1)
            }
            if !log.photoAttachments.isEmpty {
                Label(
                    String(format: AppLocalization.string("%lld 张照片"), Int64(log.photoAttachments.count)),
                    systemImage: "camera.fill"
                )
                    .font(.caption2)
                    .foregroundStyle(Color.appDoc)
            }
            if !log.linkedConstructionMethodIDs.isEmpty {
                Label(
                    String(
                        format: AppLocalization.string("关联工艺 %lld 条"),
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
