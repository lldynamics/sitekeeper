import SwiftUI

struct WidgetSectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.secondary)
    }
}

struct WidgetCompactSignalRow: View {
    let icon: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .frame(width: 13)
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WidgetSummaryTile: View {
    let icon: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
    }
}

struct WidgetRiskPill: View {
    let item: WidgetRiskLinkItem

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: item.icon)
                .font(.caption2.weight(.semibold))
            Text(item.badgeText)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(item.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(item.tint.opacity(0.14))
        )
    }
}

struct WidgetProjectProgressRow: View {
    let project: WidgetProjectSummary
    let showsStatus: Bool
    let showsTodo: Bool
    var compact: Bool = false

    var body: some View {
        let status = WidgetProjectStatus.parse(project.status)
        let tint = widgetProjectTint(for: status)

        Link(destination: WidgetDeepLinkURL.project(id: project.id)) {
            VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font((compact ? Font.caption2 : Font.caption).weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 4)

                    if showsStatus {
                        WidgetStatusCapsule(text: widgetProjectStatusText(status), tint: tint)
                    } else {
                        Text("\(Int(widgetClampedProgress(project.progress) * 100))%")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                }

                HStack(spacing: 8) {
                    WidgetProgressBar(value: project.progress, tint: tint)
                    if showsStatus {
                        Text("\(Int(widgetClampedProgress(project.progress) * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                if showsTodo, project.todoCount > 0 {
                    Text(widgetLocalizedCount("widget_project_todo_count_format", project.todoCount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct WidgetProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, proxy.size.width * widgetClampedProgress(value)))
            }
        }
        .frame(height: 4)
    }
}

private struct WidgetStatusCapsule: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(
                Capsule()
                    .fill(tint.opacity(0.14))
            )
    }
}

struct WidgetEmptyState: View {
    let text: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "hammer")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}
