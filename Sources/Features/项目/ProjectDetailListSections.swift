import SwiftUI

struct ProjectLogSectionView<LogRow: View>: View {
    let logs: [DailyLog]
    let onAddLog: () -> Void
    let logRow: (DailyLog) -> LogRow

    var body: some View {
        Group {
            Section("日志操作") {
                Button(action: onAddLog) {
                    Label("写施工日志", systemImage: "square.and.pencil")
                }
            }

            Section("施工日志 (\(logs.count))") {
                if logs.isEmpty {
                    ContentUnavailableView(
                        "暂无施工日志",
                        systemImage: "book.pages",
                        description: Text("记录今日施工内容、人员、材料和现场照片。")
                    )
                    Button(action: onAddLog) {
                        Label("写施工日志", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    ForEach(logs.sorted { $0.date > $1.date }) { log in
                        logRow(log)
                    }
                }
            }
        }
    }
}

struct ProjectMaterialSectionView: View {
    let items: [MaterialItem]
    let useMetric: Bool
    let onAdd: () -> Void
    let onEdit: (MaterialItem) -> Void

    var body: some View {
        Group {
            Section("材料操作") {
                Button(action: onAdd) {
                    Label("添加材料", systemImage: "shippingbox.fill")
                }
            }

            Section("材料清单 (\(items.count))") {
                if items.isEmpty {
                    ContentUnavailableView(
                        "暂无材料",
                        systemImage: "shippingbox",
                        description: Text("记录材料名称、规格、品牌、供应商和采购状态。")
                    )
                    Button(action: onAdd) {
                        Label("添加材料", systemImage: "shippingbox.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    ForEach(items) { item in
                        Button {
                            onEdit(item)
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.name).font(.callout.weight(.medium))
                                    Text("\(UnitDisplay.quantityWithUnit(item.quantity, unit: item.unit, useMetric: useMetric)) × \(ReportBuilder.money(ReportBuilder.number(item.unitPrice)))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    FlowTagLine(tags: materialTags(for: item))
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 5) {
                                    Text(ReportBuilder.money(ReportBuilder.materialLineTotal(item)))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.orange)
                                    Text(item.purchaseStatus)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(materialStatusColor(item.purchaseStatus))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(materialStatusColor(item.purchaseStatus).opacity(0.12), in: Capsule())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func materialTags(for item: MaterialItem) -> [String] {
        [item.specification, item.brand, item.supplier, item.arrivalDate.isEmpty ? "" : "进场 \(item.arrivalDate)"]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func materialStatusColor(_ status: String) -> Color {
        switch MaterialPurchaseStatus(rawValue: status) {
        case .notPurchased: return .gray
        case .purchased: return .blue
        case .arrived: return .green
        case .used: return .orange
        case nil: return .secondary
        }
    }
}

struct ProjectQuoteSectionView: View {
    let items: [QuoteItem]
    let onAdd: () -> Void
    let onEdit: (QuoteItem) -> Void

    var body: some View {
        Group {
            Section("报价操作") {
                Button(action: onAdd) {
                    Label("添加报价", systemImage: "doc.text.fill")
                }
            }

            Section("报价明细 (\(items.count))") {
                if items.isEmpty {
                    ContentUnavailableView(
                        "暂无报价",
                        systemImage: "doc.text",
                        description: Text("记录报价版本、状态、确认日期和转合同金额。")
                    )
                    Button(action: onAdd) {
                        Label("添加报价", systemImage: "doc.text.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    ForEach(items) { item in
                        Button {
                            onEdit(item)
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.name).font(.callout.weight(.medium))
                                    Text("¥\(item.unitPrice) × \(item.quantity) \(item.unit)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    FlowTagLine(tags: quoteTags(for: item))
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 5) {
                                    Text(ReportBuilder.money(ReportBuilder.quoteGrandTotal(item)))
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.orange)
                                    Text(item.status)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(quoteStatusColor(item.status))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(quoteStatusColor(item.status).opacity(0.12), in: Capsule())
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func quoteTags(for item: QuoteItem) -> [String] {
        [item.versionName, item.customerConfirmedDate.isEmpty ? "" : "确认 \(item.customerConfirmedDate)", item.contractAmount.isEmpty ? "" : "转合同 \(ReportBuilder.money(ReportBuilder.number(item.contractAmount)))"]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func quoteStatusColor(_ status: String) -> Color {
        switch QuoteStatus(rawValue: status) {
        case .draft: return .gray
        case .sent: return .blue
        case .confirmed: return .green
        case nil: return .secondary
        }
    }
}

struct ProjectLaborSectionView: View {
    let items: [LaborRecord]
    let onAdd: () -> Void
    let onEdit: (LaborRecord) -> Void
    @State private var teamFilter = "全部"
    @State private var settlementFilter: LaborSettlementFilter = .all

    private var filteredItems: [LaborRecord] {
        items.filter { item in
            let teamMatches = teamFilter == "全部" || item.teamName == teamFilter
            let settlementMatches: Bool = {
                switch settlementFilter {
                case .all: return true
                case .settled: return item.isSettled
                case .unsettled: return !item.isSettled
                }
            }()
            return teamMatches && settlementMatches
        }
    }

    private var teamOptions: [String] {
        let teams = Set(items.map(\.teamName).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return ["全部"] + teams.sorted()
    }

    var body: some View {
        Group {
            Section("人工操作") {
                Button(action: onAdd) {
                    Label("记人工", systemImage: "person.2.fill")
                }
            }

            Section("人工记录 (\(items.count))") {
                if items.isEmpty {
                    ContentUnavailableView(
                        "暂无人工记录",
                        systemImage: "person.2",
                        description: Text("记录工种、班组、人数、工时、单价和结算状态。")
                    )
                    Button(action: onAdd) {
                        Label("记人工", systemImage: "person.2.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                } else {
                    Picker("结算", selection: $settlementFilter) {
                        ForEach(LaborSettlementFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    if teamOptions.count > 1 {
                        Picker("班组", selection: $teamFilter) {
                            ForEach(teamOptions, id: \.self) { team in
                                Text(team).tag(team)
                            }
                        }
                    }
                    if filteredItems.isEmpty {
                        Text("当前筛选下暂无人工记录。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredItems) { item in
                            Button {
                                onEdit(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(item.date).font(.callout.weight(.medium))
                                        Spacer()
                                        Text("\(item.workers) 人 · \(item.hours)h")
                                            .font(.caption.weight(.semibold))
                                    }
                                    FlowTagLine(tags: laborTags(for: item))
                                    if !item.note.isEmpty {
                                        Text(item.note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    private func laborTags(for item: LaborRecord) -> [String] {
        var tags = [String]()
        if !item.workType.isEmpty { tags.append(item.workType) }
        if !item.teamName.isEmpty { tags.append(item.teamName) }
        if ReportBuilder.number(item.unitRate) > 0 {
            tags.append("单价 \(ReportBuilder.money(ReportBuilder.number(item.unitRate)))")
            tags.append("金额 \(ReportBuilder.money(ReportBuilder.laborLineTotal(item)))")
        }
        tags.append(item.isSettled ? "已结算" : "未结算")
        return tags
    }
}

struct ProjectProgressSectionView: View {
    let tasks: [ProgressTask]
    let onEdit: (ProgressTask) -> Void

    var body: some View {
        Section("进度任务 (\(tasks.count))") {
            if tasks.isEmpty {
                Text("暂无进度任务").foregroundStyle(.secondary)
            } else {
                ForEach(tasks) { task in
                    Button {
                        onEdit(task)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(task.title).font(.callout.weight(.medium))
                                Spacer()
                                Text("\(Int(task.clampedCompletion * 100))%")
                                    .font(.caption.weight(.semibold))
                            }
                            ProgressView(value: task.clampedCompletion)
                            Text("\(task.startDate) → \(task.dueDate)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ProjectPhotoSectionView: View {
    let logs: [DailyLog]
    let onOpen: (ProjectPhotoContext) -> Void

    var body: some View {
        Section("照片 (\(logs.flatMap(\.photoAttachments).count))") {
            let photoItems = logs.flatMap { log in
                log.photoAttachments.map { ProjectPhotoItem(logId: log.id, date: log.date, photo: $0) }
            }
            if photoItems.isEmpty {
                Text("暂无照片").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 160), spacing: 8)], spacing: 10) {
                    ForEach(photoItems) { item in
                        Button {
                            onOpen(ProjectPhotoContext(logId: item.logId, photoId: item.photo.id, legacyFileName: item.photo.fileName))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                if let image = PhotoStorage.thumbnail(for: item.photo.fileName) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .aspectRatio(1, contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .clipped()
                                }
                                Text(item.photo.tag)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.blue)
                                Text(item.date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private enum LaborSettlementFilter: String, CaseIterable {
    case all
    case unsettled
    case settled

    var displayName: String {
        switch self {
        case .all: "全部"
        case .unsettled: "未结算"
        case .settled: "已结算"
        }
    }
}

private struct FlowTagLine: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    tagViews
                }
                VStack(alignment: .leading, spacing: 4) {
                    tagViews
                }
            }
        }
    }

    @ViewBuilder
    private var tagViews: some View {
        ForEach(tags, id: \.self) { tag in
            Text(tag)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct ProjectDrawingSectionView: View {
    @Binding var drawingFilter: DrawingListFilter
    let relatedDrawings: [ProjectDrawing]
    let filteredDrawings: [ProjectDrawing]
    let icon: (String) -> String
    let onImportDrawing: () -> Void
    let onEdit: (ProjectDrawing) -> Void
    let onTimeline: (ProjectDrawing) -> Void
    let onPreview: (ProjectDrawing) -> Void
    let onDelete: (ProjectDrawing) -> Void

    var body: some View {
        Section("图纸操作") {
            Button(action: onImportDrawing) {
                Label("导入图纸", systemImage: "doc.viewfinder.fill")
            }
        }

        Section("图纸 (\(relatedDrawings.count))") {
            Picker("筛选", selection: $drawingFilter) {
                ForEach(DrawingListFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            if relatedDrawings.isEmpty {
                ContentUnavailableView(
                    "暂无图纸",
                    systemImage: "doc.viewfinder",
                    description: Text("导入 PDF、DWG 或 DXF 后，可在这里预览和管理。")
                )
                Button(action: onImportDrawing) {
                    Label("导入图纸", systemImage: "doc.viewfinder.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            } else if filteredDrawings.isEmpty {
                Text("当前筛选下暂无图纸。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredDrawings) { drawing in
                    Button {
                        onEdit(drawing)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: icon(drawing.fileType))
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(drawing.name)
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(drawing.version)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.thinMaterial, in: Capsule())
                                    if drawing.isCurrentVersion {
                                        Text("当前版")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.green)
                                    }
                                }
                                Text("\(drawing.fileType.uppercased()) · \(drawing.importedAt)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if !drawing.relatedLogDate.isEmpty {
                                    Text("关联日志: \(drawing.relatedLogDate)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if drawing.issueStatus != DrawingIssueStatus.none.rawValue {
                                    Text("状态: \(drawing.issueStatus)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.orange)
                                }
                                if !drawing.issueNote.isEmpty {
                                    Text("问题: \(drawing.issueNote)")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                        .lineLimit(1)
                                }
                                if !drawing.note.isEmpty {
                                    Text(drawing.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            onTimeline(drawing)
                        } label: {
                            Label("查看版本时间线", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        }
                        Button {
                            onPreview(drawing)
                        } label: {
                            Label("预览图纸", systemImage: "eye")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            onDelete(drawing)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            onPreview(drawing)
                        } label: {
                            Label("预览", systemImage: "eye")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
    }
}
