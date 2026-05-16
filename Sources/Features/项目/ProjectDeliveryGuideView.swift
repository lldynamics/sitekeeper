import SwiftUI

struct ProjectDeliveryBackupState: Equatable {
    let latestBackupDate: Date?
    let reminderDays: Int
    let referenceDate: Date

    static func current(referenceDate: Date = Date()) -> ProjectDeliveryBackupState {
        let reminderDaysRaw = UserDefaults.standard.integer(forKey: UserPreferenceKeys.backupHealthReminderDays)
        let reminderDays = max(1, reminderDaysRaw == 0 ? 7 : reminderDaysRaw)
        let localBackupRaw = UserDefaults.standard.double(forKey: UserPreferenceKeys.localBackupLastSuccessAt)
        let cloudBackupRaw = UserDefaults.standard.double(forKey: UserPreferenceKeys.cloudBackupLastSuccessAt)
        let localBackupDate = localBackupRaw > 0 ? Date(timeIntervalSince1970: localBackupRaw) : nil
        let cloudBackupDate = cloudBackupRaw > 0 ? Date(timeIntervalSince1970: cloudBackupRaw) : nil
        let latestBackupDate: Date? = {
            switch (localBackupDate, cloudBackupDate) {
            case let (lhs?, rhs?):
                return max(lhs, rhs)
            case let (lhs?, nil):
                return lhs
            case let (nil, rhs?):
                return rhs
            case (nil, nil):
                return nil
            }
        }()
        return ProjectDeliveryBackupState(
            latestBackupDate: latestBackupDate,
            reminderDays: reminderDays,
            referenceDate: referenceDate
        )
    }

    var isFresh: Bool {
        guard latestBackupDate != nil else { return false }
        return daysSinceLatestBackup < reminderDays
    }

    var daysSinceLatestBackup: Int {
        guard let latestBackupDate else { return Int.max }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: latestBackupDate)
        let end = calendar.startOfDay(for: referenceDate)
        return max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)
    }

    var detail: String {
        guard let latestBackupDate else {
            return String(localized: "尚未记录成功备份")
        }
        if daysSinceLatestBackup == 0 {
            return String(format: String(localized: "今天已备份，提醒阈值 %lld 天"), Int64(reminderDays))
        }
        return String(
            format: String(localized: "最近备份 %@，已过 %lld 天"),
            Formatters.dateTime.string(from: latestBackupDate),
            Int64(daysSinceLatestBackup)
        )
    }
}

struct ProjectDeliveryHealth: Equatable {
    enum Issue: String, CaseIterable, Identifiable {
        case missingReceipts
        case missingDrawings
        case openTodos
        case backupOverdue
        case missingOriginals

        var id: String { rawValue }

        var title: String {
            switch self {
            case .missingReceipts:
                return String(localized: "缺票据")
            case .missingDrawings:
                return String(localized: "缺图纸")
            case .openTodos:
                return String(localized: "未完成待办")
            case .backupOverdue:
                return String(localized: "未备份")
            case .missingOriginals:
                return String(localized: "资料缺原件")
            }
        }

        var passedTitle: String {
            switch self {
            case .missingReceipts:
                return String(localized: "票据已补齐")
            case .missingDrawings:
                return String(localized: "图纸已上传")
            case .openTodos:
                return String(localized: "待办已清空")
            case .backupOverdue:
                return String(localized: "备份有效")
            case .missingOriginals:
                return String(localized: "原件齐全")
            }
        }

        var icon: String {
            switch self {
            case .missingReceipts:
                return "receipt.fill"
            case .missingDrawings:
                return "square.on.square.squareshape.controlhandles"
            case .openTodos:
                return "checklist"
            case .backupOverdue:
                return "externaldrive.badge.icloud"
            case .missingOriginals:
                return "doc.badge.exclamationmark"
            }
        }

        var repairMode: ProjectDetailMode? {
            switch self {
            case .missingReceipts:
                return .finance
            case .missingDrawings, .missingOriginals:
                return .assets
            case .openTodos:
                return .records
            case .backupOverdue:
                return nil
            }
        }
    }

    let missingReceiptCount: Int
    let drawingCount: Int
    let openTodoCount: Int
    let backupState: ProjectDeliveryBackupState
    let missingOriginalCount: Int

    var failedIssues: [Issue] {
        Issue.allCases.filter { !isPassed($0) }
    }

    var score: Int {
        max(0, 100 - failedIssues.count * 20)
    }

    var isDeliverable: Bool {
        failedIssues.isEmpty
    }

    var verdictTitle: String {
        isDeliverable ? String(localized: "可交付") : String(localized: "不可交付")
    }

