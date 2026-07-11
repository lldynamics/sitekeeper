import Foundation
import SwiftUI

struct WidgetSignal {
    let icon: String
    let title: String
    let tint: Color
    let destination: URL
}

enum WidgetDateFormatters {
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

func widgetLocalizedCount(_ key: String, _ count: Int) -> String {
    let format = widgetText(key)
    return String.localizedStringWithFormat(format, count)
}

func widgetLocalizedUpdate(_ key: String, _ value: String) -> String {
    let format = widgetText(key)
    return String.localizedStringWithFormat(format, value)
}

enum WidgetDeepLinkURL {
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

struct WidgetRiskLinkItem: Identifiable {
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

func widgetRiskLinkItems(for data: WidgetExportData) -> [WidgetRiskLinkItem] {
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

func widgetPrimarySignal(for data: WidgetExportData) -> WidgetSignal {
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

func widgetRiskTotal(for data: WidgetExportData) -> Int {
    data.missingReceiptCount + data.priceSpikeCount + data.backupOverdueCount
}

func widgetClampedProgress(_ value: Double) -> Double {
    min(max(value, 0), 1)
}

func widgetProjectTint(for status: WidgetProjectStatus) -> Color {
    switch status {
    case .completed, .settled, .archived:
        return Color.appSuccess
    case .paused:
        return Color.secondary
    case .active, .unknown:
        return Color.appWarning
    }
}

func widgetProjectStatusText(_ status: WidgetProjectStatus) -> String {
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

func widgetText(_ key: String) -> String {
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
            return isChinese ? "缺票" : "No receipt"
        case "widget_label_price_spike":
            return isChinese ? "价格异动" : "Price Spike"
        case "widget_label_backup_overdue":
            return isChinese ? "备份超期" : "Backup"
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

extension Color {
    static var appWarning: Color { Color(red: 1.0, green: 0.58, blue: 0.0) }
    static var appSuccess: Color { Color(red: 0.20, green: 0.74, blue: 0.35) }
    static var appRisk: Color { Color(red: 0.90, green: 0.26, blue: 0.21) }
}
