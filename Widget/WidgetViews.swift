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
        let riskLinkItems = widgetRiskLinkItems(for: data)

        VStack(alignment: .leading, spacing: 6) {
            Link(destination: WidgetDeepLinkURL.todos) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "checklist")
                            .font(.caption2)
                            .foregroundStyle(Color.appWarning)
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
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            Link(destination: WidgetDeepLinkURL.lowStock) {
                HStack(spacing: 4) {
                    Image(systemName: "shippingbox")
                        .font(.caption2)
                    Text(widgetLocalizedCount("widget_material_stock_count_format", data.materialStockCount))
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if data.lowStockCount > 0 {
                Link(destination: WidgetDeepLinkURL.lowStock) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text(widgetLocalizedCount("widget_low_stock_count_format", data.lowStockCount))
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appWarning)
            }

            if !riskLinkItems.isEmpty {
                HStack(spacing: 4) {
                    ForEach(riskLinkItems.prefix(2)) { item in
                        Link(destination: item.destination) {
                            Text(item.badgeText)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(item.tint.opacity(0.16))
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(item.tint)
                    }
                }
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
        let riskLinkItems = widgetRiskLinkItems(for: data)

        HStack(alignment: .top, spacing: 12) {
            // 左侧：待办统计
            Link(destination: WidgetDeepLinkURL.todos) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "checklist")
                            .foregroundStyle(Color.appWarning)
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
            }
            .buttonStyle(.plain)
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
                        Link(destination: WidgetDeepLinkURL.project(id: project.id)) {
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
                                    .tint(status.isCompleted ? Color.appSuccess : Color.appWarning)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !riskLinkItems.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(riskLinkItems.prefix(3)) { item in
                            Link(destination: item.destination) {
                                Text(item.badgeText)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(item.tint.opacity(0.16))
                                    )
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(item.tint)
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
        let riskLinkItems = widgetRiskLinkItems(for: data)

        VStack(alignment: .leading, spacing: 10) {
            // 顶部摘要行
            HStack(spacing: 16) {
                Link(destination: WidgetDeepLinkURL.todos) {
                    SummaryBlock(
                        icon: "checklist",
                        value: "\(data.pendingTodos)",
                        label: String(localized: "widget_label_todo"),
                        color: Color.appWarning
                    )
                }
                .buttonStyle(.plain)
                Link(destination: WidgetDeepLinkURL.lowStock) {
                    SummaryBlock(
                        icon: "shippingbox",
                        value: "\(data.materialStockCount)",
                        label: String(localized: "widget_label_material_types"),
                        color: .blue
                    )
                }
                .buttonStyle(.plain)
                if data.lowStockCount > 0 {
                    Link(destination: WidgetDeepLinkURL.lowStock) {
                        SummaryBlock(
                            icon: "exclamationmark.triangle.fill",
                            value: "\(data.lowStockCount)",
                            label: String(localized: "widget_label_low_stock"),
                            color: Color.appRisk
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            if !riskLinkItems.isEmpty {
                HStack(spacing: 8) {
                    ForEach(riskLinkItems) { item in
                        Link(destination: item.destination) {
                            Text(item.badgeText)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(item.tint.opacity(0.16))
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(item.tint)
                    }
                }
            }

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
                    Link(destination: WidgetDeepLinkURL.project(id: project.id)) {
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
                                            .fill(isCompleted ? Color.appSuccess.opacity(0.15) : Color.appWarning.opacity(0.15))
                                    )
                                    .foregroundStyle(isCompleted ? Color.appSuccess : Color.appWarning)
                            }

                            HStack(spacing: 12) {
                                ProgressView(value: project.progress)
                                    .tint(isCompleted ? Color.appSuccess : Color.appWarning)
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
                    .buttonStyle(.plain)
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

private enum WidgetDeepLinkURL {
    static let todos = staticURL("sitekeeper://widget/todos")
    static let lowStock = staticURL("sitekeeper://widget/low-stock")
    static let missingReceipt = staticURL("sitekeeper://widget/missing-receipt")
    static let backupOverdue = staticURL("sitekeeper://widget/backup-overdue")
    static let priceSpike = staticURL("sitekeeper://widget/price-spike")

    static func project(id: UUID) -> URL {
        var components = URLComponents()
        components.scheme = "sitekeeper"
        components.host = "widget"
        components.path = "/project"
        components.queryItems = [URLQueryItem(name: "id", value: id.uuidString)]
        return components.url ?? staticURL("sitekeeper://widget/project")
    }

    private static func staticURL(_ rawValue: String) -> URL {
        URL(string: rawValue) ?? URL(fileURLWithPath: "/")
    }
}

private struct WidgetRiskLinkItem: Identifiable {
    let id: String
    let title: String
    let count: Int
    let tint: Color
    let destination: URL

    var badgeText: String {
        count > 0 ? "\(title) \(count)" : title
    }
}

private func widgetRiskLinkItems(for data: WidgetExportData) -> [WidgetRiskLinkItem] {
    var items: [WidgetRiskLinkItem] = []
    if data.missingReceiptCount > 0 {
        items.append(
            WidgetRiskLinkItem(
                id: "missing-receipt",
                title: String(localized: "widget_label_missing_receipt"),
                count: data.missingReceiptCount,
                tint: Color.appWarning,
                destination: WidgetDeepLinkURL.missingReceipt
            )
        )
    }
    if data.priceSpikeCount > 0 {
        items.append(
            WidgetRiskLinkItem(
                id: "price-spike",
                title: String(localized: "widget_label_price_spike"),
                count: data.priceSpikeCount,
                tint: Color.appRisk,
                destination: WidgetDeepLinkURL.priceSpike
            )
        )
    }
    if data.backupOverdueCount > 0 {
        items.append(
            WidgetRiskLinkItem(
                id: "backup-overdue",
                title: String(localized: "widget_label_backup_overdue"),
                count: 0,
                tint: .purple,
                destination: WidgetDeepLinkURL.backupOverdue
            )
        )
    }
    return items
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

private extension Color {
    static var appWarning: Color { Color(red: 1.0, green: 0.58, blue: 0.0) }
    static var appSuccess: Color { Color(red: 0.20, green: 0.74, blue: 0.35) }
    static var appRisk: Color { Color(red: 0.90, green: 0.26, blue: 0.21) }
}
