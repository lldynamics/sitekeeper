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
