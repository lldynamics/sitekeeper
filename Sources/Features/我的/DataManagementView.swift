import SwiftUI

enum DataManagementRoute: Hashable {
    case export
    case backup
    case restore
    case health
    case storage
    case audit
}

private enum HealthCleanupSection: CaseIterable {
    case health
    case storage
    case audit

    var displayName: String {
        switch self {
        case .health:
            return String(localized: "健康检查")
        case .storage:
            return String(localized: "存储清理")
        case .audit:
            return String(localized: "审计")
        }
    }

    var icon: String {
        switch self {
        case .health:
            return "stethoscope"
        case .storage:
            return "internaldrive"
        case .audit:
            return "checklist.checked"
        }
    }

    var summary: String {
        switch self {
        case .health:
            return String(localized: "扫描缺失文件、无效关联与孤立文件，并支持一键修复。")
        case .storage:
            return String(localized: "查看照片/视频/图纸原件/备份/历史计算占用，支持按项目清理附件文件。")
        case .audit:
            return String(localized: "查看导入、恢复、清理、修复、删除等高风险操作记录。")
        }
    }

    static func from(route: DataManagementRoute?) -> Self {
        guard let route else { return .health }
        switch route {
        case .storage:
            return .storage
        case .audit:
            return .audit
        default:
            return .health
        }
    }
}

private enum DataManagementTab: CaseIterable {
    case backupAndRestore
    case export
    case healthAndCleanup

    var displayName: String {
        switch self {
        case .backupAndRestore:
            return String(localized: "备份恢复")
        case .export:
            return String(localized: "导出交付")
        case .healthAndCleanup:
            return String(localized: "体检清理")
        }
    }

    var icon: String {
        switch self {
        case .export:
            return "square.and.arrow.up"
        case .backupAndRestore:
            return "arrow.triangle.2.circlepath.icloud"
        case .healthAndCleanup:
            return "cross.case.fill"
        }
    }

    var summary: String {
        switch self {
        case .backupAndRestore:
            return String(localized: "统一完成本地/iCloud 备份、恢复预览与导入校验。")
        case .export:
            return String(localized: "按项目或日期筛选后导出 CSV / Excel / PDF。")
        case .healthAndCleanup:
            return String(localized: "统一查看健康检查、存储占用、审计记录与清理风险。")
        }
    }

    static func from(route: DataManagementRoute?) -> Self {
        guard let route else { return .backupAndRestore }
        switch route {
        case .export:
            return .export
        case .backup, .restore:
            return .backupAndRestore
        case .health, .storage, .audit:
            return .healthAndCleanup
        }
    }
}

private enum DataSafetyPrimaryTarget {
    case backup
    case health
    case storage
}

private enum DataSafetySecondaryTarget: Hashable {
    case backupAndRestore
    case health
    case storage
    case export
}

private struct DataSafetyPrimaryAction {
    let title: String
    let message: String
    let buttonTitle: String
    let systemImage: String
    let tone: StatusChipTone
    let target: DataSafetyPrimaryTarget
}

