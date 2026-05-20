import SwiftUI

struct ProjectTimelineItem: Identifiable {
    let id: String
    let date: String
    let type: String
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    /// 点击时间线条目时应进入的项目详情模块。
    let targetMode: ProjectDetailMode

    init(
        id: String,
        date: String,
        type: String,
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        targetMode: ProjectDetailMode = .timeline
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.targetMode = targetMode
    }
}

enum ProjectTimelineBuilder {
    static func makeItems(
        logs: [DailyLog],
        progress: [ProgressTask],
        materials: [MaterialItem],
        quotes: [QuoteItem],
        labor: [LaborRecord],
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument],
        warehouseMovements: [ProjectWarehouseMovement],
        quickNotes: [QuickNote],
        siteTodos: [SiteTodo],
        drawings: [ProjectDrawing]
    ) -> [ProjectTimelineItem] {
        var items: [ProjectTimelineItem] = []

        items += logs.map {
            let methodSummary = $0.linkedConstructionMethodIDs.isEmpty ? "" : "关联工艺 \($0.linkedConstructionMethodIDs.count) 条"
            return ProjectTimelineItem(
                id: "log-\($0.id.uuidString)",
                date: $0.date,
                type: String(localized: "日志"),
                title: $0.content.isEmpty ? String(localized: "施工日志") : $0.content,
                subtitle: [
                    $0.weather,
                    $0.workers.isEmpty ? "" : "\($0.workers) \(String(localized: "人"))",
                    $0.photoAttachments.isEmpty ? "" : "\($0.photoAttachments.count) \(String(localized: "张照片"))",
                    methodSummary
                ].filter { !$0.isEmpty }.joined(separator: " · "),
                systemImage: "book.pages.fill",
                tint: .appSuccess,
                targetMode: .records
            )
        }

        items += progress.map {
            ProjectTimelineItem(
                id: "progress-\($0.id.uuidString)",
                date: $0.dueDate.isEmpty ? $0.startDate : $0.dueDate,
                type: String(localized: "进度"),
                title: $0.title,
                subtitle: "\(Int($0.clampedCompletion * 100))% · \($0.startDate)-\($0.dueDate)",
                systemImage: "checklist.checked",
                tint: .appPrimaryAction,
                targetMode: .records
            )
        }

        items += siteTodos.map {
            let methodSummary = $0.linkedConstructionMethodIDs.isEmpty ? "" : "关联工艺 \($0.linkedConstructionMethodIDs.count) 条"
            return ProjectTimelineItem(
                id: "todo-\($0.id.uuidString)",
                date: $0.completedAt ?? $0.dueDate,
                type: String(localized: "待办"),
                title: $0.title,
                subtitle: [
                    $0.owner,
                    $0.priority.displayName,
                    $0.isDone ? String(localized: "已完成") : String(localized: "未完成"),
                    methodSummary
                ].filter { !$0.isEmpty }.joined(separator: " · "),
                systemImage: $0.isDone ? "checkmark.circle.fill" : "checklist",
                tint: $0.isDone ? .appSuccess : .appPrimaryAction,
                targetMode: .records
            )
        }

        items += materials.map {
            ProjectTimelineItem(
                id: "material-\($0.id.uuidString)",
                date: $0.arrivalDate.isEmpty ? "" : $0.arrivalDate,
                type: String(localized: "材料"),
                title: $0.name,
                subtitle: [$0.specification, "\($0.quantity)\($0.unit)", $0.purchaseStatus.displayName].filter { !$0.isEmpty }.joined(separator: " · "),
                systemImage: "shippingbox.fill",
                tint: .appPrimaryAction,
                targetMode: .finance
            )
        }

        items += drawings.map {
            ProjectTimelineItem(
                id: "drawing-\($0.id.uuidString)",
                date: $0.importedAt,
                type: String(localized: "图纸"),
                title: $0.name,
                subtitle: [$0.version, $0.fileType.uppercased(), $0.isCurrentVersion ? String(localized: "当前版本") : String(localized: "历史版本")].filter { !$0.isEmpty }.joined(separator: " · "),
                systemImage: "doc.richtext",
                tint: .appDoc,
                targetMode: .assets
            )
        }

        items += quotes.map {
            ProjectTimelineItem(
                id: "quote-\($0.id.uuidString)",
                date: $0.customerConfirmedDate,
                type: String(localized: "预结算"),
                title: $0.name,
                subtitle: "\($0.status.displayName) · \(ReportBuilder.money(ReportBuilder.quoteGrandTotal($0)))",
                systemImage: "doc.text.fill",
                tint: .appPrimaryAction,
                targetMode: .finance
            )
        }

        items += labor.map {
            ProjectTimelineItem(
                id: "labor-\($0.id.uuidString)",
                date: $0.date,
                type: String(localized: "人工"),
                title: $0.workType.isEmpty ? String(localized: "人工记录") : $0.workType,
                subtitle: "\($0.workers) \(String(localized: "人")) · \($0.hours) \(String(localized: "小时")) · \(ReportBuilder.money(ReportBuilder.laborLineTotal($0)))",
                systemImage: "person.2.fill",
                tint: .appSuccess,
                targetMode: .finance
            )
        }

        items += financialRecords.map {
            ProjectTimelineItem(
                id: "finance-\($0.id.uuidString)",
                date: $0.date,
                type: String(localized: "记账"),
                title: "\($0.normalizedDirection.displayName) \(ReportBuilder.money($0.amountValue.doubleValue))",
                subtitle: [$0.normalizedCategory.displayName, $0.normalizedStatus.displayName, $0.counterparty].filter { !$0.isEmpty }.joined(separator: " · "),
                systemImage: "receipt.fill",
                tint: $0.normalizedDirection == .income ? .appSuccess : .appRisk,
                targetMode: .finance
            )
        }

        items += documents.map {
            let methodSummary = $0.linkedConstructionMethodIDs.isEmpty ? "" : "关联工艺 \($0.linkedConstructionMethodIDs.count) 条"
            return ProjectTimelineItem(
                id: "document-\($0.id.uuidString)",
                date: $0.createdAt,
                type: String(localized: "资料"),
                title: $0.title,
                subtitle: [
                    "\($0.category.displayName) · \($0.pageCount) \(String(localized: "页"))",
                    methodSummary
                ].filter { !$0.isEmpty }.joined(separator: " · "),
                systemImage: "doc.viewfinder.fill",
                tint: .appDoc,
                targetMode: .assets
            )
        }

        items += warehouseMovements.map {
            ProjectTimelineItem(
                id: "warehouse-\($0.id.uuidString)",
                date: $0.date,
                type: String(localized: "仓库"),
                title: "\($0.normalizedMovementType.displayName) \($0.materialName)",
                subtitle: "\($0.quantity)\($0.unit) · \($0.counterparty)",
                systemImage: "shippingbox.and.arrow.backward.fill",
                tint: .appPrimaryAction,
                targetMode: .finance
            )
        }

        items += quickNotes.map {
            ProjectTimelineItem(
                id: "note-\($0.id.uuidString)",
                date: $0.createdAt,
                type: String(localized: "随手记"),
                title: $0.title.isEmpty ? String(localized: "随手记") : $0.title,
                subtitle: $0.content,
                systemImage: "square.and.pencil",
                tint: .appPrimaryAction,
                targetMode: .records
            )
        }

        return items.sorted { lhs, rhs in
            let lhsDate = timelineDate(lhs.date)
            let rhsDate = timelineDate(rhs.date)
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id > rhs.id
        }
    }

    private static func timelineDate(_ text: String) -> Date {
        Formatters.parseDateOrDateTime(text) ?? .distantPast
    }
}

