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
        let signal = widgetPrimarySignal(for: data)

        VStack(alignment: .leading, spacing: 6) {
            WidgetSectionHeader(
                icon: "checklist",
                title: widgetText("widget_label_today_todos")
            )

            Link(destination: WidgetDeepLinkURL.todos) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(data.pendingTodos)")
                        .font(.largeTitle.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(widgetText("widget_pending_items_text"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Link(destination: signal.destination) {
                WidgetCompactSignalRow(
                    icon: signal.icon,
                    title: signal.title,
                    tint: signal.tint
                )
            }
            .buttonStyle(.plain)

            Text(widgetLocalizedUpdate("widget_updated_time_format", WidgetDateFormatters.timeOnly.string(from: entry.date)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
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

        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                WidgetSectionHeader(
                    icon: "calendar",
                    title: widgetText("widget_label_overview")
                )

                Link(destination: WidgetDeepLinkURL.todos) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(data.pendingTodos)")
                            .font(.largeTitle.weight(.bold))
                            .fontDesign(.rounded)
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(widgetText("widget_pending_items_text"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Link(destination: WidgetDeepLinkURL.lowStock) {
                        WidgetCompactSignalRow(
                            icon: data.lowStockCount > 0 ? "shippingbox.fill" : "shippingbox",
                            title: data.lowStockCount > 0
                                ? widgetLocalizedCount("widget_low_stock_count_format", data.lowStockCount)
                                : widgetLocalizedCount("widget_material_stock_count_format", data.materialStockCount),
                            tint: data.lowStockCount > 0 ? Color.appRisk : Color.secondary
                        )
                    }
                    .buttonStyle(.plain)

                    if let firstRisk = riskLinkItems.first {
                        Link(destination: firstRisk.destination) {
                            WidgetCompactSignalRow(
                                icon: firstRisk.icon,
                                title: firstRisk.badgeText,
                                tint: firstRisk.tint
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)

                Text(widgetLocalizedUpdate("widget_updated_time_format", WidgetDateFormatters.timeOnly.string(from: entry.date)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(width: 108, alignment: .leading)

            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 7) {
                WidgetSectionHeader(
                    icon: "hammer",
                    title: widgetText("widget_label_focus_projects")
                )

                if data.projects.isEmpty {
                    WidgetEmptyState(text: widgetText("widget_no_active_projects"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(data.projects.prefix(3), id: \.id) { project in
                        WidgetProjectProgressRow(project: project, showsStatus: false, showsTodo: false)
                    }
                    Spacer(minLength: 0)
                }
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
        let riskTotal = widgetRiskTotal(for: data)

        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center) {
                WidgetSectionHeader(
                    icon: "square.grid.2x2",
                    title: widgetText("widget_label_overview")
                )
                Spacer(minLength: 8)
                Text(widgetLocalizedUpdate("widget_updated_time_format", WidgetDateFormatters.timeOnly.string(from: entry.date)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Link(destination: WidgetDeepLinkURL.todos) {
                    WidgetSummaryTile(
                        icon: "checklist",
                        value: "\(data.pendingTodos)",
                        label: widgetText("widget_label_todo"),
                        tint: Color.appWarning
                    )
                }
                .buttonStyle(.plain)

                Link(destination: WidgetDeepLinkURL.lowStock) {
                    WidgetSummaryTile(
                        icon: data.lowStockCount > 0 ? "shippingbox.fill" : "shippingbox",
                        value: "\(data.lowStockCount > 0 ? data.lowStockCount : data.materialStockCount)",
                        label: data.lowStockCount > 0
                            ? widgetText("widget_label_low_stock")
                            : widgetText("widget_label_material_types"),
                        tint: data.lowStockCount > 0 ? Color.appRisk : Color.blue
                    )
                }
                .buttonStyle(.plain)

                Link(destination: riskTotal > 0 ? (riskLinkItems.first?.destination ?? WidgetDeepLinkURL.todos) : WidgetDeepLinkURL.todos) {
                    WidgetSummaryTile(
                        icon: riskTotal > 0 ? "exclamationmark.triangle.fill" : "hammer",
                        value: "\(riskTotal > 0 ? riskTotal : data.projects.count)",
                        label: riskTotal > 0
                            ? widgetText("widget_label_risk")
                            : widgetText("widget_label_projects"),
                        tint: riskTotal > 0 ? Color.appRisk : Color.appSuccess
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(height: 52)

            if !riskLinkItems.isEmpty {
                HStack(spacing: 6) {
                    ForEach(riskLinkItems.prefix(3)) { item in
                        Link(destination: item.destination) {
                            WidgetRiskPill(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.10))
                .frame(height: 1)

            WidgetSectionHeader(
                icon: "hammer",
                title: widgetText("widget_label_focus_projects")
            )

            if data.projects.isEmpty {
                WidgetEmptyState(text: widgetText("widget_no_active_projects"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(data.projects.prefix(4), id: \.id) { project in
                        WidgetProjectProgressRow(project: project, showsStatus: true, showsTodo: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WidgetSectionHeader: View {
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

private struct WidgetCompactSignalRow: View {
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

private struct WidgetSummaryTile: View {
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
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
    }
}

private struct WidgetRiskPill: View {
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

private struct WidgetProjectProgressRow: View {
    let project: WidgetProjectSummary
    let showsStatus: Bool
    let showsTodo: Bool

    var body: some View {
        let status = WidgetProjectStatus.parse(project.status)
        let tint = widgetProjectTint(for: status)

        Link(destination: WidgetDeepLinkURL.project(id: project.id)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.caption.weight(.medium))
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

private struct WidgetEmptyState: View {
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

private struct WidgetSignal {
    let icon: String
    let title: String
    let tint: Color
    let destination: URL
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
    let format = widgetText(key)
    return String.localizedStringWithFormat(format, count)
}

private func widgetLocalizedUpdate(_ key: String, _ value: String) -> String {
    let format = widgetText(key)
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
    let icon: String
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
                title: widgetText("widget_label_missing_receipt"),
                count: data.missingReceiptCount,
                icon: "doc.text",
                tint: Color.appWarning,
                destination: WidgetDeepLinkURL.missingReceipt
            )
        )
    }
    if data.priceSpikeCount > 0 {
        items.append(
            WidgetRiskLinkItem(
                id: "price-spike",
                title: widgetText("widget_label_price_spike"),
                count: data.priceSpikeCount,
                icon: "chart.line.uptrend.xyaxis",
                tint: Color.appRisk,
                destination: WidgetDeepLinkURL.priceSpike
            )
        )
    }
    if data.backupOverdueCount > 0 {
        items.append(
            WidgetRiskLinkItem(
                id: "backup-overdue",
                title: widgetText("widget_label_backup_overdue"),
                count: data.backupOverdueCount,
                icon: "icloud.slash",
                tint: .purple,
                destination: WidgetDeepLinkURL.backupOverdue
            )
        )
    }
    return items
}

private func widgetPrimarySignal(for data: WidgetExportData) -> WidgetSignal {
    if data.lowStockCount > 0 {
        return WidgetSignal(
            icon: "shippingbox.fill",
            title: widgetLocalizedCount("widget_low_stock_count_format", data.lowStockCount),
            tint: Color.appRisk,
            destination: WidgetDeepLinkURL.lowStock
        )
    }
    if let risk = widgetRiskLinkItems(for: data).first {
        return WidgetSignal(
            icon: risk.icon,
            title: risk.badgeText,
            tint: risk.tint,
            destination: risk.destination
        )
    }
    return WidgetSignal(
        icon: "shippingbox",
        title: widgetLocalizedCount("widget_material_stock_count_format", data.materialStockCount),
        tint: Color.secondary,
        destination: WidgetDeepLinkURL.lowStock
    )
}

private func widgetRiskTotal(for data: WidgetExportData) -> Int {
    data.missingReceiptCount + data.priceSpikeCount + data.backupOverdueCount
}

private func widgetClampedProgress(_ value: Double) -> Double {
    min(max(value, 0), 1)
}

private func widgetProjectTint(for status: WidgetProjectStatus) -> Color {
    switch status {
    case .completed, .settled, .archived:
        return Color.appSuccess
    case .paused:
        return Color.secondary
    case .active, .unknown:
        return Color.appWarning
    }
}

private func widgetProjectStatusText(_ status: WidgetProjectStatus) -> String {
    switch status {
    case .active:
        return widgetText("widget_project_status_active")
    case .paused:
        return widgetText("widget_project_status_paused")
    case .completed:
        return widgetText("widget_project_status_completed")
    case .settled:
        return widgetText("widget_project_status_settled")
    case .archived:
        return widgetText("widget_project_status_archived")
    case .unknown:
        return widgetText("widget_project_status_unknown")
    }
}

private func widgetText(_ key: String) -> String {
    WidgetLocalizedText.string(for: key)
}

enum WidgetLocalizedText {
    static func string(for key: String) -> String {
        let isChinese = WidgetDataStore.languageCode.lowercased().hasPrefix("zh")
        switch key {
        case "widget_placeholder_project_primary":
            return isChinese ? "金方花园" : "Garden Site"
        case "widget_placeholder_project_secondary":
            return isChinese ? "翰林府邸" : "Hanlin Residence"
        case "widget_storage_app_group_unavailable_format":
            return isChinese ? "Widget App Group 不可用：%@" : "Widget App Group unavailable: %@"
        case "widget_material_stock_count_format":
            return isChinese ? "%d 种材料" : "%d materials"
        case "widget_low_stock_count_format":
            return isChinese ? "%d 种不足" : "%d low stock"
        case "widget_project_todo_count_format":
            return isChinese ? "%d 项待办" : "%d pending"
        case "widget_updated_time_format":
            return isChinese ? "更新 %@" : "Updated %@"
        case "widget_updated_datetime_format":
            return isChinese ? "更新时间 %@" : "Updated %@"
        case "widget_label_todo":
            return isChinese ? "待办" : "To-do"
        case "widget_label_today_todos":
            return isChinese ? "今日待办" : "Today"
        case "widget_label_project_progress":
            return isChinese ? "项目进度" : "Progress"
        case "widget_label_material_types":
            return isChinese ? "材料种类" : "Materials"
        case "widget_label_low_stock":
            return isChinese ? "库存不足" : "Low Stock"
        case "widget_label_missing_receipt":
            return isChinese ? "缺票" : "Missing Receipt"
        case "widget_label_price_spike":
            return isChinese ? "价格异动" : "Price Spike"
        case "widget_label_backup_overdue":
            return isChinese ? "备份超期" : "Backup Overdue"
        case "widget_pending_items_text":
            return isChinese ? "项待处理" : "pending"
        case "widget_no_active_projects":
            return isChinese ? "暂无进行中的项目" : "No active projects"
        case "widget_project_status_active":
            return isChinese ? "进行中" : "Active"
        case "widget_project_status_paused":
            return isChinese ? "暂停" : "Paused"
        case "widget_project_status_completed":
            return isChinese ? "已完成" : "Completed"
        case "widget_project_status_settled":
            return isChinese ? "已结算" : "Settled"
        case "widget_project_status_archived":
            return isChinese ? "已归档" : "Archived"
        case "widget_project_status_unknown":
            return isChinese ? "未知" : "Unknown"
        case "widget_label_overview":
            return isChinese ? "今日概览" : "Overview"
        case "widget_label_focus_projects":
            return isChinese ? "重点项目" : "Key Projects"
        case "widget_label_risk":
            return isChinese ? "风险" : "Risk"
        case "widget_label_projects":
            return isChinese ? "项目" : "Projects"
        default:
            return key
        }
    }
}

private extension Color {
    static var appWarning: Color { Color(red: 1.0, green: 0.58, blue: 0.0) }
    static var appSuccess: Color { Color(red: 0.20, green: 0.74, blue: 0.35) }
    static var appRisk: Color { Color(red: 0.90, green: 0.26, blue: 0.21) }
}
