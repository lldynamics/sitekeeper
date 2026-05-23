import SwiftUI

extension DataManagementView {
    var sampleDataImportEnabled: Bool {
        AppFeatureFlags.allowsSampleDataImport || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var showsUITestBackupPreviewShortcut: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-backup-preview")
            || ProcessInfo.processInfo.environment["UITEST_BACKUP_PREVIEW"] == "1"
    }

    var historyTrimCount: Int {
        let perToolLimit = store.historyRetentionPerToolLimit
        let totalLimit = store.historyRetentionTotalLimit
        var kept = 0
        var perToolCounts: [String: Int] = [:]
        for record in store.historyRecords {
            guard kept < totalLimit else { break }
            let count = perToolCounts[record.tool, default: 0]
            guard count < perToolLimit else { continue }
            perToolCounts[record.tool] = count + 1
            kept += 1
        }
        return max(store.historyRecords.count - kept, 0)
    }

    var localBackupDate: Date? {
        guard localBackupLastSuccessAt > 0 else { return nil }
        return Date(timeIntervalSince1970: localBackupLastSuccessAt)
    }

    var cloudBackupDate: Date? {
        guard cloudBackupLastSuccessAt > 0 else { return nil }
        return Date(timeIntervalSince1970: cloudBackupLastSuccessAt)
    }

    var latestBackupDate: Date? {
        [localBackupDate, cloudBackupDate].compactMap { $0 }.max()
    }

    var hasAnyBackupRecord: Bool {
        latestBackupDate != nil
    }

