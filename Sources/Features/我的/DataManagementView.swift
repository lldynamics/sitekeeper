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
    case export
    case backup
    case restore
    case healthAndCleanup

    var displayName: String {
        switch self {
        case .export:
            return String(localized: "导出")
        case .backup:
            return String(localized: "备份")
        case .restore:
            return String(localized: "导入恢复")
        case .healthAndCleanup:
            return String(localized: "体检与清理")
        }
    }

    var icon: String {
        switch self {
        case .export:
            return "square.and.arrow.up"
        case .backup:
            return "externaldrive"
        case .restore:
            return "arrow.clockwise.icloud"
        case .healthAndCleanup:
            return "cross.case.fill"
        }
    }

    var summary: String {
        switch self {
        case .export:
            return String(localized: "按项目或日期筛选后导出 CSV / Excel / PDF / ZIP。")
        case .backup:
            return String(localized: "创建本地或 iCloud 备份，并查看备份体积与恢复建议。")
        case .restore:
            return String(localized: "导入备份并预览差异，可选择合并或覆盖当前数据。")
        case .healthAndCleanup:
            return String(localized: "统一查看健康检查和存储占用，集中完成体检、修复与清理。")
        }
    }

    static func from(route: DataManagementRoute?) -> Self {
        guard let route else { return .backup }
        switch route {
        case .export:
            return .export
        case .backup:
            return .backup
        case .restore:
            return .restore
        case .health, .storage, .audit:
            return .healthAndCleanup
        }
    }
}

struct DataManagementView: View {
    @Environment(DataStore.self) private var store
    @State private var selectedTab: DataManagementTab
    @State private var healthCleanupSection: HealthCleanupSection
    @State private var showClearHistoryConfirm = false
    @State private var showSampleDataImportConfirm = false
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()

    init(initialRoute: DataManagementRoute? = nil) {
        _selectedTab = State(initialValue: DataManagementTab.from(route: initialRoute))
        _healthCleanupSection = State(initialValue: HealthCleanupSection.from(route: initialRoute))
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

    var body: some View {
        VStack(spacing: AppSpacing.normal) {
            Picker(String(localized: "数据管理"), selection: $selectedTab) {
                ForEach(DataManagementTab.allCases, id: \.self) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

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

            if selectedTab == .restore {
                sampleDataImportCard
            }

            if !store.historyRecords.isEmpty {
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

            Group {
                switch selectedTab {
                case .export:
                    ExportView(showsNavigationTitle: false)
                case .backup:
                    BackupView(showsNavigationTitle: false)
                case .restore:
                    BackupView(autoOpenImporter: true, showsNavigationTitle: false)
                case .healthAndCleanup:
                    healthAndCleanupContent
                }
            }
            .id(selectedTab)
        }
        .navigationTitle(String(localized: "数据管理"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(String(localized: "清空所有计算历史？"), isPresented: $showClearHistoryConfirm) {
            Button(String(localized: "清空"), role: .destructive) { clearCalculationHistoryWithUndo() }
            Button(String(localized: "取消"), role: .cancel) {}
        }
        .alert(String(localized: "恢复测试数据？"), isPresented: $showSampleDataImportConfirm) {
            Button(String(localized: "清空并导入"), role: .destructive) {
                importDebugSampleDataWithNotice()
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

    @ViewBuilder
    private var sampleDataImportCard: some View {
#if DEBUG
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            Label(String(localized: "测试数据导入"), systemImage: "testtube.2")
                .font(.subheadline.weight(.semibold))

            Text(String(localized: "开发构建下可一键恢复测试环境。当前样例包含项目、材料、报价、进度、图纸、票据、照片与附件。"))
                .font(.caption)
                .foregroundStyle(.secondary)

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
#else
        EmptyView()
#endif
    }

    private var healthAndCleanupContent: some View {
        VStack(spacing: AppSpacing.normal) {
            Picker(String(localized: "体检与清理"), selection: $healthCleanupSection) {
                ForEach(HealthCleanupSection.allCases, id: \.self) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

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

    private func importDebugSampleDataWithNotice() {
#if DEBUG
        let summary = String(localized: "清空并导入测试数据")
        let detail = String(localized: "开发构建测试数据恢复")
        OperationAuditLog.record(
            action: .import,
            outcome: .started,
            summary: summary,
            detail: detail,
            source: "DataManagementView"
        )

        if store.importDebugSampleData(replacingExisting: true) {
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
#endif
    }
}
