import SwiftUI

struct ProjectProgressGanttView: View {
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
