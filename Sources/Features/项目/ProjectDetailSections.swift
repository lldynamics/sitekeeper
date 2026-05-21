import SwiftUI

struct ProjectOverviewView<LogRowContent: View>: View {
    let project: Project
    let businessSummary: ProjectBusinessSummary
    let paidAmount: Double
    let unpaidAmount: Double
    let materialCost: Double
    let laborCost: Double
    let estimatedProfit: Double
    let laborHours: String
    let projectBookIncome: Double
    let projectBookExpense: Double
    let logDayCount: Int
    let materialCount: Int
    let contactCount: Int
    let financialCount: Int
    let documentCount: Int
    let documentMissingCategoryCount: Int
    let documentActionCount: Int
    let documentReturnedCount: Int
    let documentArchivedCount: Int
    let recentLogs: [DailyLog]
    let progressTasks: [ProgressTask]
    let todos: [SiteTodo]
    let recentItems: [ProjectTimelineItem]
    let overdueCount: Int
    let missingReceiptCount: Int
    let hasTodayLog: Bool
    let onOpenFinance: () -> Void
    let onOpenFinanceUnsettled: () -> Void
    let onOpenFinanceMissingReceipt: () -> Void
    let onOpenRecords: () -> Void
    let onOpenAssets: () -> Void
    let onOpenLogs: () -> Void
    let onOpenTodos: () -> Void
    let onOpenTimeline: () -> Void
    let onAddLog: () -> Void
    let onEditProgress: (ProgressTask) -> Void
    let onOpenTimelineItem: (ProjectTimelineItem) -> Void
    let logRow: (DailyLog) -> LogRowContent

    var body: some View {
        Group {
            Section(String(localized: "项目入口")) {
                ProjectDetailEntryShortcutsView(entries: compactEntries)
            }

            if !nextStepSuggestions.isEmpty {
                Section(String(localized: "优先处理")) {
                    ProjectNextStepSuggestionsView(
                        suggestions: nextStepSuggestions,
                        onAddLog: onAddLog,
                        onOpenRecords: onOpenRecords,
                        onOpenFinance: onOpenFinance,
                        onOpenAssets: onOpenAssets
                    )
                }
            }
        }
    }

    private var compactEntries: [ProjectDetailEntryShortcut] {
        [
            .init(
                title: String(localized: "现场"),
                subtitle: siteShortcutSubtitle,
                systemImage: "checklist.checked",
                tint: .appSuccess,
                statusColor: siteShortcutColor,
                action: onOpenRecords
            ),
            .init(
                title: String(localized: "资料"),
                subtitle: assetShortcutSubtitle,
                systemImage: "folder.fill",
                tint: .appDoc,
                statusColor: assetShortcutColor,
                action: onOpenAssets
            ),
            .init(
                title: String(localized: "成本"),
                subtitle: financeShortcutSubtitle,
                systemImage: "yensign.circle.fill",
                tint: .appFinance,
                statusColor: financeShortcutColor,
                action: onOpenFinance
            ),
            .init(
                title: String(localized: "时间线"),
                subtitle: timelineShortcutSubtitle,
                systemImage: "clock.arrow.circlepath",
                tint: .appPrimaryAction,
                statusColor: .secondary,
                action: onOpenTimeline
            )
        ]
    }

    private var siteShortcutSubtitle: String {
        if !hasTodayLog {
            return String(localized: "今日日志未填")
        }
        if overdueCount > 0 {
            return String(format: String(localized: "%lld 项延期"), Int64(overdueCount))
        }
        if !todos.isEmpty {
            return String(format: String(localized: "%lld 项待办"), Int64(todos.count))
        }
        return String(localized: "现场正常")
    }

    private var siteShortcutColor: Color {
        if !hasTodayLog || overdueCount > 0 || !todos.isEmpty {
            return .appWarning
        }
        return .appSuccess
    }

    private var assetShortcutSubtitle: String {
        if documentMissingCategoryCount > 0 {
            return String(format: String(localized: "%lld 类缺项"), Int64(documentMissingCategoryCount))
        }
        if documentReturnedCount > 0 {
            return String(format: String(localized: "%lld 份退回"), Int64(documentReturnedCount))
        }
        return countValue(documentCount, unit: String(localized: "份"))
    }

    private var assetShortcutColor: Color {
        documentMissingCategoryCount > 0 || documentReturnedCount > 0 ? .appWarning : .secondary
    }

    private var financeShortcutSubtitle: String {
        if unpaidAmount > 0 {
            return ReportBuilder.money(unpaidAmount)
        }
        if missingReceiptCount > 0 {
            return String(format: String(localized: "%lld 笔缺票"), Int64(missingReceiptCount))
        }
        return countValue(financialCount, unit: String(localized: "笔"))
    }

    private var financeShortcutColor: Color {
        if unpaidAmount > 0 { return .appFinance }
        if missingReceiptCount > 0 { return .appWarning }
        return .secondary
    }

    private var timelineShortcutSubtitle: String {
        if !recentItems.isEmpty {
            return countValue(recentItems.count, unit: String(localized: "条"))
        }
        if contactCount > 0 {
            return countValue(contactCount, unit: String(localized: "人"))
        }
        return String(localized: "暂无动态")
    }