struct ProjectTimelineView: View {
    let items: [ProjectTimelineItem]
    var onSelect: ((ProjectTimelineItem) -> Void)?

    var body: some View {
        ForEach(items) { item in
            if let onSelect {
                Button {
                    onSelect(item)
                } label: {
                    row(item, showsChevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(format: String(localized: "打开%@"), item.targetMode.displayName))
            } else {
                row(item, showsChevron: false)
            }
        }
    }

    private func row(_ item: ProjectTimelineItem, showsChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .foregroundStyle(item.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.type)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.tint)
                    Text(item.date.isEmpty ? String(localized: "未填写日期") : item.date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(item.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(.vertical, 4)
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
        }
        .contentShape(Rectangle())
    }
}

struct ProjectTimelineSectionView: View {
    let items: [ProjectTimelineItem]
    let showsFilters: Bool
    let previewLimit: Int?
    var onSelect: ((ProjectTimelineItem) -> Void)?
    @State private var typeFilter = ProjectTimelineTypeFilter.all
    @State private var rangeFilter: ProjectTimelineRangeFilter = .all
    @State private var showsAllItems = false

    init(
        items: [ProjectTimelineItem],
        showsFilters: Bool = true,
        previewLimit: Int? = nil,
        onSelect: ((ProjectTimelineItem) -> Void)? = nil
    ) {
        self.items = items
        self.showsFilters = showsFilters
        self.previewLimit = previewLimit
        self.onSelect = onSelect
    }

