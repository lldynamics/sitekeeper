import SwiftUI
import WidgetKit
import Foundation

struct SmallWidgetView: View {
    var entry: SitekeeperProvider.Entry
    let data: WidgetExportData

    init(entry: SitekeeperProvider.Entry) {
        self.entry = entry
        self.data = entry.data
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checklist")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text(String(localized: "widget_label_todo"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("\(data.pendingTodos)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(String(localized: "widget_pending_items_text"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Image(systemName: "shippingbox")
                    .font(.caption2)
                Text(widgetLocalizedCount("widget_material_stock_count_format", data.materialStockCount))
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            if data.lowStockCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(widgetLocalizedCount("widget_low_stock_count_format", data.lowStockCount))
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
            }

            Text(widgetLocalizedUpdate("widget_updated_time_format", WidgetDateFormatters.timeOnly.string(from: entry.date)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MediumWidgetView: View {
    var entry: SitekeeperProvider.Entry
    let data: WidgetExportData

    init(entry: SitekeeperProvider.Entry) {
        self.entry = entry
        self.data = entry.data
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 左侧：待办统计
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "checklist")
                        .foregroundStyle(.orange)
                    Text(String(localized: "widget_label_today_todos"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(data.pendingTodos)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(String(localized: "widget_pending_items_text"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧：项目进度列表
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "widget_label_project_progress"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if data.projects.isEmpty {
                    Text(String(localized: "widget_no_active_projects"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                } else {
                    ForEach(data.projects.prefix(3), id: \.id) { project in
                        let status = WidgetProjectStatus.parse(project.status)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(project.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(project.progress * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: project.progress)
                                .tint(status.isCompleted ? .green : .orange)
                        }
                    }
                }
                Spacer()
                Text(widgetLocalizedUpdate("widget_updated_time_format", WidgetDateFormatters.timeOnly.string(from: entry.date)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LargeWidgetView: View {
    var entry: SitekeeperProvider.Entry
    let data: WidgetExportData

    init(entry: SitekeeperProvider.Entry) {
        self.entry = entry
        self.data = entry.data
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 顶部摘要行
            HStack(spacing: 16) {
                SummaryBlock(
                    icon: "checklist",
                    value: "\(data.pendingTodos)",
                    label: String(localized: "widget_label_todo"),
                    color: .orange
                )
                SummaryBlock(
                    icon: "shippingbox",
                    value: "\(data.materialStockCount)",
                    label: String(localized: "widget_label_material_types"),
                    color: .blue
                )
                if data.lowStockCount > 0 {
                    SummaryBlock(
                        icon: "exclamationmark.triangle.fill",
                        value: "\(data.lowStockCount)",
                        label: String(localized: "widget_label_low_stock"),
                        color: .red
                    )
                }
            }

            Divider()

            // 项目列表
            if data.projects.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "hammer")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "widget_no_active_projects"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ForEach(data.projects, id: \.id) { project in
                    let status = WidgetProjectStatus.parse(project.status)
                    let isCompleted = status.isCompleted
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(project.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Spacer()
                            Text(status.displayName)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(isCompleted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                )
                                .foregroundStyle(isCompleted ? .green : .orange)
                        }

                        HStack(spacing: 12) {
                            ProgressView(value: project.progress)
                                .tint(isCompleted ? .green : .orange)
                            Text("\(Int(project.progress * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }

                        if project.todoCount > 0 {
                            Text(widgetLocalizedCount("widget_project_todo_count_format", project.todoCount))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text(widgetLocalizedUpdate("widget_updated_datetime_format", WidgetDateFormatters.dateTime.string(from: entry.date)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private enum WidgetDateFormatters {
    private static let displayLocale = Locale.autoupdatingCurrent
    private static let displayTimeZone = TimeZone.autoupdatingCurrent

    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.timeZone = displayTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = displayLocale
        formatter.timeZone = displayTimeZone
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

private func widgetLocalizedCount(_ key: String, _ count: Int) -> String {
    let format = NSLocalizedString(key, comment: "")
    return String.localizedStringWithFormat(format, count)
}

private func widgetLocalizedUpdate(_ key: String, _ value: String) -> String {
    let format = NSLocalizedString(key, comment: "")
    return String.localizedStringWithFormat(format, value)
}

private struct SummaryBlock: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