    private var nextStepSuggestions: [ProjectNextStepSuggestion] {
        var suggestions: [ProjectNextStepSuggestion] = []
        if !hasTodayLog {
            suggestions.append(.init(title: String(localized: "补写今日日志"), subtitle: String(localized: "今天还没有施工日志"), systemImage: "book.pages.fill", tint: .appSuccess, action: .addLog))
        }
        if overdueCount > 0 {
            suggestions.append(.init(title: String(localized: "处理延期事项"), subtitle: String(format: String(localized: "%lld 项需要跟进"), Int64(overdueCount)), systemImage: "calendar.badge.exclamationmark", tint: .appRisk, action: .records))
        }
        if unpaidAmount > 0 {
            suggestions.append(.init(title: String(localized: "跟进未收款"), subtitle: ReportBuilder.money(unpaidAmount), systemImage: "yensign.circle.fill", tint: .appFinance, action: .finance))
        }
        if missingReceiptCount > 0 {
            suggestions.append(.init(title: String(localized: "补齐票据资料"), subtitle: String(format: String(localized: "%lld 笔账目缺票"), Int64(missingReceiptCount)), systemImage: "doc.badge.plus", tint: .appDoc, action: .assets))
        }
        if documentMissingCategoryCount > 0 || documentReturnedCount > 0 {
            suggestions.append(.init(
                title: String(localized: "补齐施工资料"),
                subtitle: documentArchiveSuggestionSubtitle,
                systemImage: "folder.badge.plus",
                tint: .appWarning,
                action: .assets
            ))
        }
        if progressTasks.isEmpty {
            suggestions.append(.init(title: String(localized: "添加进度任务"), subtitle: String(localized: "用项目看板跟踪节点"), systemImage: "checklist.checked", tint: .appWarning, action: .records))
        }
        return Array(suggestions.prefix(4))
    }

    private var documentArchiveSuggestionSubtitle: String {
        switch (documentMissingCategoryCount, documentReturnedCount) {
        case let (missing, returned) where missing > 0 && returned > 0:
            return String(format: String(localized: "%1$lld 类缺项 · %2$lld 份退回"), Int64(missing), Int64(returned))
        case let (missing, _) where missing > 0:
            return String(format: String(localized: "%lld 类施工资料缺项"), Int64(missing))
        case let (_, returned) where returned > 0:
            return String(format: String(localized: "%lld 份资料退回修改"), Int64(returned))
        default:
            return String(localized: "施工资料需要检查")
        }
    }

    private func countValue(_ count: Int, unit: String) -> String {
        String(format: String(localized: "%1$lld %2$@"), Int64(count), unit)
    }
}

private struct ProjectDetailEntryShortcut: Identifiable {
    var id: String { title }
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let statusColor: Color
    let action: () -> Void
}

