import SwiftUI

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

            Text(widgetLocalizedUpdate("widget_updated_time_format", WidgetDateFormatters.timeOnly.string(from: entry.lastUpdatedDate)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

                Text(widgetLocalizedUpdate("widget_updated_time_format", WidgetDateFormatters.timeOnly.string(from: entry.lastUpdatedDate)))
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

        let projectLimit = riskLinkItems.isEmpty ? 4 : 3

        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center) {
                WidgetSectionHeader(
                    icon: "square.grid.2x2",
                    title: widgetText("widget_label_overview")
                )
                Spacer(minLength: 8)
                Text(widgetLocalizedUpdate("widget_updated_time_format", WidgetDateFormatters.timeOnly.string(from: entry.lastUpdatedDate)))
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
            .frame(height: 48)

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
                    ForEach(data.projects.prefix(projectLimit), id: \.id) { project in
                        WidgetProjectProgressRow(project: project, showsStatus: true, showsTodo: true, compact: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