    var summary: String {
        if isDeliverable {
            return String(localized: "票据、图纸、待办、备份和原件检查均已通过。")
        }
        let titles = failedIssues.map(\.title).joined(separator: "、")
        return String(format: String(localized: "需处理：%@"), titles)
    }

    func isPassed(_ issue: Issue) -> Bool {
        switch issue {
        case .missingReceipts:
            return missingReceiptCount == 0
        case .missingDrawings:
            return drawingCount > 0
        case .openTodos:
            return openTodoCount == 0
        case .backupOverdue:
            return backupState.isFresh
        case .missingOriginals:
            return missingOriginalCount == 0
        }
    }

    func detail(for issue: Issue) -> String {
        switch issue {
        case .missingReceipts:
            return missingReceiptCount == 0
                ? String(localized: "需要留票的账目均已关联票据。")
                : String(format: String(localized: "还有 %lld 笔账目缺票据。"), Int64(missingReceiptCount))
        case .missingDrawings:
            return drawingCount > 0
                ? String(format: String(localized: "已上传 %lld 份图纸。"), Int64(drawingCount))
                : String(localized: "项目还没有图纸文件。")
        case .openTodos:
            return openTodoCount == 0
                ? String(localized: "没有未完成待办。")
                : String(format: String(localized: "还有 %lld 条现场待办未完成。"), Int64(openTodoCount))
        case .backupOverdue:
            return backupState.detail
        case .missingOriginals:
            return missingOriginalCount == 0
                ? String(localized: "交付包引用的本机原件均可找到。")
                : String(format: String(localized: "检测到 %lld 个资料原件缺失。"), Int64(missingOriginalCount))
        }
    }
}