private struct ProjectDetailEntryShortcutsView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let entries: [ProjectDetailEntryShortcut]

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var columns: [GridItem] {
        if usesWideLayout {
            return [GridItem(.adaptive(minimum: 176), spacing: AppSpacing.tight)]
        }
        return [
            GridItem(.flexible(), spacing: AppSpacing.tight),
            GridItem(.flexible(), spacing: AppSpacing.tight)
        ]
    }

    private var iconSize: CGFloat {
        usesWideLayout ? 30 : 28
    }

    private var minHeight: CGFloat {
        usesWideLayout ? 72 : 56
    }

    private var horizontalPadding: CGFloat {
        usesWideLayout ? AppSpacing.normal : AppSpacing.tight
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.tight) {
            ForEach(entries) { entry in
                Button(action: entry.action) {
                    HStack(spacing: AppSpacing.tight) {
                        Image(systemName: entry.systemImage)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(entry.tint)
                            .frame(width: iconSize, height: iconSize)
                            .background(entry.tint.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title)
                                .font(usesWideLayout ? .subheadline.weight(.semibold) : .caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .appListPrimaryTextLayout(lines: 1)
                            Text(entry.subtitle)
                                .font((usesWideLayout ? Font.caption : Font.caption2).weight(.medium))
                                .foregroundStyle(entry.statusColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 6)
                    .background(Color.appPrimarySurfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(entry.title)，\(entry.subtitle)")
            }
        }
    }
}

private struct ProjectNextStepSuggestion: Identifiable {
    enum Action {
        case addLog
        case records
        case finance
        case assets
    }

    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: Action
}

private struct ProjectNextStepSuggestionsView: View {
    let suggestions: [ProjectNextStepSuggestion]
    let onAddLog: () -> Void
    let onOpenRecords: () -> Void
    let onOpenFinance: () -> Void
    let onOpenAssets: () -> Void

    var body: some View {
        if suggestions.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                Label(String(localized: "当前项目状态良好"), systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.appSuccess)
                Text(String(localized: "暂无需要优先处理的日志、延期、回款或票据问题。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } else {
            ForEach(suggestions) { suggestion in
                Button {
                    perform(suggestion.action)
                } label: {
                    HStack(spacing: AppSpacing.normal) {
                        Image(systemName: suggestion.systemImage)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(suggestion.tint)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(suggestion.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(suggestion.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func perform(_ action: ProjectNextStepSuggestion.Action) {
        switch action {
        case .addLog:
            onAddLog()
        case .records:
            onOpenRecords()
        case .finance:
            onOpenFinance()
        case .assets:
            onOpenAssets()
        }
    }
}

private struct ProjectProgressGanttView: View {
    let tasks: [ProgressTask]
    let onEditTask: (ProgressTask) -> Void

    private var rangeStart: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: today) ?? today
    }
    private var rangeEnd: Date {
        Calendar.current.date(byAdding: .day, value: 30, to: today) ?? today
    }
    private var totalDays: Int { 61 }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var weekOffsets: [Int] { Array(stride(from: 0, through: totalDays - 1, by: 7)) }

    private var bars: [GanttBar] {
        tasks.compactMap { task in
            guard let start = Formatters.date.date(from: task.startDate),
                  let due = Formatters.date.date(from: task.dueDate) else { return nil }
            let realStart = min(start, due)
            let realEnd = max(start, due)
            guard realEnd >= rangeStart, realStart <= rangeEnd else { return nil }
            let clampedStart = max(realStart, rangeStart)
            let clampedEnd = min(realEnd, rangeEnd)
            let offset = Calendar.current.dateComponents([.day], from: rangeStart, to: clampedStart).day ?? 0
            let span = max((Calendar.current.dateComponents([.day], from: clampedStart, to: clampedEnd).day ?? 0) + 1, 1)
            return GanttBar(task: task, offsetDays: offset, durationDays: span)
        }
        .sorted { lhs, rhs in
            let lhsDate = Formatters.date.date(from: lhs.task.startDate) ?? .distantPast
            let rhsDate = Formatters.date.date(from: rhs.task.startDate) ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    var body: some View {
        if bars.isEmpty {
            ProjectInlineEmptyState(
                String(localized: "没有可展示的进度"),
                systemImage: "chart.bar.xaxis",
                detail: String(localized: "补充任务开始和截止日期后显示。")
            )
        } else {
            GeometryReader { proxy in
                let labelWidth = min(max(proxy.size.width * 0.32, 120), 178)
                let chartWidth = max(proxy.size.width - labelWidth - AppSpacing.normal, 220)
                let dayWidth = chartWidth / CGFloat(totalDays)

                VStack(alignment: .leading, spacing: AppSpacing.tight) {
                    HStack {
                        Text(String(format: String(localized: "%1$@ 至 %2$@"), Formatters.date.string(from: rangeStart), Formatters.date.string(from: rangeEnd)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(localized: "今天"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.appPrimaryAction)
                        Text(String(format: String(localized: "共 %lld 项"), Int64(bars.count)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    ZStack(alignment: .topLeading) {
                        timelineGrid(chartWidth: chartWidth, dayWidth: dayWidth, labelWidth: labelWidth)
                        VStack(alignment: .leading, spacing: AppSpacing.tight) {
                            ForEach(bars) { bar in
                                ganttRow(bar, labelWidth: labelWidth, chartWidth: chartWidth, dayWidth: dayWidth)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: CGFloat(bars.count) * 44 + 34)
        }
    }

    private func timelineGrid(chartWidth: CGFloat, dayWidth: CGFloat, labelWidth: CGFloat) -> some View {
        HStack(spacing: AppSpacing.normal) {
            Color.clear
                .frame(width: labelWidth)
            ZStack(alignment: .leading) {
                ForEach(weekOffsets, id: \.self) { offset in
                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: 1)
                        .offset(x: CGFloat(offset) * dayWidth)
                }
                Rectangle()
                    .fill(Color.appPrimaryAction.opacity(0.65))
                    .frame(width: 2)
                    .offset(x: CGFloat(30) * dayWidth)
            }
            .frame(width: chartWidth, alignment: .leading)
            .frame(maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    private func ganttRow(_ bar: GanttBar, labelWidth: CGFloat, chartWidth: CGFloat, dayWidth: CGFloat) -> some View {
        Button {
            onEditTask(bar.task)
        } label: {
            HStack(alignment: .center, spacing: AppSpacing.normal) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bar.task.title)
                        .font(.caption.weight(.semibold))
                        .appListPrimaryTextLayout()
                    Text("\(bar.task.startDate) → \(bar.task.dueDate)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .appListSecondaryTextLayout()
                }
                .frame(width: labelWidth, alignment: .leading)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                        .frame(width: chartWidth, height: 18)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(bar.color)
                        .frame(width: max(CGFloat(bar.durationDays) * dayWidth, 5), height: 18)
                        .offset(x: CGFloat(bar.offsetDays) * dayWidth)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private struct GanttBar: Identifiable {
        let task: ProgressTask
        let offsetDays: Int
        let durationDays: Int
        var id: UUID { task.id }

        var color: Color {
            if task.clampedCompletion >= 1 { return .appSuccess }
            if let due = Formatters.date.date(from: task.dueDate),
               due < Calendar.current.startOfDay(for: Date()) {
                return .appRisk
            }
            return .appWarning
        }
    }
}
