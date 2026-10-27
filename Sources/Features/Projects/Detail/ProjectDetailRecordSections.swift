import SwiftUI

struct ProjectLogSectionView<LogRow: View>: View {
    let logs: [DailyLog]
    let onAddLog: () -> Void
    let logRow: (DailyLog) -> LogRow

    var body: some View {
        ProjectDetailAnchoredSection(String(format: AppLocalization.string("日志 (%lld)"), Int64(logs.count)), anchor: .records) {
            if logs.isEmpty {
                ProjectInlineEmptyState(
                    AppLocalization.string("还没有日志"),
                    systemImage: "book.pages",
                    detail: AppLocalization.string("记录今天的人员、材料和现场照片。")
                )
                Button(action: onAddLog) {
                    Label(AppLocalization.string("写日志"), systemImage: "square.and.pencil")
                }
                .buttonStyle(.appProminent())
            } else {
                Button(action: onAddLog) {
                    Label(AppLocalization.string("写日志"), systemImage: "square.and.pencil")
                }
                ForEach(logs.sorted { $0.date > $1.date }) { log in
                    logRow(log)
                }
            }
        }
    }
}

struct ProjectQuoteSectionView: View {
    let items: [QuoteItem]
    let onAdd: () -> Void
    let onEdit: (QuoteItem) -> Void

    var body: some View {
        Section(String(format: AppLocalization.string("报价 (%lld)"), Int64(items.count))) {
            if items.isEmpty {
                ProjectInlineEmptyState(
                    AppLocalization.string("还没有报价"),
                    systemImage: "doc.text",
                    detail: AppLocalization.string("记录版本、状态和确认金额。")
                )
                Button(action: onAdd) {
                    Label(AppLocalization.string("加报价"), systemImage: "doc.text.fill")
                }
                .buttonStyle(.appProminent())
            } else {
                Button(action: onAdd) {
                    Label(AppLocalization.string("加报价"), systemImage: "doc.text.fill")
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
        [
            item.versionName,
            item.customerConfirmedDate.isEmpty ? "" : String(format: AppLocalization.string("确认 %@"), item.customerConfirmedDate.storageText),
            item.contractAmount.isEmpty ? "" : String(format: AppLocalization.string("转合同 %@"), ReportBuilder.money(item.contractAmount))
        ]
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
    @State private var teamFilter = "__all_teams__"
    @State private var settlementFilter: LaborSettlementFilter = .all

    private let allTeamFilter = "__all_teams__"

    private var filteredItems: [LaborRecord] {
        items.filter { item in
            let teamMatches = teamFilter == allTeamFilter || item.teamName == teamFilter
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
        return [allTeamFilter] + teams.sorted()
    }

    var body: some View {
        Section(String(format: AppLocalization.string("人工 (%lld)"), Int64(items.count))) {
            if items.isEmpty {
                ProjectInlineEmptyState(
                    AppLocalization.string("还没有人工"),
                    systemImage: "person.2",
                    detail: AppLocalization.string("记录班组、工时、单价和结算状态。")
                )
                Button(action: onAdd) {
                    Label(AppLocalization.string("记人工"), systemImage: "person.2.fill")
                }
                .buttonStyle(.appProminent())
            } else {
                Button(action: onAdd) {
                    Label(AppLocalization.string("记人工"), systemImage: "person.2.fill")
                }
                Picker(AppLocalization.string("结算"), selection: $settlementFilter) {
                    ForEach(LaborSettlementFilter.allCases, id: \.self) { filter in
                        Text(filter.displayName).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                if teamOptions.count > 1 {
                    Picker(AppLocalization.string("班组"), selection: $teamFilter) {
                        ForEach(teamOptions, id: \.self) { team in
                            Text(team == allTeamFilter ? AppLocalization.string("全部") : team).tag(team)
                        }
                    }
                }
                if filteredItems.isEmpty {
                    ProjectInlineEmptyState(AppLocalization.string("没有匹配人工"), systemImage: "line.3.horizontal.decrease.circle")
                } else {
                    ForEach(filteredItems) { item in
                        Button {
                            onEdit(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(item.date).font(.callout.weight(.medium))
                                    Spacer()
                                    Text("\(item.workers) \(AppLocalization.string("人")) · \(item.hours) \(item.workloadUnit.displayName)")
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
        if item.unitRate.isPositive {
            tags.append(String(format: AppLocalization.string("单价 %@"), ReportBuilder.money(item.unitRate)))
            tags.append(String(format: AppLocalization.string("金额 %@"), ReportBuilder.money(ReportBuilder.laborLineTotal(item))))
        }
        tags.append(item.isSettled ? AppLocalization.string("已结算") : AppLocalization.string("未结算"))
        return tags
    }
}

struct ProjectProgressSectionView: View {
    let tasks: [ProgressTask]
    let onEdit: (ProgressTask) -> Void

    var body: some View {
        Section(String(format: AppLocalization.string("进度 (%lld)"), Int64(tasks.count))) {
            if tasks.isEmpty {
                ProjectInlineEmptyState(
                    AppLocalization.string("还没有进度任务"),
                    systemImage: "calendar.badge.plus",
                    detail: AppLocalization.string("添加节点后可看完成率和延期风险。")
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
        Section(String(format: AppLocalization.string("照片 (%lld)"), Int64(logs.flatMap(\.photoAttachments).count))) {
            let photoItems = logs.flatMap { log in
                log.photoAttachments.map { ProjectPhotoItem(logId: log.id, date: log.date, photo: $0) }
            }
            if photoItems.isEmpty {
                ProjectInlineEmptyState(
                    AppLocalization.string("还没有现场照片"),
                    systemImage: "photo.on.rectangle.angled",
                    detail: AppLocalization.string("日志或待办里的照片会汇总到这里。")
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
        case .all: AppLocalization.string("全部")
        case .unsettled: AppLocalization.string("未结算")
        case .settled: AppLocalization.string("已结算")
        }
    }
}
