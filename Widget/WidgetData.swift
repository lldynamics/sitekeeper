import Foundation

struct WidgetProjectSummary: Codable {
    let id: UUID
    let name: String
    let status: String
    let progress: Double
    let todoCount: Int
}

struct WidgetExportData: Codable {
    let projects: [WidgetProjectSummary]
    let pendingTodos: Int
    let materialStockCount: Int
    let lowStockCount: Int
}

final class WidgetDataStore {
    static let suiteName = "group.com.chengjinfang.sitekeeper"
    static let widgetDataKey = "widget_data"

    static var shared: WidgetExportData {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: widgetDataKey),
              let widgetData = try? JSONDecoder().decode(WidgetExportData.self, from: data)
        else {
            return WidgetExportData(projects: [], pendingTodos: 0, materialStockCount: 0, lowStockCount: 0)
        }
        return widgetData
    }
}
