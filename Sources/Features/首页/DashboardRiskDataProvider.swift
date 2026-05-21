import SwiftUI

extension DashboardView {
    var effectiveBackupReminderDays: Int {
        let raw = UserDefaults.standard.integer(forKey: UserPreferenceKeys.backupHealthReminderDays)
        return max(1, raw == 0 ? 7 : raw)
    }

    var latestSuccessfulBackupDate: Date? {
        let localRaw = UserDefaults.standard.double(forKey: UserPreferenceKeys.localBackupLastSuccessAt)
        let cloudRaw = UserDefaults.standard.double(forKey: UserPreferenceKeys.cloudBackupLastSuccessAt)
        let localDate = localRaw > 0 ? Date(timeIntervalSince1970: localRaw) : nil
        let cloudDate = cloudRaw > 0 ? Date(timeIntervalSince1970: cloudRaw) : nil
        switch (localDate, cloudDate) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    var daysSinceLastSuccessfulBackup: Int? {
        guard let latestSuccessfulBackupDate else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: latestSuccessfulBackupDate)
        let today = calendar.startOfDay(for: Date())
        return max(calendar.dateComponents([.day], from: start, to: today).day ?? 0, 0)
    }

    var isBackupReminderOverdue: Bool {
        guard let daysSinceLastSuccessfulBackup else { return true }
        return daysSinceLastSuccessfulBackup >= effectiveBackupReminderDays
    }

    var backupReminderValue: String {
        if isIgnoringBackupReminderToday { return String(localized: "已忽略") }
        guard let daysSinceLastSuccessfulBackup else { return String(localized: "未备份") }
        return String(format: String(localized: "%lld天"), Int64(daysSinceLastSuccessfulBackup))
    }

    var backupReminderRiskCount: Int {
        isBackupReminderOverdue ? 1 : 0
    }

    private var isIgnoringBackupReminderToday: Bool {
        ignoredBackupRiskDay == todayStr
    }

    private var isIgnoringMissingReceiptToday: Bool {
        ignoredMissingReceiptRiskDay == todayStr
    }

    private var isIgnoringPriceSpikeToday: Bool {
        ignoredPriceSpikeRiskDay == todayStr
    }

    private var isIgnoringNegativeStockToday: Bool {
        ignoredNegativeStockRiskDay == todayStr
    }

    var displayedMissingReceiptCount: Int {
        isIgnoringMissingReceiptToday ? 0 : unattachedReceiptCount
    }

    var displayedPriceSpikeCount: Int {
        isIgnoringPriceSpikeToday ? 0 : materialPriceSpikeCount
    }

    var displayedNegativeStockCount: Int {
        isIgnoringNegativeStockToday ? 0 : warehouseNegativeCount
    }

    var displayedDataHealthIssueCount: Int {
        store.latestDataHealthScan?.totalIssues ?? 0
    }

    var dataHealthRiskValue: String {
        guard let summary = store.latestDataHealthScan else { return String(localized: "待扫描") }
        return "\(summary.totalIssues)"
    }

    var isDisplayedBackupReminderOverdue: Bool {
        guard !isIgnoringBackupReminderToday else { return false }
        return isBackupReminderOverdue
    }

    var dashboardRiskTotal: Int {
        overdueCount
            + todayTodos.count
            + projectsWithoutTodayLogCount
            + displayedMissingReceiptCount
            + unsettledFinancialCount
            + displayedPriceSpikeCount
            + displayedNegativeStockCount
            + displayedDataHealthIssueCount
            + (isDisplayedBackupReminderOverdue ? 1 : 0)
    }

    var hasDashboardRisk: Bool {
        dashboardRiskTotal > 0
    }