    private var typeOptions: [String] {
        [ProjectTimelineTypeFilter.all] + Array(Set(items.map(\.type))).sorted()
    }

    private var filteredItems: [ProjectTimelineItem] {
        items.filter { item in
            let typeMatches = typeFilter == ProjectTimelineTypeFilter.all || item.type == typeFilter
            return typeMatches && rangeFilter.matches(item)
        }
    }

    private var visibleItems: [ProjectTimelineItem] {
        guard let previewLimit, previewLimit > 0, !showsAllItems else {
            return filteredItems
        }
        return Array(filteredItems.prefix(previewLimit))
    }

    private var canToggleExpand: Bool {
        guard let previewLimit, previewLimit > 0 else { return false }
        return filteredItems.count > previewLimit
    }

    var body: some View {
        Group {
            if showsFilters {
                Section("时间线筛选") {
                    Picker("类型", selection: $typeFilter) {
                        ForEach(typeOptions, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }

                    Picker("时间", selection: $rangeFilter) {
                        ForEach(ProjectTimelineRangeFilter.allCases, id: \.self) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section("项目时间线 (\(filteredItems.count))") {
                if items.isEmpty {
                    ContentUnavailableView(
                        "还没有项目动态",
                        systemImage: "timeline.selection",
                        description: Text("写日志、导入资料、记账或更新进度后，会自动汇总到这里。")
                    )
                } else if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "没有匹配动态",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("调整类型或时间筛选后再查看。")
                    )
                } else {
                    ProjectTimelineView(items: visibleItems, onSelect: onSelect)
                    if canToggleExpand {
                        Button {
                            showsAllItems.toggle()
                        } label: {
                            Label(
                                showsAllItems ? "收起时间线" : "查看全部时间线",
                                systemImage: showsAllItems ? "chevron.up.circle" : "chevron.down.circle"
                            )
                            .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.appPrimaryAction)
                    }
                }
            }
        }
        .onChange(of: typeFilter) { _, _ in
            showsAllItems = false
        }
        .onChange(of: rangeFilter) { _, _ in
            showsAllItems = false
        }
    }
}

private enum ProjectTimelineTypeFilter {
    static let all = "全部"
}

private enum ProjectTimelineRangeFilter: String, CaseIterable {
    case all
    case sevenDays
    case thirtyDays

    var displayName: String {
        switch self {
        case .all: "全部"
        case .sevenDays: "7天"
        case .thirtyDays: "30天"
        }
    }

    func matches(_ item: ProjectTimelineItem) -> Bool {
        guard self != .all else { return true }
        guard let date = Formatters.parseDateOrDateTime(item.date) else { return false }
        let days: Int = self == .sevenDays ? 7 : 30
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return date >= Calendar.current.startOfDay(for: start)
    }
}
