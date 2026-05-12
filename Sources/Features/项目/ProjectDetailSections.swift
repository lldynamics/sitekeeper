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
    let onAddLog: () -> Void
    let onEditProgress: (ProgressTask) -> Void
    let logRow: (DailyLog) -> LogRowContent

    var body: some View {
        Group {
            Section("经营概览") {
                ProjectBusinessCardsView(
                    summary: businessSummary,
                    onOpenCore: onOpenFinance,
                    onOpenInsight: onOpenFinanceUnsettled
                )
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: AppSpacing.tight)], spacing: AppSpacing.tight) {
                    ProjectOverviewSummaryCard(
                        title: "资料",
                        systemImage: "folder.badge.gearshape.fill",
                        tint: .appDoc,
                        metrics: [
                            .init(title: "资料", value: "\(documentCount) 份"),
                            .init(title: "联系人", value: "\(contactCount) 人"),
                            .init(title: "记账附件", value: "\(missingReceiptCount) 缺票", color: missingReceiptCount > 0 ? .appFinance : .secondary)
                        ],
                        action: onOpenAssets
                    )
                    ProjectOverviewSummaryCard(
                        title: "日志",
                        systemImage: "book.pages.fill",
                        tint: .appSuccess,
                        metrics: [
                            .init(title: "日志天数", value: "\(logDayCount) 天"),
                            .init(title: "今日日志", value: hasTodayLog ? "已填写" : "未填写", color: hasTodayLog ? .appSuccess : .appWarning)
                        ],
                        action: onOpenLogs
                    )
                    ProjectOverviewSummaryCard(
                        title: "待办",
                        systemImage: "checklist.checked",
                        tint: .appWarning,
                        metrics: [
                            .init(title: "未完成", value: "\(todos.count) 项"),
                            .init(title: "延期", value: "\(todos.filter(\.isOverdue).count) 项", color: todos.contains(where: \.isOverdue) ? .appRisk : .secondary)
                        ],
                        action: onOpenTodos
                    )
                    ProjectOverviewSummaryCard(
                        title: "风险",
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .appRisk,
                        metrics: [
                            .init(title: "延期事项", value: "\(overdueCount) 项", color: overdueCount > 0 ? .appRisk : .secondary),
                            .init(title: "缺票账目", value: "\(missingReceiptCount) 笔", color: missingReceiptCount > 0 ? .appFinance : .secondary),
                            .init(title: "今日日志", value: hasTodayLog ? "已填写" : "未填写", color: hasTodayLog ? .appSuccess : .appWarning),
                            .init(title: "未回款", value: ReportBuilder.money(unpaidAmount), color: unpaidAmount > 0 ? .appFinance : .appSuccess)
                        ],
                        style: .risk(hasRisk: hasActiveRisk),
                        action: riskCardAction
                    )
                }
                Button {
                    onOpenRecords()
                } label: {
                    Label("查看现场、资料与财务明细", systemImage: "checklist.checked")
                }
            }

            Section("最近日志") {
                if recentLogs.isEmpty {
                    ContentUnavailableView(
                        "还没有施工日志",
                        systemImage: "book.pages",
                        description: Text("点击顶部“日志”记录今天的现场情况。")
                    )
                } else {
                    ForEach(recentLogs.sorted { $0.date > $1.date }.prefix(3)) { log in
                        logRow(log)
                    }
                }
            }

            Section("项目看板（±30 天）") {
                ProjectProgressGanttView(tasks: progressTasks, onEditTask: onEditProgress)
            }

            Section("下一步建议") {
                ProjectNextStepSuggestionsView(
                    suggestions: nextStepSuggestions,
                    onAddLog: onAddLog,
                    onOpenRecords: onOpenRecords,
                    onOpenFinance: onOpenFinance,
                    onOpenAssets: onOpenAssets
                )
            }

            Section("最近操作") {
                if recentItems.isEmpty {
                    ContentUnavailableView(
                        "暂无最近操作",
                        systemImage: "clock.badge.questionmark",
                        description: Text("写日志、导入资料、记账或更新进度后会显示在这里。")
                    )
                } else {
                    ProjectTimelineView(items: recentItems)
                }
            }

            Section("现场待办") {
                if todos.isEmpty {
                    ContentUnavailableView(
                        "没有未完成待办",
                        systemImage: "checklist.checked",
                        description: Text("新增现场待办后，会在这里显示最近需要处理的事项。")
                    )
                } else {
                    ForEach(todos.prefix(4)) { todo in
                        HStack {
                            Text(todo.title).font(.callout)
                            Spacer()
                            Text(todo.isOverdue ? "延期" : todo.dueDate)
                                .font(.caption)
                                .foregroundStyle(todo.isOverdue ? Color.appRisk : .secondary)
                        }
                    }
                }
            }
        }
    }

    private var nextStepSuggestions: [ProjectNextStepSuggestion] {
        var suggestions: [ProjectNextStepSuggestion] = []
        if !hasTodayLog {
            suggestions.append(.init(title: "补写今日日志", subtitle: "今天还没有施工日志", systemImage: "book.pages.fill", tint: .appSuccess, action: .addLog))
        }
        if overdueCount > 0 {
            suggestions.append(.init(title: "处理延期事项", subtitle: "\(overdueCount) 项需要跟进", systemImage: "calendar.badge.exclamationmark", tint: .appRisk, action: .records))
        }
        if unpaidAmount > 0 {
            suggestions.append(.init(title: "跟进未收款", subtitle: ReportBuilder.money(unpaidAmount), systemImage: "yensign.circle.fill", tint: .appFinance, action: .finance))
        }
        if missingReceiptCount > 0 {
            suggestions.append(.init(title: "补齐票据资料", subtitle: "\(missingReceiptCount) 笔账目缺票", systemImage: "doc.badge.plus", tint: .appDoc, action: .assets))
        }
        if progressTasks.isEmpty {
            suggestions.append(.init(title: "添加进度任务", subtitle: "用项目看板跟踪节点", systemImage: "checklist.checked", tint: .appWarning, action: .records))
        }
        return Array(suggestions.prefix(4))
    }

    private var paymentStatus: PaymentStatus {
        let contract = project.contractAmountValue.doubleValue
        if paidAmount <= 0 { return .unpaid }
        if contract > 0, paidAmount >= contract { return .paid }
        if contract <= 0 { return .partial }
        return .partial
    }

    private var hasActiveRisk: Bool {
        overdueCount > 0 || missingReceiptCount > 0 || !hasTodayLog || unpaidAmount > 0
    }

    private func riskCardAction() {
        if missingReceiptCount > 0 {
            onOpenFinanceMissingReceipt()
            return
        }
        if unpaidAmount > 0 {
            onOpenFinanceUnsettled()
            return
        }
        if !hasTodayLog {
            onOpenLogs()
            return
        }
        if overdueCount > 0 {
            onOpenTodos()
            return
        }
        onOpenRecords()
    }
}

private struct ProjectOverviewSummaryMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    var color: Color = .primary
}

private struct ProjectOverviewSummaryCard: View {
    enum Style {
        case regular
        case risk(hasRisk: Bool)
    }

    let title: String
    let systemImage: String
    let tint: Color
    let metrics: [ProjectOverviewSummaryMetric]
    var style: Style = .regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                HStack(spacing: AppSpacing.tight * 0.75) {
                    Image(systemName: systemImage)
                        .foregroundStyle(headerIconColor)
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                }

                ForEach(metrics) { metric in
                    HStack(alignment: .firstTextBaseline) {
                        Text(metric.title)
                            .font(.caption2)
                            .foregroundStyle(secondaryTextColor)
                        Spacer(minLength: AppSpacing.tight)
                        Text(metric.value)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(metricValueColor(metric))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
            .padding(AppSpacing.normal)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.tight, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.tight, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var isSolidRisk: Bool {
        if case .risk(let hasRisk) = style {
            return hasRisk
        }
        return false
    }

    private var isSafeRisk: Bool {
        if case .risk(let hasRisk) = style {
            return !hasRisk
        }
        return false
    }

    private var backgroundColor: Color {
        switch style {
        case .regular:
            return Color(uiColor: .secondarySystemGroupedBackground)
        case .risk(let hasRisk):
            return hasRisk ? Color.appRisk : Color.appSuccessSurfaceSubtle
        }
    }

    private var borderColor: Color {
        isSafeRisk ? Color.appSuccess.opacity(0.35) : Color.clear
    }

    private var borderWidth: CGFloat {
        isSafeRisk ? 1 : 0
    }

    private var headerIconColor: Color {
        if isSolidRisk { return .white }
        if isSafeRisk { return .appSuccess }
        return tint
    }

    private var primaryTextColor: Color {
        isSolidRisk ? .white : .primary
    }

    private var secondaryTextColor: Color {
        isSolidRisk ? Color.white.opacity(0.82) : .secondary
    }

    private func metricValueColor(_ metric: ProjectOverviewSummaryMetric) -> Color {
        isSolidRisk ? .white : metric.color
    }

    private var accessibilityLabelText: String {
        let values = metrics.map { "\($0.title)\($0.value)" }.joined(separator: "，")
        return "\(title)，\(values)"
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
                Label("当前项目状态良好", systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.appSuccess)
                Text("暂无需要优先处理的日志、延期、回款或票据问题。")
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
            ContentUnavailableView(
                "暂无可展示的进度任务",
                systemImage: "chart.bar.xaxis",
                description: Text("请先补充任务开始和截止日期。")
            )
        } else {
            GeometryReader { proxy in
                let labelWidth = min(max(proxy.size.width * 0.32, 120), 178)
                let chartWidth = max(proxy.size.width - labelWidth - AppSpacing.normal, 220)
                let dayWidth = chartWidth / CGFloat(totalDays)

                VStack(alignment: .leading, spacing: AppSpacing.tight) {
                    HStack {
                        Text("\(Formatters.date.string(from: rangeStart)) 至 \(Formatters.date.string(from: rangeEnd))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("今天")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.appPrimaryAction)
                        Text("共 \(bars.count) 项")
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
                        .lineLimit(1)
                    Text("\(bar.task.startDate) → \(bar.task.dueDate)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
