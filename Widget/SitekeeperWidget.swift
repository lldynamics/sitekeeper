import WidgetKit
import SwiftUI

@main
struct SitekeeperWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        SitekeeperWidget()
    }
}

struct SitekeeperProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(
            date: Date(),
            data: WidgetExportData(
                projects: [
                    WidgetProjectSummary(id: UUID(), name: "金方花园", status: "进行中", progress: 0.65, todoCount: 3),
                    WidgetProjectSummary(id: UUID(), name: "翰林府邸", status: "进行中", progress: 0.32, todoCount: 5)
                ],
                pendingTodos: 8,
                materialStockCount: 42,
                lowStockCount: 3,
                lastUpdatedAt: Date().timeIntervalSince1970
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        let data = WidgetDataStore.shared
        let entry = WidgetEntry(date: data.lastUpdatedDate ?? Date(), data: data)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let data = WidgetDataStore.shared
        let entry = WidgetEntry(date: data.lastUpdatedDate ?? Date(), data: data)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetExportData
}

struct SitekeeperWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: SitekeeperProvider.Entry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}

struct SitekeeperWidget: Widget {
    let kind: String = "SitekeeperWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SitekeeperProvider()) { entry in
            SitekeeperWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("工地掌柜")
        .description("今日待办、项目进度、材料库存一目了然")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