struct DataManagementView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: DataManagementTab
    @State private var healthCleanupSection: HealthCleanupSection
    @State private var shouldAutoOpenBackupImporter: Bool
    @State private var showClearHistoryConfirm = false
    @State private var showSampleDataImportConfirm = false
    @State private var showUITestOverwriteImportConfirm = false
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()
    @State private var cleanupTrashBatchCount = 0
    @AppStorage(UserPreferenceKeys.localBackupLastSuccessAt) private var localBackupLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.cloudBackupLastSuccessAt) private var cloudBackupLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.backupHealthReminderDays) private var backupHealthReminderDays = 7

    init(initialRoute: DataManagementRoute? = nil) {
        _selectedTab = State(initialValue: DataManagementTab.from(route: initialRoute))
        _healthCleanupSection = State(initialValue: HealthCleanupSection.from(route: initialRoute))
        _shouldAutoOpenBackupImporter = State(initialValue: initialRoute == .restore)
    }

    private var sampleDataImportEnabled: Bool {
        AppFeatureFlags.allowsSampleDataImport || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private var showsUITestBackupPreviewShortcut: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-backup-preview")
            || ProcessInfo.processInfo.environment["UITEST_BACKUP_PREVIEW"] == "1"
    }

    private var historyTrimCount: Int {
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

    private var localBackupDate: Date? {
        guard localBackupLastSuccessAt > 0 else { return nil }
        return Date(timeIntervalSince1970: localBackupLastSuccessAt)
    }

    private var cloudBackupDate: Date? {
        guard cloudBackupLastSuccessAt > 0 else { return nil }
        return Date(timeIntervalSince1970: cloudBackupLastSuccessAt)
    }

    private var latestBackupDate: Date? {
        [localBackupDate, cloudBackupDate].compactMap { $0 }.max()
    }

    private var hasAnyBackupRecord: Bool {
        latestBackupDate != nil
    }

    private var backupAgeDays: Int? {
        guard let latestBackupDate else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: latestBackupDate)
        let end = calendar.startOfDay(for: Date())
        return max(calendar.dateComponents([.day], from: start, to: end).day ?? 0, 0)
    }

    private var isBackupStale: Bool {
        guard let backupAgeDays else { return true }
        return backupAgeDays >= max(1, backupHealthReminderDays)
    }

    private var dataHealthIssueCount: Int {
        store.latestDataHealthScan?.totalIssues ?? 0
    }

    private var hasDataHealthScan: Bool {
        store.latestDataHealthScan != nil
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var primarySafetyAction: DataSafetyPrimaryAction {
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

    private var cleanupRiskMessage: String {
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

    private var backupStatusValue: String {
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

    private var backupStatusTone: StatusChipTone {
        if !hasAnyBackupRecord || isBackupStale {
            return .warning
        }
        return .success
    }

    private var healthStatusValue: String {
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

    private var healthStatusTone: StatusChipTone {
        guard hasDataHealthScan else {
            return .neutral
        }
        return dataHealthIssueCount > 0 ? .risk : .success
    }

    private var cleanupStatusValue: String {
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

    private var cleanupStatusTone: StatusChipTone {
        (cleanupTrashBatchCount > 0 || historyTrimCount > 0) ? .warning : .success
    }

    var body: some View {
        VStack(spacing: usesWideLayout ? AppSpacing.normal : AppSpacing.tight) {
            dataSafetyHeader

            secondaryFlowShortcuts

            if usesWideLayout {
                selectedTabSummary

                if selectedTab == .backupAndRestore, sampleDataImportEnabled {
                    sampleDataImportCard
                }

                if !store.historyRecords.isEmpty {
                    calculationHistoryCard
                }
            }

            Group {
                switch selectedTab {
                case .export:
                    ExportView(showsNavigationTitle: false)
                case .backupAndRestore:
                    BackupView(
                        autoOpenImporter: shouldAutoOpenBackupImporter,
                        showsNavigationTitle: false,
                        onAutoOpenImporterConsumed: {
                            shouldAutoOpenBackupImporter = false
                        }
                    )
                case .healthAndCleanup:
                    healthAndCleanupContent
                }
            }
            .id(selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(String(localized: "数据安全中心"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !usesWideLayout {
                ToolbarItem(placement: .topBarTrailing) {
                    compactActionMenu
                }
            }
        }
        .confirmationDialog(String(localized: "清空所有计算历史？"), isPresented: $showClearHistoryConfirm) {
            Button(String(localized: "清空"), role: .destructive) { clearCalculationHistoryWithUndo() }
            Button(String(localized: "取消"), role: .cancel) {}
        }
        .alert(String(localized: "恢复测试数据？"), isPresented: $showSampleDataImportConfirm) {
            Button(String(localized: "清空并导入"), role: .destructive) {
                importSampleDataWithNotice()
            }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "会清空当前本机业务数据，并恢复一套更完整的测试项目、报价、图纸、票据、照片和附件样例。"))
        }
        .alert(String(localized: "确认覆盖导入？"), isPresented: $showUITestOverwriteImportConfirm) {
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(String(localized: "覆盖会删除当前本机数据，请先导出备份。"))
        }
        .operationToast(notice: $operationNotice)
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
        .onAppear {
            refreshRiskSnapshot()
        }
        .onChange(of: selectedTab) { _, _ in
            refreshRiskSnapshot()
        }
    }

    private var selectedTabSummary: some View {
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

    private var secondaryFlowShortcuts: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: usesWideLayout ? 154 : 134), spacing: AppSpacing.tight)],
            alignment: .leading,
            spacing: AppSpacing.tight
        ) {
            shortcutButton(.backupAndRestore)
            shortcutButton(.health)
            shortcutButton(.storage)
            shortcutButton(.export)
        }
        .padding(.horizontal)
    }

    private func shortcutButton(_ target: DataSafetySecondaryTarget) -> some View {
        let selected = isSelectedSecondaryTarget(target)
        let tone = shortcutTone(target)
        return Button {
            selectSecondaryTarget(target)
        } label: {
            AppPanel(
                tone: selected ? selectedCardTone(for: tone) : .grouped,
                cornerRadius: 10,
                padding: 10,
                stroke: selected ? tone.tint.opacity(0.3) : Color.appStrokeSecondary.opacity(0.35)
            ) {
                HStack(alignment: .top, spacing: AppSpacing.tight) {
                    Image(systemName: shortcutIcon(target))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tone.tint)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(shortcutTitle(target))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(shortcutSubtitle(target))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("data-management-shortcut-\(shortcutIdentifier(target))")
    }

    private var calculationHistoryCard: some View {
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

    private var compactActionMenu: some View {
        Menu {
            Button {
                selectedTab = .backupAndRestore
            } label: {
                Label(String(localized: "去备份"), systemImage: "externaldrive.badge.plus")
            }

            Button {
                selectedTab = .backupAndRestore
                shouldAutoOpenBackupImporter = true
            } label: {
                Label(String(localized: "导入恢复"), systemImage: "square.and.arrow.down")
            }

            Button {
                selectedTab = .export
            } label: {
                Label(String(localized: "导出交付"), systemImage: "square.and.arrow.up")
            }

            Divider()

            Button {
                selectedTab = .healthAndCleanup
                healthCleanupSection = .health
            } label: {
                Label(String(localized: "健康检查"), systemImage: "stethoscope")
            }

            Button {
                selectedTab = .healthAndCleanup
                healthCleanupSection = .storage
            } label: {
                Label(String(localized: "存储清理"), systemImage: "internaldrive")
            }

            Button {
                selectedTab = .healthAndCleanup
                healthCleanupSection = .audit
            } label: {
                Label(String(localized: "审计"), systemImage: "checklist.checked")
            }

            if sampleDataImportEnabled || !store.historyRecords.isEmpty {
                Divider()
            }

            if showsUITestBackupPreviewShortcut {
                Button {
                    selectedTab = .backupAndRestore
                } label: {
                    Label(String(localized: "UI测试：模拟覆盖导入预览"), systemImage: "doc.text.magnifyingglass")
                }
                .accessibilityIdentifier("ui-test-backup-preview")

                Button {
                    showUITestOverwriteImportConfirm = true
                } label: {
                    Label(String(localized: "UI测试：触发覆盖二次确认"), systemImage: "exclamationmark.triangle")
                }
                .accessibilityIdentifier("ui-test-overwrite-confirm")
            }

            if sampleDataImportEnabled {
                Button(role: store.hasAnyBusinessData ? .destructive : nil) {
                    showSampleDataImportConfirm = true
                } label: {
                    Label(String(localized: "导入测试数据"), systemImage: "testtube.2")
                }
            }

            if !store.historyRecords.isEmpty {
                if historyTrimCount > 0 {
                    Button {
                        trimCalculationHistoryWithUndo()
                    } label: {
                        Label(String(format: String(localized: "按策略清理 %lld 条"), Int64(historyTrimCount)), systemImage: "clock.arrow.circlepath")
                    }
                }

                Button(role: .destructive) {
                    showClearHistoryConfirm = true
                } label: {
                    Label(String(localized: "清空计算历史"), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .visibleIconStyle()
        }
        .accessibilityLabel(String(localized: "数据安全中心操作"))
        .accessibilityIdentifier("data-management-actions-menu")
    }

    private func selectSecondaryTarget(_ target: DataSafetySecondaryTarget) {
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

    private func isSelectedSecondaryTarget(_ target: DataSafetySecondaryTarget) -> Bool {
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

    private func shortcutTitle(_ target: DataSafetySecondaryTarget) -> String {
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

    private func shortcutSubtitle(_ target: DataSafetySecondaryTarget) -> String {
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

    private func shortcutIcon(_ target: DataSafetySecondaryTarget) -> String {
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

    private func shortcutTone(_ target: DataSafetySecondaryTarget) -> StatusChipTone {
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

    private func shortcutIdentifier(_ target: DataSafetySecondaryTarget) -> String {
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

    @ViewBuilder
    private var dataSafetyHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.normal) {
            AppPanel(
                tone: .grouped,
                cornerRadius: 12,
                padding: AppSpacing.normal,
                stroke: Color.appStrokeSecondary.opacity(0.45)
            ) {
                VStack(alignment: .leading, spacing: AppSpacing.tight) {
                    Label(String(localized: "数据安全状态"), systemImage: "externaldrive.badge.shield.half.filled")
                        .font(.headline)

                    Text(String(localized: "先看当前风险，再选择备份、修复、清理或导出；普通入口按处理顺序排列。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: AppSpacing.tight) {
                        statusChip(
                            title: String(localized: "备份"),
                            value: backupStatusValue,
                            tone: backupStatusTone
                        )
                        statusChip(
                            title: String(localized: "健康"),
                            value: healthStatusValue,
                            tone: healthStatusTone
                        )
                        statusChip(
                            title: String(localized: "清理"),
                            value: cleanupStatusValue,
                            tone: cleanupStatusTone
                        )
                    }

                    primarySafetyActionCard(primarySafetyAction)
                }
            }
            .padding(.horizontal)
        }
    }

    private func primarySafetyActionCard(_ action: DataSafetyPrimaryAction) -> some View {
        AppPanel(
            tone: selectedCardTone(for: action.tone),
            cornerRadius: 10,
            padding: 12,
            stroke: action.tone.tint.opacity(0.2)
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                HStack(alignment: .top, spacing: AppSpacing.tight) {
                    Image(systemName: action.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(action.tone.tint)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(action.title)
                            .font(.subheadline.weight(.semibold))
                        Text(action.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                }

                HStack(spacing: AppSpacing.tight) {
                    Button {
                        performPrimarySafetyAction(action)
                    } label: {
                        Label(action.buttonTitle, systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appProminent(tint: action.tone.tint))

                    Menu {
                        Button {
                            selectedTab = .backupAndRestore
                            shouldAutoOpenBackupImporter = true
                        } label: {
                            Label(String(localized: "导入恢复"), systemImage: "square.and.arrow.down")
                        }

                        Button {
                            selectedTab = .export
                        } label: {
                            Label(String(localized: "导出交付"), systemImage: "square.and.arrow.up")
                        }

                        Button {
                            selectedTab = .healthAndCleanup
                            healthCleanupSection = .storage
                        } label: {
                            Label(String(localized: "存储清理"), systemImage: "internaldrive")
                        }

                        Button {
                            selectedTab = .healthAndCleanup
                            healthCleanupSection = .audit
                        } label: {
                            Label(String(localized: "审计"), systemImage: "checklist.checked")
                        }
                    } label: {
                        Label(String(localized: "更多操作"), systemImage: "ellipsis.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func performPrimarySafetyAction(_ action: DataSafetyPrimaryAction) {
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

    private func refreshRiskSnapshot() {
        cleanupTrashBatchCount = StorageCleanupTrashStore.loadBatches().count
        store.scheduleDataHealthScanIfStale(reason: .scheduled)
    }

    private func statusChip(title: String, value: String, tone: StatusChipTone) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            StatusChip(text: chipLabel(for: tone), tone: tone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipLabel(for tone: StatusChipTone) -> String {
        switch tone {
        case .success:
            return String(localized: "正常")
        case .warning:
            return String(localized: "注意")
        case .risk:
            return String(localized: "风险")
        case .primary:
            return String(localized: "已启用")
        default:
            return String(localized: "待处理")
        }
    }

    private func selectedCardTone(for tone: StatusChipTone) -> AppSurfaceTone {
        switch tone {
        case .success:
            return .tinted(Color.appSuccessSurfaceSubtle)
        case .warning:
            return .tinted(Color.appWarning.opacity(0.12))
        case .risk:
            return .tinted(Color.appRiskSurface)
        case .doc:
            return .tinted(Color.appDocSurfaceSubtle)
        case .primary:
            return .tinted(Color.appPrimarySurfaceSubtle)
        default:
            return .grouped
        }
    }

    @ViewBuilder
    private var sampleDataImportCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            Label(String(localized: "测试数据导入"), systemImage: "testtube.2")
                .font(.subheadline.weight(.semibold))

            Text(String(localized: "可一键恢复一套更完整的测试环境。当前样例包含多个项目、材料、报价、进度、图纸、票据、照片与附件。"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Label(String(localized: "当前环境允许导入测试数据。"), systemImage: "checkmark.shield")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.appSuccess)

            if store.hasAnyBusinessData {
                Label(String(localized: "会覆盖当前本机数据，建议先导出备份 ZIP。"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.appRisk)
            }

            Button {
                showSampleDataImportConfirm = true
            } label: {
                Label(String(localized: "清空并导入测试数据"), systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.appWarning)
            .accessibilityIdentifier("data-management-import-sample-data")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .padding(.horizontal)
    }

    private var healthAndCleanupContent: some View {
        VStack(spacing: usesWideLayout ? AppSpacing.normal : AppSpacing.tight) {
            Picker(String(localized: "体检与清理"), selection: $healthCleanupSection) {
                ForEach(HealthCleanupSection.allCases, id: \.self) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if usesWideLayout {
                HStack(alignment: .top, spacing: AppSpacing.tight) {
                    Image(systemName: healthCleanupSection.icon)
                        .foregroundStyle(.appWarning)
                        .frame(width: 18, height: 18)
                        .padding(.top, 1)
                    Text(healthCleanupSection.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            }

            Group {
                switch healthCleanupSection {
                case .health:
                    DataHealthView(showsNavigationTitle: false)
                case .storage:
                    StorageCleanupCenterView(showsNavigationTitle: false)
                case .audit:
                    OperationAuditLogView(showsNavigationTitle: false)
                }
            }
            .id(healthCleanupSection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func clearCalculationHistoryWithUndo() {
        let count = store.historyRecords.count
        let deletion = store.clearCalculationHistory(
            audit: DataStoreDeletionAuditContext(
                summary: String(format: String(localized: "清空计算历史 %lld 条"), Int64(count)),
                source: "DataManagementView"
            )
        )
        queueHistoryDeletion(
            deletion,
            message: String(format: String(localized: "已清空 %lld 条计算历史"), Int64(deletion.deletedCount))
        )
    }

    private func trimCalculationHistoryWithUndo() {
        let count = historyTrimCount
        let deletion = store.enforceCalculationHistoryRetention(
            audit: DataStoreDeletionAuditContext(
                summary: String(format: String(localized: "按保留策略清理计算历史 %lld 条"), Int64(count)),
                source: "DataManagementView"
            )
        )
        queueHistoryDeletion(
            deletion,
            message: String(format: String(localized: "已按策略清理 %lld 条计算历史"), Int64(deletion.deletedCount))
        )
    }

    private func queueHistoryDeletion(_ deletion: DataStoreRemovalResult<HistoryRecord>, message: String) {
        guard !deletion.isEmpty else { return }
        undoableDeletion.queue(
            notice: $operationNotice,
            message: message,
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.restoreHistoryRecords(from: deletion)
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    private func importSampleDataWithNotice() {
        let summary = String(localized: "清空并导入测试数据")
        let detail = String(localized: "测试数据恢复")
        OperationAuditLog.record(
            action: .import,
            outcome: .started,
            summary: summary,
            detail: detail,
            source: "DataManagementView"
        )

        if store.importSampleData(replacingExisting: true) {
            store.persistenceErrorMessage = nil
            OperationAuditLog.record(
                action: .import,
                outcome: .succeeded,
                summary: summary,
                detail: detail,
                source: "DataManagementView"
            )
            operationNotice = .info(String(localized: "已恢复测试数据"))
        } else {
            let errorDetail = store.persistenceErrorMessage ?? String(localized: "测试数据导入失败")
            OperationAuditLog.record(
                action: .import,
                outcome: .failed,
                summary: summary,
                detail: errorDetail,
                source: "DataManagementView"
            )
            operationNotice = .info(errorDetail)
        }
    }
}
