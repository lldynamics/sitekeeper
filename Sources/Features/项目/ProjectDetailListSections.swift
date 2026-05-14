import SwiftUI

struct ProjectInlineEmptyState: View {
    let title: String
    let systemImage: String
    let detail: String?

    init(_ title: String, systemImage: String, detail: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.tight) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

struct ProjectLogSectionView<LogRow: View>: View {
    let logs: [DailyLog]
    let onAddLog: () -> Void
    let logRow: (DailyLog) -> LogRow

    var body: some View {
        Section("日志 (\(logs.count))") {
            if logs.isEmpty {
                ProjectInlineEmptyState(
                    "还没有日志",
                    systemImage: "book.pages",
                    detail: "记录今天的人员、材料和现场照片。"
                )
                Button(action: onAddLog) {
                    Label("写日志", systemImage: "square.and.pencil")
                }
                .buttonStyle(.appProminent())
            } else {
                Button(action: onAddLog) {
                    Label("写日志", systemImage: "square.and.pencil")
                }
                ForEach(logs.sorted { $0.date > $1.date }) { log in
                    logRow(log)
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
        Section("材料 (\(items.count))") {
            if items.isEmpty {
                ProjectInlineEmptyState(
                    "还没有材料",
                    systemImage: "shippingbox",
                    detail: "记录规格、供应商和进场状态。"
                )
                Button(action: onAdd) {
                    Label("加材料", systemImage: "shippingbox.fill")
                }
                .buttonStyle(.appProminent())
            } else {
                Button(action: onAdd) {
                    Label("加材料", systemImage: "shippingbox.fill")
                }
                ForEach(items) { item in
                    Button {
                        onEdit(item)
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name).font(.callout.weight(.medium))
                                Text("\(UnitDisplay.quantityWithUnit(item.quantity, unit: item.unit, useMetric: useMetric)) × \(ReportBuilder.money(item.unitPriceValue.doubleValue))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                FlowTagLine(tags: materialTags(for: item))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 5) {
                                Text(ReportBuilder.money(ReportBuilder.materialLineTotal(item)))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.appFinance)
                                Text(item.purchaseStatus.displayName)
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

    private func materialTags(for item: MaterialItem) -> [String] {
        [item.specification, item.brand, item.supplier, item.arrivalDate.isEmpty ? "" : "进场 \(item.arrivalDate)"]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func materialStatusColor(_ status: MaterialPurchaseStatus) -> Color {
        switch status {
        case .notPurchased: return .appMuted
        case .purchased: return .appDoc
        case .arrived: return .appSuccess
        case .used: return .appWarning
        }
    }
}

struct ProjectQuoteSectionView: View {
    let items: [QuoteItem]
    let onAdd: () -> Void
    let onEdit: (QuoteItem) -> Void

    var body: some View {
        Section("报价 (\(items.count))") {
            if items.isEmpty {
                ProjectInlineEmptyState(
                    "还没有报价",
                    systemImage: "doc.text",
                    detail: "记录版本、状态和确认金额。"
                )
                Button(action: onAdd) {
                    Label("加报价", systemImage: "doc.text.fill")
                }
                .buttonStyle(.appProminent())
            } else {
                Button(action: onAdd) {
                    Label("加报价", systemImage: "doc.text.fill")
                }
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
                                    .foregroundStyle(Color.appFinance)
                                Text(item.status.displayName)
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

    private func quoteTags(for item: QuoteItem) -> [String] {
        [item.versionName, item.customerConfirmedDate.isEmpty ? "" : "确认 \(item.customerConfirmedDate)", item.contractAmount.isEmpty ? "" : "转合同 \(ReportBuilder.money(item.contractAmountValue.doubleValue))"]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func quoteStatusColor(_ status: QuoteStatus) -> Color {
        switch status {
        case .draft: return .appMuted
        case .sent: return .appDoc
        case .confirmed: return .appSuccess
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
        Section("人工 (\(items.count))") {
            if items.isEmpty {
                ProjectInlineEmptyState(
                    "还没有人工",
                    systemImage: "person.2",
                    detail: "记录班组、工时、单价和结算状态。"
                )
                Button(action: onAdd) {
                    Label("记人工", systemImage: "person.2.fill")
                }
                .buttonStyle(.appProminent())
            } else {
                Button(action: onAdd) {
                    Label("记人工", systemImage: "person.2.fill")
                }
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
                    ProjectInlineEmptyState("没有匹配人工", systemImage: "line.3.horizontal.decrease.circle")
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

    private func laborTags(for item: LaborRecord) -> [String] {
        var tags = [String]()
        if !item.workType.isEmpty { tags.append(item.workType) }
        if !item.teamName.isEmpty { tags.append(item.teamName) }
        if item.unitRateValue.isPositive {
            tags.append("单价 \(ReportBuilder.money(item.unitRateValue.doubleValue))")
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
        Section("进度 (\(tasks.count))") {
            if tasks.isEmpty {
                ProjectInlineEmptyState(
                    "还没有进度任务",
                    systemImage: "calendar.badge.plus",
                    detail: "添加节点后可看完成率和延期风险。"
                )
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
                ProjectInlineEmptyState(
                    "还没有现场照片",
                    systemImage: "photo.on.rectangle.angled",
                    detail: "日志或待办里的照片会汇总到这里。"
                )
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 160), spacing: AppSpacing.tight)], spacing: AppSpacing.normal) {
                    ForEach(photoItems) { item in
                        Button {
                            onOpen(ProjectPhotoContext(logId: item.logId, photoId: item.photo.id, legacyFileName: item.photo.fileName))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                AsyncPhotoThumbnailImageView(fileName: item.photo.fileName) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .aspectRatio(1, contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .clipped()
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(uiColor: .secondarySystemFill))
                                        .aspectRatio(1, contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                        .overlay {
                                            Image(systemName: "photo")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                }
                                Text(item.photo.tag.displayName)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color.appDoc)
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
    @State private var showHistoricalDrawings = false

    private var currentVersionDrawings: [ProjectDrawing] {
        filteredDrawings.filter(\.isCurrentVersion)
    }

    private var historicalDrawings: [ProjectDrawing] {
        filteredDrawings.filter { !$0.isCurrentVersion }
    }

    var body: some View {
        Section("图纸 (\(relatedDrawings.count))") {
            Picker("筛选", selection: $drawingFilter) {
                ForEach(DrawingListFilter.allCases, id: \.self) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            if relatedDrawings.isEmpty {
                ProjectInlineEmptyState(
                    "还没有图纸",
                    systemImage: "doc.viewfinder",
                    detail: "支持 DWG、DXF 看图，PDF 作为图纸附件打开。"
                )
                Button(action: onImportDrawing) {
                    Label("导图纸", systemImage: "doc.viewfinder.fill")
                }
                .buttonStyle(.appProminent())
            } else if filteredDrawings.isEmpty {
                Button(action: onImportDrawing) {
                    Label("导图纸", systemImage: "doc.viewfinder.fill")
                }
                ProjectInlineEmptyState("没有匹配图纸", systemImage: "line.3.horizontal.decrease.circle")
            } else {
                Button(action: onImportDrawing) {
                    Label("导图纸", systemImage: "doc.viewfinder.fill")
                }
                if drawingFilter == .all {
                    if !currentVersionDrawings.isEmpty {
                        ForEach(currentVersionDrawings) { drawing in
                            drawingRow(drawing)
                        }
                    }
                    if !historicalDrawings.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showHistoricalDrawings.toggle()
                            }
                        } label: {
                            HStack {
                                Label("历史版本 (\(historicalDrawings.count))", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                Spacer()
                                Image(systemName: showHistoricalDrawings ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        if showHistoricalDrawings {
                            ForEach(historicalDrawings) { drawing in
                                drawingRow(drawing)
                            }
                        }
                    }
                } else {
                    ForEach(filteredDrawings) { drawing in
                        drawingRow(drawing)
                    }
                }
            }
        }
    }

    private func drawingRow(_ drawing: ProjectDrawing) -> some View {
        Button {
            onEdit(drawing)
        } label: {
            HStack(spacing: AppSpacing.normal) {
                Image(systemName: icon(drawing.fileType))
                    .foregroundStyle(Color.appDoc)
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
                                .foregroundStyle(Color.appSuccess)
                        } else {
                            Text("历史版")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("\(drawing.fileType.uppercased()) · \(drawing.importedAt)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if ProjectDetailDrawingHelper.isCADSource(drawing.fileType) {
                        let status = previewStatus(for: drawing)
                        Text(status.text)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(status.isReady ? Color.appSuccess : Color.appWarning)
                        Text("文字：\(drawing.textEncoding.displayName) / \(drawing.textBigFont.displayName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !drawing.relatedLogDate.isEmpty {
                        Text("关联日志: \(drawing.relatedLogDate)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if drawing.issueStatus != .none {
                        Text("状态: \(drawing.issueStatus.displayName)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.appWarning)
                    }
                    if !drawing.issueNote.isEmpty {
                        Text("问题: \(drawing.issueNote)")
                            .font(.caption2)
                            .foregroundStyle(Color.appRisk)
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
            .tint(Color.appDoc)
        }
    }

    private func previewStatus(for drawing: ProjectDrawing) -> (text: String, isReady: Bool) {
        let fileType = drawing.fileType.lowercased()
        if fileType == "dxf" {
            return ("DXF 直览", true)
        }
        if fileType == "pdf" {
            return ("PDF 附件", true)
        }
        if fileType == "dwg" {
            if !CADDrawingCapability.isLibreDWGRendererAvailable() {
                return ("DWG Lite 未接入", false)
            }
            if !CADRendererProvider.isLibreDWGRendererBound {
                return ("DWG Lite 未绑定", false)
            }
            return ("DWG Lite 本地直览", true)
        }
        return ("文件独立打开", true)
    }
}