    var dashboardRiskPins: [DashboardRiskPin] {
        let pins: [DashboardRiskPin] = [
            DashboardRiskPin(
                id: "overdue",
                title: String(localized: "延期"),
                value: "\(overdueCount)",
                color: overdueCount > 0 ? .appRisk : .appSuccess,
                hasRisk: overdueCount > 0,
                priority: 1000,
                destination: .projectList(initialOverviewFilter: .overdue)
            ),
            DashboardRiskPin(
                id: "todayTodos",
                title: String(localized: "今日待办"),
                value: "\(todayTodos.count)",
                color: !todayTodos.isEmpty ? .appWarning : .appSuccess,
                hasRisk: !todayTodos.isEmpty,
                priority: 900,
                destination: .projectList(initialOverviewFilter: .todo)
            ),
            DashboardRiskPin(
                id: "backupOverdue",
                title: String(localized: "备份超期"),
                value: backupReminderValue,
                color: isDisplayedBackupReminderOverdue ? .appRisk : .appSuccess,
                hasRisk: isDisplayedBackupReminderOverdue,
                priority: 850,
                destination: .dataManagement(initialRoute: .backup),
                quickActions: backupReminderRiskActions
            ),
            DashboardRiskPin(
                id: "priceSpike",
                title: String(localized: "价格异动"),
                value: "\(displayedPriceSpikeCount)",
                color: displayedPriceSpikeCount > 0 ? .appFinance : .appSuccess,
                hasRisk: displayedPriceSpikeCount > 0,
                priority: 820,
                destination: .materialPriceSpikeDetails,
                quickActions: priceSpikeRiskActions
            ),
            DashboardRiskPin(
                id: "dataHealth",
                title: String(localized: "数据异常"),
                value: dataHealthRiskValue,
                color: displayedDataHealthIssueCount > 0 ? .appRisk : .appSuccess,
                hasRisk: displayedDataHealthIssueCount > 0,
                priority: 800,
                destination: .dataManagement(initialRoute: .health),
                quickActions: dataHealthRiskActions
            ),
            DashboardRiskPin(
                id: "negativeStock",
                title: String(localized: "负库存"),
                value: "\(displayedNegativeStockCount)",
                color: displayedNegativeStockCount > 0 ? .appRisk : .appSuccess,
                hasRisk: displayedNegativeStockCount > 0,
                priority: 780,
                destination: warehouseOverviewDestination,
                quickActions: negativeStockRiskActions
            ),
            DashboardRiskPin(
                id: "missingReceipt",
                title: String(localized: "缺票"),
                value: "\(displayedMissingReceiptCount)",
                color: displayedMissingReceiptCount > 0 ? .appFinance : .appSuccess,
                hasRisk: displayedMissingReceiptCount > 0,
                priority: 740,
                destination: .projectList(initialOverviewFilter: .missingReceipt),
                quickActions: missingReceiptRiskActions
            ),
            DashboardRiskPin(
                id: "financialDue",
                title: String(localized: "应收付"),
                value: "\(unsettledFinancialCount)",
                color: unsettledFinancialCount > 0 ? .appWarning : .appSuccess,
                hasRisk: unsettledFinancialCount > 0,
                priority: 700,
                destination: .projectList(initialOverviewFilter: .financialDue)
            ),
            DashboardRiskPin(
                id: "missingTodayLog",
                title: String(localized: "未写日志"),
                value: "\(projectsWithoutTodayLogCount)",
                color: projectsWithoutTodayLogCount > 0 ? .appDoc : .appSuccess,
                hasRisk: projectsWithoutTodayLogCount > 0,
                priority: 620,
                destination: .projectList(initialOverviewFilter: .missingTodayLog)
            ),
        ]

        return pins.sorted {
            if $0.hasRisk != $1.hasRisk { return $0.hasRisk && !$1.hasRisk }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    var visibleDashboardRiskPins: [DashboardRiskPin] {
        dashboardRiskPins.filter(\.hasRisk)
    }

    var dataHealthRiskActions: [DashboardRiskQuickAction] {
        guard displayedDataHealthIssueCount > 0 else { return [] }
        return [
            DashboardRiskQuickAction(
                id: "dataHealth.scan",
                title: String(localized: "重新扫描"),
                systemImage: "arrow.clockwise",
                action: refreshDataHealthRisk
            ),
            DashboardRiskQuickAction(
                id: "dataHealth.todo",
                title: String(localized: "生成待办"),
                systemImage: "checklist",
                action: createDataHealthTodo
            )
        ]
    }

    var backupReminderRiskActions: [DashboardRiskQuickAction] {
        guard isDisplayedBackupReminderOverdue else { return [] }
        return [
            DashboardRiskQuickAction(
                id: "backup.ignore",
                title: String(localized: "忽略今日提醒"),
                systemImage: "eye.slash",
                action: ignoreBackupReminderForToday
            ),
            DashboardRiskQuickAction(
                id: "backup.threshold",
                title: String(localized: "阈值 +1 天"),
                systemImage: "slider.horizontal.3",
                action: raiseBackupReminderThreshold
            ),
            DashboardRiskQuickAction(
                id: "backup.todo",
                title: String(localized: "生成待办"),
                systemImage: "checklist",
                action: createBackupFollowupTodo
            )
        ]
    }

    var missingReceiptRiskActions: [DashboardRiskQuickAction] {
        guard displayedMissingReceiptCount > 0 else { return [] }
        return [
            DashboardRiskQuickAction(
                id: "receipt.ignore",
                title: String(localized: "忽略今日提醒"),
                systemImage: "eye.slash",
                action: ignoreMissingReceiptForToday
            ),
            DashboardRiskQuickAction(
                id: "receipt.todo",
                title: String(localized: "生成待办"),
                systemImage: "checklist",
                action: createMissingReceiptTodo
            )
        ]
    }

    var priceSpikeRiskActions: [DashboardRiskQuickAction] {
        guard displayedPriceSpikeCount > 0 else { return [] }
        return [
            DashboardRiskQuickAction(
                id: "spike.ignore",
                title: String(localized: "忽略今日提醒"),
                systemImage: "eye.slash",
                action: ignorePriceSpikeForToday
            ),
            DashboardRiskQuickAction(
                id: "spike.threshold",
                title: String(localized: "上调阈值 +5%"),
                systemImage: "slider.horizontal.3",
                action: raisePriceSpikeThreshold
            ),
            DashboardRiskQuickAction(
                id: "spike.todo",
                title: String(localized: "生成待办"),
                systemImage: "checklist",
                action: createPriceSpikeTodo
            )
        ]
    }

    var negativeStockRiskActions: [DashboardRiskQuickAction] {
        guard displayedNegativeStockCount > 0 else { return [] }
        return [
            DashboardRiskQuickAction(
                id: "stock.ignore",
                title: String(localized: "忽略今日提醒"),
                systemImage: "eye.slash",
                action: ignoreNegativeStockForToday
            ),
            DashboardRiskQuickAction(
                id: "stock.todo",
                title: String(localized: "生成待办"),
                systemImage: "checklist",
                action: createNegativeStockTodo
            )
        ]
    }

    func ignoreBackupReminderForToday() {
        ignoredBackupRiskDay = todayStr
        AppHaptics.impact(.light)
        showDashboardActionFeedback(String(localized: "已忽略今日“备份超期”提醒"))
    }

    func ignoreMissingReceiptForToday() {
        ignoredMissingReceiptRiskDay = todayStr
        AppHaptics.impact(.light)
        showDashboardActionFeedback(String(localized: "已忽略今日“缺票”提醒"))
    }

    func ignorePriceSpikeForToday() {
        ignoredPriceSpikeRiskDay = todayStr
        AppHaptics.impact(.light)
        showDashboardActionFeedback(String(localized: "已忽略今日“价格异动”提醒"))
    }

    func ignoreNegativeStockForToday() {
        ignoredNegativeStockRiskDay = todayStr
        AppHaptics.impact(.light)
        showDashboardActionFeedback(String(localized: "已忽略今日“负库存”提醒"))
    }

    func refreshDataHealthRisk() {
        store.runDataHealthScanNow(reason: .manual)
        AppHaptics.impact(.light)
        showDashboardActionFeedback(String(localized: "已安排数据健康检查"))
    }

    func raisePriceSpikeThreshold() {
        let current = financeStore.materialPriceSpikeThreshold
        let raised = min(current + 0.05, 0.50)
        guard abs(raised - current) > 0.0001 else {
            AppHaptics.warning()
            showDashboardActionFeedback(String(localized: "阈值已到上限"))
            return
        }
        financeStore.setMaterialPriceSpikeThreshold(raised)
        AppHaptics.success()
        showDashboardActionFeedback(
            String(
                format: String(localized: "已上调阈值到 %lld%%"),
                Int64((raised * 100).rounded())
            )
        )
    }

    func raiseBackupReminderThreshold() {
        let raw = UserDefaults.standard.integer(forKey: UserPreferenceKeys.backupHealthReminderDays)
        let current = max(1, raw == 0 ? 7 : raw)
        let raised = min(current + 1, 30)
        guard raised != current else {
            AppHaptics.warning()
            showDashboardActionFeedback(String(localized: "备份提醒阈值已到上限"))
            return
        }
        UserDefaults.standard.set(raised, forKey: UserPreferenceKeys.backupHealthReminderDays)
        AppHaptics.success()
        showDashboardActionFeedback(
            String(
                format: String(localized: "备份提醒阈值已调整为 %lld 天"),
                Int64(raised)
            )
        )
    }

    func createBackupFollowupTodo() {
        createRiskTodo(
            marker: "[dashboard-risk:backup-overdue]",
            title: String(localized: "检查备份策略"),
            note: String(localized: "工作台检测到备份超期，请检查本地和云端备份是否成功。"),
            projectId: nil
        )
    }

    func createMissingReceiptTodo() {
        let projectId = currentProject?.id
        let projectNameText = currentProject?.name ?? String(localized: "全部项目")
        createRiskTodo(
            marker: "[dashboard-risk:missing-receipt]",
            title: String(localized: "补齐票据资料"),
            note: String(
                format: String(localized: "%@ 当前有 %lld 笔账目缺票，请补齐附件并关联账目。"),
                projectNameText,
                Int64(displayedMissingReceiptCount)
            ),
            projectId: projectId
        )
    }

    func createPriceSpikeTodo() {
        let projectId = currentProject?.id
        let projectNameText = currentProject?.name ?? String(localized: "全部项目")
        createRiskTodo(
            marker: "[dashboard-risk:price-spike]",
            title: String(localized: "处理材料价格异动"),
            note: String(
                format: String(localized: "%@ 当前有 %lld 项价格异动，请复核采购价或调整阈值。"),
                projectNameText,
                Int64(displayedPriceSpikeCount)
            ),
            projectId: projectId
        )
    }

    func createNegativeStockTodo() {
        let projectId = currentProject?.id
        let projectNameText = currentProject?.name ?? String(localized: "全部项目")
        createRiskTodo(
            marker: "[dashboard-risk:negative-stock]",
            title: String(localized: "核对负库存"),
            note: String(
                format: String(localized: "%@ 当前有 %lld 项负库存，请补录入库或修正数量。"),
                projectNameText,
                Int64(displayedNegativeStockCount)
            ),
            projectId: projectId
        )
    }

    func createDataHealthTodo() {
        createRiskTodo(
            marker: "[dashboard-risk:data-health]",
            title: String(localized: "处理数据健康异常"),
            note: String(
                format: String(localized: "工作台检测到数据健康检查有 %lld 个异常，请打开数据健康检查处理。"),
                Int64(displayedDataHealthIssueCount)
            ),
            projectId: nil
        )
    }

    func createRiskTodo(marker: String, title: String, note: String, projectId: UUID?) {
        let hasDuplicate = store.siteTodos.contains { todo in
            !todo.isDone
                && todo.note.contains(marker)
                && todo.projectId == projectId
        }
        guard !hasDuplicate else {
            AppHaptics.warning()
            showDashboardActionFeedback(String(localized: "相同提醒待办已存在"))
            return
        }

        let todo = SiteTodo(
            title: title,
            owner: "",
            dueDate: todayStr,
            priority: .medium,
            issueType: .general,
            note: "\(note)\n\(marker)",
            projectId: projectId
        )
        store.insertSiteTodoAtTop(todo)
        store.scheduleSave()
        AppHaptics.success()
        showDashboardActionFeedback(String(localized: "已生成处理待办"))
    }
}