    var backupAgeDays: Int? {
        guard let latestBackupDate else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: latestBackupDate)
        let end = calendar.startOfDay(for: Date())
        return max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)
    }

    var isBackupStale: Bool {
        guard let backupAgeDays else { return true }
        return backupAgeDays >= max(1, backupHealthReminderDays)
    }

    var dataHealthIssueCount: Int {
        store.latestDataHealthScan?.totalIssues ?? 0
    }

    var hasDataHealthScan: Bool {
        store.latestDataHealthScan != nil
    }

    var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var primarySafetyAction: DataSafetyPrimaryAction {
        if !hasAnyBackupRecord {
            return DataSafetyPrimaryAction(
                title: String(localized: "先生成一份备份"),
                message: String(localized: "当前没有成功备份记录，清理、恢复或导入前先生成本地 ZIP 或 iCloud 备份。"),
                buttonTitle: String(localized: "去备份"),
                systemImage: "externaldrive.badge.plus",
                tone: .warning,
                target: .backup
            )
        }

        if isBackupStale {
            let days = Int64(backupAgeDays ?? 0)
            return DataSafetyPrimaryAction(
                title: String(localized: "备份需要更新"),
                message: String(
                    format: String(localized: "最近一次备份已过 %lld 天，超过当前提醒阈值。清理或交付前建议先补一份新备份。"),
                    days
                ),
                buttonTitle: String(localized: "去备份"),
                systemImage: "externaldrive.badge.plus",
                tone: .warning,
                target: .backup
            )
        }

        if dataHealthIssueCount > 0 {
            return DataSafetyPrimaryAction(
                title: String(localized: "先修复数据异常"),
                message: String(
                    format: String(localized: "数据健康扫描发现 %lld 个异常，建议逐项修复后再清理或导出。"),
                    Int64(dataHealthIssueCount)
                ),
                buttonTitle: String(localized: "去修复"),
                systemImage: "stethoscope",
                tone: .risk,
                target: .health
            )
        }

        if historyTrimCount > 0 || cleanupTrashBatchCount > 0 {
            return DataSafetyPrimaryAction(
                title: String(localized: "有空间可清理"),
                message: cleanupRiskMessage,
                buttonTitle: String(localized: "去清理"),
                systemImage: "clock.arrow.circlepath",
                tone: .warning,
                target: .storage
            )
        }

        if cloudBackupDate == nil {
            return DataSafetyPrimaryAction(
                title: String(localized: "建议补一次云备份"),
                message: String(localized: "本机已有备份记录，但还没有云端成功记录。重要项目建议再同步到 iCloud。"),
                buttonTitle: String(localized: "去备份"),
                systemImage: "icloud.and.arrow.up",
                tone: .doc,
                target: .backup
            )
        }

        return DataSafetyPrimaryAction(
            title: String(localized: "数据安全状态正常"),
            message: String(localized: "已经具备基础备份记录，可以继续做健康检查或导出交付。"),
            buttonTitle: String(localized: "查看健康检查"),
            systemImage: "checkmark.shield.fill",
            tone: .success,
            target: .health
        )
    }

    var cleanupRiskMessage: String {
        switch (historyTrimCount, cleanupTrashBatchCount) {
        case let (historyCount, trashCount) where historyCount > 0 && trashCount > 0:
            return String(
                format: String(localized: "当前可按策略清理 %lld 条计算历史，回收站还有 %lld 个可恢复批次。"),
                Int64(historyCount),
                Int64(trashCount)
            )
        case let (historyCount, _) where historyCount > 0:
            return String(
                format: String(localized: "当前可按保留策略清理 %lld 条计算历史，清理前已检测到备份记录。"),
                Int64(historyCount)
            )
        case let (_, trashCount) where trashCount > 0:
            return String(
                format: String(localized: "清理回收站还有 %lld 个可恢复批次，可继续恢复或永久清理。"),
                Int64(trashCount)
            )
        default:
            return String(localized: "可以查看大文件、回收站和项目附件占用。")
        }
    }

    var backupStatusValue: String {
        guard let backupAgeDays else {
            return String(localized: "未备份")
        }
        if backupAgeDays == 0 {
            return String(localized: "今天已备份")
        }
        return String(
            format: String(localized: "%lld 天前备份"),
            Int64(backupAgeDays)
        )
    }

    var backupStatusTone: StatusChipTone {
        if !hasAnyBackupRecord || isBackupStale {
            return .warning
        }
        return .success
    }

    var healthStatusValue: String {
        guard hasDataHealthScan else {
            return String(localized: "待扫描")
        }
        guard dataHealthIssueCount > 0 else {
            return String(localized: "正常")
        }
        return String(
            format: String(localized: "%lld 个异常"),
            Int64(dataHealthIssueCount)
        )
    }

    var healthStatusTone: StatusChipTone {
        guard hasDataHealthScan else {
            return .neutral
        }
        return dataHealthIssueCount > 0 ? .risk : .success
    }

    var cleanupStatusValue: String {
        if cleanupTrashBatchCount > 0 {
            return String(
                format: String(localized: "%lld 个回收批次"),
                Int64(cleanupTrashBatchCount)
            )
        }
        if historyTrimCount > 0 {
            return String(
                format: String(localized: "%lld 条待清理"),
                Int64(historyTrimCount)
            )
        }
        return String(localized: "正常")
    }

    var cleanupStatusTone: StatusChipTone {
        (cleanupTrashBatchCount > 0 || historyTrimCount > 0) ? .warning : .success
    }

    var secondaryShortcutCards: [DataManagementShortcutCardModel] {
        let targets: [DataSafetySecondaryTarget] = [.backupAndRestore, .health, .storage, .export]
        return targets.map { target in
            DataManagementShortcutCardModel(
                id: shortcutIdentifier(target),
                target: target,
                title: shortcutTitle(target),
                subtitle: shortcutSubtitle(target),
                icon: shortcutIcon(target),
                tone: shortcutTone(target),
                isSelected: isSelectedSecondaryTarget(target)
            )
        }
    }

    var selectedTabSummary: some View {
        HStack(alignment: .top, spacing: AppSpacing.tight) {
            Image(systemName: selectedTab.icon)
                .foregroundStyle(.appWarning)
                .frame(width: 18, height: 18)
                .padding(.top, 1)
            Text(selectedTab.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
    }

    var calculationHistoryCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight * 0.6) {
            HStack(spacing: AppSpacing.tight) {
                Label(
                    String(format: String(localized: "计算历史 %lld 条"), Int64(store.historyRecords.count)),
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "清空计算历史"), role: .destructive) {
                    showClearHistoryConfirm = true
                }
                .font(.caption.weight(.semibold))
            }
            HStack(spacing: AppSpacing.tight) {
                Text(
                    String(
                        format: String(localized: "保留策略：每工具最近 %lld 条，总计最多 %lld 条"),
                        Int64(store.historyRetentionPerToolLimit),
                        Int64(store.historyRetentionTotalLimit)
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                Spacer()
                if historyTrimCount > 0 {
                    Button(String(format: String(localized: "按策略清理 %lld 条"), Int64(historyTrimCount))) {
                        trimCalculationHistoryWithUndo()
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.appWarning)
                }
            }
        }
        .padding(.horizontal)
    }

    func selectSecondaryTarget(_ target: DataSafetySecondaryTarget) {
        switch target {
        case .backupAndRestore:
            selectedTab = .backupAndRestore
        case .health:
            selectedTab = .healthAndCleanup
            healthCleanupSection = .health
        case .storage:
            selectedTab = .healthAndCleanup
            healthCleanupSection = .storage
        case .export:
            selectedTab = .export
        }
    }

    func isSelectedSecondaryTarget(_ target: DataSafetySecondaryTarget) -> Bool {
        switch target {
        case .backupAndRestore:
            return selectedTab == .backupAndRestore
        case .health:
            return selectedTab == .healthAndCleanup && healthCleanupSection == .health
        case .storage:
            return selectedTab == .healthAndCleanup && healthCleanupSection == .storage
        case .export:
            return selectedTab == .export
        }
    }

    func shortcutTitle(_ target: DataSafetySecondaryTarget) -> String {
        switch target {
        case .backupAndRestore:
            return String(localized: "备份恢复")
        case .health:
            return String(localized: "健康修复")
        case .storage:
            return String(localized: "空间清理")
        case .export:
            return String(localized: "导出交付")
        }
    }

    func shortcutSubtitle(_ target: DataSafetySecondaryTarget) -> String {
        switch target {
        case .backupAndRestore:
            return backupStatusValue
        case .health:
            return healthStatusValue
        case .storage:
            return cleanupStatusValue
        case .export:
            return String(localized: "交付包与表格")
        }
    }

    func shortcutIcon(_ target: DataSafetySecondaryTarget) -> String {
        switch target {
        case .backupAndRestore:
            return "externaldrive.badge.icloud"
        case .health:
            return "stethoscope"
        case .storage:
            return "internaldrive"
        case .export:
            return "square.and.arrow.up"
        }
    }

    func shortcutTone(_ target: DataSafetySecondaryTarget) -> StatusChipTone {
        switch target {
        case .backupAndRestore:
            return backupStatusTone
        case .health:
            return healthStatusTone
        case .storage:
            return cleanupStatusTone
        case .export:
            return .doc
        }
    }

    func shortcutIdentifier(_ target: DataSafetySecondaryTarget) -> String {
        switch target {
        case .backupAndRestore:
            return "backup"
        case .health:
            return "health"
        case .storage:
            return "storage"
        case .export:
            return "export"
        }
    }

    func performPrimarySafetyAction(_ action: DataSafetyPrimaryAction) {
        switch action.target {
        case .backup:
            selectedTab = .backupAndRestore
        case .health:
            selectedTab = .healthAndCleanup
            healthCleanupSection = .health
        case .storage:
            selectedTab = .healthAndCleanup
            healthCleanupSection = .storage
        }
    }
}
