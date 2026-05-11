import SwiftUI

struct ProjectOverviewView<LogRowContent: View>: View {
    let project: Project
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
    let onOpenRecords: () -> Void
    let onOpenAssets: () -> Void
    let onAddLog: () -> Void
    let onEditProgress: (ProgressTask) -> Void
    let logRow: (DailyLog) -> LogRowContent

    var body: some View {
        Group {
            Section("经营概览") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: AppSpacing.tight)], spacing: AppSpacing.tight) {
                    ProjectOverviewSummaryCard(
                        title: "合同 / 收款",
                        systemImage: "yensign.circle.fill",
                        tint: .pink,
                        metrics: [
                            .init(title: "合同", value: ReportBuilder.money(project.contractAmountValue.doubleValue)),
                            .init(title: "已收", value: ReportBuilder.money(paidAmount), color: .green),
                            .init(title: "未收", value: ReportBuilder.money(unpaidAmount), color: unpaidAmount > 0 ? .orange : .secondary),
                            .init(title: "状态", value: paymentStatus.displayName)
                        ],
                        action: onOpenFinance
                    )
                    ProjectOverviewSummaryCard(
                        title: "成本 / 利润",
                        systemImage: "chart.pie.fill",
                        tint: .orange,
                        metrics: [
                            .init(title: "材料", value: ReportBuilder.money(materialCost)),
                            .init(title: "人工", value: ReportBuilder.money(laborCost)),
                            .init(title: "工时", value: laborHours),
                            .init(title: "毛利", value: ReportBuilder.money(estimatedProfit), color: estimatedProfit >= 0 ? .green : .red)
                        ],
                        action: onOpenFinance
                    )
                    ProjectOverviewSummaryCard(
                        title: "记录 / 资料",
                        systemImage: "folder.badge.gearshape",
                        tint: .blue,
                        metrics: [
                            .init(title: "日志", value: "\(logDayCount) 天"),
                            .init(title: "记账", value: "\(financialCount) 笔"),
                            .init(title: "材料", value: "\(materialCount) 项"),
                            .init(title: "资料", value: "\(documentCount) 份")
                        ],
                        action: onOpenAssets
                    )
                }
                Button {
                    onOpenRecords()
                } label: {
                    Label("查看现场记录和进度", systemImage: "checklist.checked")
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
                                .foregroundStyle(todo.isOverdue ? .red : .secondary)
                        }
                    }
                }
            }
        }
    }

    private var nextStepSuggestions: [ProjectNextStepSuggestion] {
        var suggestions: [ProjectNextStepSuggestion] = []
        if !hasTodayLog {
            suggestions.append(.init(title: "补写今日日志", subtitle: "今天还没有施工日志", systemImage: "book.pages.fill", tint: .green, action: .addLog))
        }
        if overdueCount > 0 {
            suggestions.append(.init(title: "处理延期事项", subtitle: "\(overdueCount) 项需要跟进", systemImage: "calendar.badge.exclamationmark", tint: .red, action: .records))
        }
        if unpaidAmount > 0 {
            suggestions.append(.init(title: "跟进未收款", subtitle: ReportBuilder.money(unpaidAmount), systemImage: "yensign.circle.fill", tint: .orange, action: .finance))
        }
        if missingReceiptCount > 0 {
            suggestions.append(.init(title: "补齐票据资料", subtitle: "\(missingReceiptCount) 笔账目缺票", systemImage: "doc.badge.plus", tint: .brown, action: .assets))
        }
        if progressTasks.isEmpty {
            suggestions.append(.init(title: "添加进度任务", subtitle: "用项目看板跟踪节点", systemImage: "checklist.checked", tint: .blue, action: .records))
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
}

private struct ProjectOverviewSummaryMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    var color: Color = .primary
}

private struct ProjectOverviewSummaryCard: View {
    let title: String
    let systemImage: String
    let tint: Color
    let metrics: [ProjectOverviewSummaryMetric]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                HStack(spacing: AppSpacing.tight * 0.75) {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ForEach(metrics) { metric in
                    HStack(alignment: .firstTextBaseline) {
                        Text(metric.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: AppSpacing.tight)
                        Text(metric.value)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(metric.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
            .padding(AppSpacing.normal)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.tight, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
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
                    .foregroundStyle(.green)
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
                            .foregroundStyle(.orange)
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
                    .fill(Color.orange.opacity(0.65))
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
            if task.clampedCompletion >= 1 { return .green }
            if let due = Formatters.date.date(from: task.dueDate),
               due < Calendar.current.startOfDay(for: Date()) {
                return .red
            }
            return .orange
        }
    }
}