struct ProjectDeliveryHealthSummaryRow: View {
    let health: ProjectDeliveryHealth
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: AppSpacing.tight) {
                Image(systemName: health.isDeliverable ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .foregroundStyle(health.isDeliverable ? Color.appSuccess : Color.appRisk)
                    .font(.caption.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: String(localized: "交付健康分 %lld · %@"), Int64(health.score), health.verdictTitle))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(health.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppSpacing.normal)
            .padding(.vertical, 8)
            .background(
                health.isDeliverable ? Color.appSuccessSurfaceSubtle : Color.appRiskSurface,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ProjectDeliveryGuideData {
    let projectName: String
    let logCount: Int
    let expectedLogDateCount: Int
    let missingLogDateCount: Int
    let missingLogDateSamples: [String]
    let drawingCount: Int
    let drawingGroupsWithoutCurrent: [String]
    let documentCount: Int
    let contactCount: Int
    let missingReceiptCount: Int
    let unsettledFinancialCount: Int
    let unsettledFinancialAmount: Double
    let openTodoCount: Int
    let backupState: ProjectDeliveryBackupState
    let missingOriginalEntries: [String]
    let estimatedPackageBytes: Int

    var deliveryHealth: ProjectDeliveryHealth {
        ProjectDeliveryHealth(
            missingReceiptCount: missingReceiptCount,
            drawingCount: drawingCount,
            openTodoCount: openTodoCount,
            backupState: backupState,
            missingOriginalCount: missingOriginalEntries.count
        )
    }

    var drawingWithoutCurrentCount: Int {
        drawingGroupsWithoutCurrent.count
    }

    var hasBlockingMissingOriginals: Bool {
        !missingOriginalEntries.isEmpty
    }

    var hasDeliveryChecklistWarning: Bool {
        missingLogDateCount > 0
            || drawingCount == 0
            || drawingWithoutCurrentCount > 0
            || contactCount == 0
            || missingReceiptCount > 0
            || unsettledFinancialCount > 0
            || !deliveryHealth.isDeliverable
    }

    var deliveryWarningCount: Int {
        deliveryHealth.failedIssues.count + [
            missingLogDateCount > 0,
            drawingCount > 0 && drawingWithoutCurrentCount > 0,
            contactCount == 0,
            unsettledFinancialCount > 0
        ].filter { $0 }.count
    }

    var isReadyForDelivery: Bool {
        deliveryHealth.isDeliverable && !hasDeliveryChecklistWarning && !hasBlockingMissingOriginals
    }
}

struct ProjectDeliveryGuideView: View {
    let data: ProjectDeliveryGuideData
    let onStartExport: () -> Void
    let onOpenMode: (ProjectDetailMode) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    readinessCard
                }

                Section(String(localized: "交付健康分")) {
                    ForEach(ProjectDeliveryHealth.Issue.allCases) { issue in
                        healthRow(issue)
                    }
                }

                Section(String(localized: "交付检查")) {
                    guideRow(
                        title: String(localized: "缺日志检查"),
                        detail: logCoverageDetail,
                        status: data.missingLogDateCount == 0 ? .ok : .warning
                    ) {
                        onOpenMode(.records)
                    }
                    guideRow(
                        title: String(localized: "缺票检查"),
                        detail: data.missingReceiptCount == 0
                            ? String(localized: "全部已关联")
                            : String(format: String(localized: "还有 %lld 条待关联"), Int64(data.missingReceiptCount)),
                        status: data.missingReceiptCount == 0 ? .ok : .warning
                    ) {
                        onOpenMode(.finance)
                    }
                    guideRow(
                        title: String(localized: "未完成待办"),
                        detail: data.openTodoCount == 0
                            ? String(localized: "没有未完成待办")
                            : String(format: String(localized: "还有 %lld 条待办未完成"), Int64(data.openTodoCount)),
                        status: data.openTodoCount == 0 ? .ok : .warning
                    ) {
                        onOpenMode(.records)
                    }
                    guideRow(
                        title: String(localized: "图纸当前版检查"),
                        detail: drawingCurrentVersionDetail,
                        status: drawingCurrentVersionStatus
                    ) {
                        onOpenMode(.assets)
                    }
                    guideRow(
                        title: String(localized: "联系人缺失检查"),
                        detail: data.contactCount > 0
                            ? String(format: String(localized: "已维护 %lld 位"), Int64(data.contactCount))
                            : String(localized: "还没有联系人"),
                        status: data.contactCount > 0 ? .ok : .warning
                    ) {
                        onOpenMode(.assets)
                    }
                    guideRow(
                        title: String(localized: "未结清检查"),
                        detail: unsettledFinancialDetail,
                        status: data.unsettledFinancialCount == 0 ? .ok : .warning
                    ) {
                        onOpenMode(.finance)
                    }
                    guideRow(
                        title: String(localized: "原件完整性"),
                        detail: data.hasBlockingMissingOriginals
                            ? String(format: String(localized: "检测到 %lld 个缺失原件"), Int64(data.missingOriginalEntries.count))
                            : String(localized: "未发现缺失原件"),
                        status: data.hasBlockingMissingOriginals ? .error : .ok
                    ) {
                        onOpenMode(.assets)
                    }
                    guideRow(
                        title: String(localized: "最近备份"),
                        detail: data.backupState.detail,
                        status: data.backupState.isFresh ? .ok : .warning,
                        fixAction: nil
                    )
                }

                if data.hasDeliveryChecklistWarning {
                    Section {
                        Text(String(localized: "仍可先预览交付包，但建议先补齐日志、票据、图纸当前版、联系人和未结清账目，再执行最终交付。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if data.hasBlockingMissingOriginals {
                    Section(String(localized: "缺失原件（导出前需处理）")) {
                        ForEach(Array(data.missingOriginalEntries.prefix(20)), id: \.self) { item in
                            HStack(alignment: .top, spacing: AppSpacing.tight) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.appRisk)
                                    .font(.caption)
                                Text(item)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if data.missingOriginalEntries.count > 20 {
                            Text(
                                String(
                                    format: String(localized: "还有 %lld 项未显示"),
                                    Int64(data.missingOriginalEntries.count - 20)
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(String(localized: "交付包预估")) {
                    LabeledContent(String(localized: "工程名称")) {
                        Text(data.projectName)
                            .lineLimit(1)
                    }
                    LabeledContent(String(localized: "预计原始附件体积")) {
                        Text(ProjectDetailImportExportActions.formattedBytes(data.estimatedPackageBytes))
                            .foregroundStyle(.secondary)
                    }
                    Text(String(localized: "将导出包含日志、图纸、票据、联系人、财务摘要与原件的 ZIP 交付包。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        onStartExport()
                    } label: {
                        Label(exportButtonTitle, systemImage: "archivebox.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appProminent())
                    .disabled(data.hasBlockingMissingOriginals)
                } footer: {
                    if data.hasBlockingMissingOriginals {
                        Text(String(localized: "检测到缺失原件，需先补齐后才能导出。"))
                    }
                }
            }
            .navigationTitle(String(localized: "完工交付向导"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var readinessCard: some View {
        HStack(alignment: .top, spacing: AppSpacing.normal) {
            Image(systemName: data.isReadyForDelivery ? "checkmark.seal.fill" : "checklist.unchecked")
                .font(.title2.weight(.semibold))
                .foregroundStyle(data.deliveryHealth.isDeliverable ? Color.appSuccess : Color.appRisk)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    String(
                        format: String(localized: "交付健康分 %lld · %@"),
                        Int64(data.deliveryHealth.score),
                        data.deliveryHealth.verdictTitle
                    )
                )
                    .font(.headline)
                ProgressView(value: Double(data.deliveryHealth.score), total: 100)
                    .tint(data.deliveryHealth.isDeliverable ? Color.appSuccess : Color.appRisk)
                Text(readinessDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var readinessDetail: String {
        if data.deliveryHealth.isDeliverable {
            if data.isReadyForDelivery {
                return String(localized: "票据、图纸、待办、备份和原件检查均已通过，可执行最终交付。")
            }
            return String(
                format: String(localized: "核心交付项已通过，另有 %lld 项建议检查。"),
                Int64(data.deliveryWarningCount)
            )
        }
        return data.deliveryHealth.summary
    }

    private var logCoverageDetail: String {
        if data.missingLogDateCount == 0 {
            if data.expectedLogDateCount > 0 {
                return String(
                    format: String(localized: "已覆盖 %lld 个施工日，共 %lld 条日志"),
                    Int64(data.expectedLogDateCount),
                    Int64(data.logCount)
                )
            }
            return data.logCount > 0
                ? String(format: String(localized: "已记录 %lld 条"), Int64(data.logCount))
                : String(localized: "未设置工期，暂无缺日志日期")
        }
        if data.expectedLogDateCount == 0 {
            return String(localized: "未记录施工日志")
        }
        let sample = data.missingLogDateSamples.joined(separator: "、")
        if sample.isEmpty {
            return String(format: String(localized: "缺 %lld 个施工日"), Int64(data.missingLogDateCount))
        }
        return String(
            format: String(localized: "缺 %lld 个施工日：%@"),
            Int64(data.missingLogDateCount),
            sample
        )
    }

    private var unsettledFinancialDetail: String {
        guard data.unsettledFinancialCount > 0 else {
            return String(localized: "没有未结清账目")
        }
        if data.unsettledFinancialAmount > 0 {
            return String(
                format: String(localized: "还有 %lld 笔，合计 %@"),
                Int64(data.unsettledFinancialCount),
                ReportBuilder.money(data.unsettledFinancialAmount)
            )
        }
        return String(
            format: String(localized: "还有 %lld 笔未结清"),
            Int64(data.unsettledFinancialCount)
        )
    }

    private var exportButtonTitle: String {
        data.hasDeliveryChecklistWarning || !data.deliveryHealth.isDeliverable
            ? String(localized: "检查后导出交付包 ZIP")
            : String(localized: "一键导出交付包 ZIP")
    }

    @ViewBuilder
    private func guideRow(title: String, detail: String, status: GuideStatus, fixAction: (() -> Void)? = nil) -> some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status != .ok, let fixAction {
                Button(String(localized: "去处理")) {
                    fixAction()
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private func healthRow(_ issue: ProjectDeliveryHealth.Issue) -> some View {
        let isPassed = data.deliveryHealth.isPassed(issue)
        return HStack(spacing: AppSpacing.tight) {
            Image(systemName: issue.icon)
                .foregroundStyle(isPassed ? Color.appSuccess : Color.appRisk)
                .font(.caption.weight(.semibold))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(isPassed ? issue.passedTitle : issue.title)
                    .font(.callout.weight(.semibold))
                Text(data.deliveryHealth.detail(for: issue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isPassed, let mode = issue.repairMode {
                Button(String(localized: "去处理")) {
                    onOpenMode(mode)
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private var drawingCurrentVersionDetail: String {
        if data.drawingCount == 0 {
            return String(localized: "还没有图纸")
        }
        if data.drawingWithoutCurrentCount > 0 {
            let sample = data.drawingGroupsWithoutCurrent.prefix(3).joined(separator: "、")
            if sample.isEmpty {
                return String(
                    format: String(localized: "%lld 组图纸未标记当前版"),
                    Int64(data.drawingWithoutCurrentCount)
                )
            }
            return String(
                format: String(localized: "%lld 组图纸未标记当前版：%@"),
                Int64(data.drawingWithoutCurrentCount),
                sample
            )
        }
        return String(format: String(localized: "已上传 %lld 份，均有当前版"), Int64(data.drawingCount))
    }

    private var drawingCurrentVersionStatus: GuideStatus {
        if data.drawingCount == 0 {
            return .warning
        }
        return data.drawingWithoutCurrentCount > 0 ? .warning : .ok
    }

    private enum GuideStatus {
        case ok
        case warning
        case error

        var icon: String {
            switch self {
            case .ok:
                return "checkmark.circle.fill"
            case .warning:
                return "exclamationmark.circle.fill"
            case .error:
                return "xmark.octagon.fill"
            }
        }

        var color: Color {
            switch self {
            case .ok:
                return .appSuccess
            case .warning:
                return .appPrimaryAction
            case .error:
                return .appRisk
            }
        }
    }
}
