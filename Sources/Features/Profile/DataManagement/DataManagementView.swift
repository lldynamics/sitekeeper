import SwiftUI

struct DataManagementView: View {
    @Environment(DataStore.self) var store
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @State var selectedTab: DataManagementTab
    @State var healthCleanupSection: HealthCleanupSection
    @State var shouldAutoOpenBackupImporter: Bool
    @State var showClearHistoryConfirm = false
    @State var showSampleDataImportConfirm = false
    @State var showUITestOverwriteImportConfirm = false
    @State var operationNotice: OperationToastNotice?
    @State var undoableDeletion = UndoableDeletionCoordinator()
    @State var cleanupTrashBatchCount = 0
    @State var isCompactSafetyHeader = false
    @State private var lastContentOffset: CGFloat = 0
    @State var pendingHealthRepairRequestID: UUID?
    @AppStorage(UserPreferenceKeys.localBackupLastSuccessAt) var localBackupLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.cloudBackupLastSuccessAt) var cloudBackupLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.backupHealthReminderDays) var backupHealthReminderDays = 7

    init(initialRoute: DataManagementRoute? = nil) {
        _selectedTab = State(initialValue: DataManagementTab.from(route: initialRoute))
        _healthCleanupSection = State(initialValue: HealthCleanupSection.from(route: initialRoute))
        _shouldAutoOpenBackupImporter = State(initialValue: initialRoute == .restore)
    }

    var body: some View {
        lifecycleContent
    }

    private var lifecycleContent: some View {
        dialogContent
            .operationToast(notice: $operationNotice)
            .onDisappear {
                undoableDeletion.flushPendingCommit()
            }
            .onAppear {
                refreshRiskSnapshot()
                isCompactSafetyHeader = false
                lastContentOffset = 0
            }
            .onChange(of: selectedTab) { _, _ in
                refreshRiskSnapshot()
                withAnimation(.snappy) {
                    isCompactSafetyHeader = false
                }
                lastContentOffset = 0
            }
    }

    private var dialogContent: some View {
        navigationContent
            .confirmationDialog(AppLocalization.string("清空所有计算历史？"), isPresented: $showClearHistoryConfirm) {
                Button(AppLocalization.string("清空"), role: .destructive) { clearCalculationHistoryWithUndo() }
                Button(AppLocalization.string("取消"), role: .cancel) {}
            }
            .alert(AppLocalization.string("恢复测试数据？"), isPresented: $showSampleDataImportConfirm) {
                Button(AppLocalization.string("清空并导入"), role: .destructive) {
                    importSampleDataWithNotice()
                }
                Button(AppLocalization.string("取消"), role: .cancel) {}
            } message: {
                Text(AppLocalization.string("会清空当前本机业务数据，并恢复一套更完整的测试项目、报价、图纸、票据、照片和附件样例。"))
            }
            .alert(AppLocalization.string("确认覆盖导入？"), isPresented: $showUITestOverwriteImportConfirm) {
                Button(AppLocalization.string("取消"), role: .cancel) {}
            } message: {
                Text(AppLocalization.string("覆盖会删除当前本机数据，请先导出备份。"))
            }
    }

    private var navigationContent: some View {
        mainContent
            .navigationTitle(AppLocalization.string("数据安全中心"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: compactNavigationAction)
    }

    private var mainContent: some View {
        VStack(spacing: usesWideLayout ? AppSpacing.normal : AppSpacing.tight) {
            headerContent
            wideSupplementaryContent
            selectedFlowContent
            .id(selectedTab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    private var headerContent: some View {
        collapsibleSafetyHeader
    }

    @ViewBuilder
    private var wideSupplementaryContent: some View {
        if usesWideLayout, !showsCompactSafetyHeader {
            selectedTabSummary

            if selectedTab == .backupAndRestore, sampleDataImportEnabled {
                DataManagementSampleDataImportCard(
                    hasAnyBusinessData: store.hasAnyBusinessData,
                    onImport: {
                        showSampleDataImportConfirm = true
                    }
                )
            }

            if !store.historyRecords.isEmpty {
                calculationHistoryCard
            }
        }
    }

    @ViewBuilder
    private var selectedFlowContent: some View {
        switch selectedTab {
        case .export:
            ExportView(
                showsNavigationTitle: false,
                bottomContentInset: embeddedScrollBottomInset,
                onMobileScrollOffsetChange: contentScrollHandler
            )
        case .backupAndRestore:
            BackupView(
                autoOpenImporter: shouldAutoOpenBackupImporter,
                showsNavigationTitle: false,
                bottomContentInset: embeddedScrollBottomInset,
                onMobileScrollOffsetChange: contentScrollHandler,
                onAutoOpenImporterConsumed: {
                    shouldAutoOpenBackupImporter = false
                }
            )
        case .healthAndCleanup:
            healthAndCleanupContent
        }
    }

    var contentScrollHandler: ((CGFloat) -> Void)? {
        { offset in handleContentScrollOffsetChange(offset) }
    }

    var showsCompactSafetyHeader: Bool {
        isCompactSafetyHeader || dynamicTypeSize.isAccessibilitySize || verticalSizeClass == .compact
    }

    private var compactActionMenu: some View {
        DataManagementCompactActionMenu(
            selectedTab: $selectedTab,
            healthCleanupSection: $healthCleanupSection,
            shouldAutoOpenBackupImporter: $shouldAutoOpenBackupImporter,
            showClearHistoryConfirm: $showClearHistoryConfirm,
            showSampleDataImportConfirm: $showSampleDataImportConfirm,
            showUITestOverwriteImportConfirm: $showUITestOverwriteImportConfirm,
            sampleDataImportEnabled: sampleDataImportEnabled,
            showsUITestBackupPreviewShortcut: showsUITestBackupPreviewShortcut,
            hasHistoryRecords: !store.historyRecords.isEmpty,
            hasAnyBusinessData: store.hasAnyBusinessData,
            historyTrimCount: historyTrimCount,
            onTrimHistory: trimCalculationHistoryWithUndo
        )
    }

    @ViewBuilder
    private var compactNavigationAction: some View {
        if !usesWideLayout || showsCompactSafetyHeader || showsUITestBackupPreviewShortcut {
            compactActionMenu
        }
    }

    var safetyHeaderSection: some View {
        DataManagementSafetyHeaderSection(
            backupStatusValue: backupStatusValue,
            backupStatusTone: backupStatusTone,
            healthStatusValue: healthStatusValue,
            healthStatusTone: healthStatusTone,
            cleanupStatusValue: cleanupStatusValue,
            cleanupStatusTone: cleanupStatusTone,
            action: primarySafetyAction,
            onPrimaryAction: {
                performPrimarySafetyAction(primarySafetyAction)
            },
            onOpenBackupImport: {
                selectedTab = .backupAndRestore
                shouldAutoOpenBackupImporter = true
            },
            onOpenExport: {
                selectedTab = .export
            },
            onOpenStorageCleanup: {
                selectedTab = .healthAndCleanup
                healthCleanupSection = .storage
            },
            onOpenAudit: {
                selectedTab = .healthAndCleanup
                healthCleanupSection = .audit
            }
        )
    }

    @ViewBuilder
    var collapsibleSafetyHeader: some View {
        if showsCompactSafetyHeader {
            DataManagementSecondaryFlowShortcutGrid(
                usesWideLayout: usesWideLayout,
                cards: secondaryShortcutCards,
                onSelect: selectSecondaryTarget(_:),
                usesCompactRow: true
            )
            .padding(.vertical, 4)
            .background(.bar)
            .transition(.move(edge: .top).combined(with: .opacity))
        } else {
            VStack(spacing: AppSpacing.tight) {
                safetyHeaderSection

                DataManagementSecondaryFlowShortcutGrid(
                    usesWideLayout: usesWideLayout,
                    cards: secondaryShortcutCards,
                    onSelect: selectSecondaryTarget(_:),
                    usesCompactRow: false
                )
            }
            .contentShape(Rectangle())
            .transition(.opacity)
        }
    }

    func handleContentScrollOffsetChange(_ offset: CGFloat) {
        guard abs(offset - lastContentOffset) > 1 else { return }
        lastContentOffset = offset

        let shouldCompact = offset < -56
        let shouldExpand = offset > -12

        if shouldCompact, !isCompactSafetyHeader {
            withAnimation(.snappy) {
                isCompactSafetyHeader = true
            }
        } else if shouldExpand, isCompactSafetyHeader {
            withAnimation(.snappy) {
                isCompactSafetyHeader = false
            }
        }
    }
}
