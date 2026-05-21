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
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()
    @AppStorage(UserPreferenceKeys.localBackupLastSuccessAt) private var localBackupLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.cloudBackupLastSuccessAt) private var cloudBackupLastSuccessAt = 0.0

    init(initialRoute: DataManagementRoute? = nil) {
        _selectedTab = State(initialValue: DataManagementTab.from(route: initialRoute))
        _healthCleanupSection = State(initialValue: HealthCleanupSection.from(route: initialRoute))
        _shouldAutoOpenBackupImporter = State(initialValue: initialRoute == .restore)
    }

    private var sampleDataImportEnabled: Bool {
        AppFeatureFlags.allowsSampleDataImport || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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

        if historyTrimCount > 0 {
            return DataSafetyPrimaryAction(
                title: String(localized: "有计算历史可按策略清理"),
                message: String(
                    format: String(localized: "当前可按保留策略清理 %lld 条计算历史，清理前已检测到备份记录。"),
                    Int64(historyTrimCount)
                ),
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

    var body: some View {
        VStack(spacing: usesWideLayout ? AppSpacing.normal : AppSpacing.tight) {
            if usesWideLayout {
                dataSafetyHeader
            }

            dataManagementTabPicker

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
        .operationToast(notice: $operationNotice)
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
    }

    private var dataManagementTabPicker: some View {
        Picker(String(localized: "数据管理"), selection: $selectedTab) {
            ForEach(DataManagementTab.allCases, id: \.self) { tab in
                Text(tab.displayName).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, usesWideLayout ? 8 : 6)
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
                    Label(String(localized: "数据安全中心"), systemImage: "externaldrive.badge.shield.half.filled")
                        .font(.headline)

                    Text(String(localized: "把备份健康、导入恢复、导出交付和清理风险收进同一条操作链路，先判断风险，再执行动作。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: AppSpacing.tight) {
                        statusChip(
                            title: String(localized: "本地备份"),
                            value: localBackupDate.map(relativeDateText) ?? String(localized: "未完成"),
                            tone: localBackupDate == nil ? .warning : .success
                        )
                        statusChip(
                            title: String(localized: "云备份"),
                            value: cloudBackupDate.map(relativeDateText) ?? String(localized: "未同步"),
                            tone: cloudBackupDate == nil ? .neutral : .primary
                        )
                        statusChip(
                            title: String(localized: "清理风险"),
                            value: historyTrimCount > 0 ? String(format: String(localized: "%lld 条待清理"), Int64(historyTrimCount)) : String(localized: "正常"),
                            tone: historyTrimCount > 0 ? .warning : .success
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

    private func relativeDateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
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
