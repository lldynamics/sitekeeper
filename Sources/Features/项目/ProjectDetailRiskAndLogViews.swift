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
