import SwiftUI

struct DataManagementView: View {
    @Environment(DataStore.self) var store
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
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
        VStack(spacing: usesWideLayout ? AppSpacing.normal : AppSpacing.tight) {
            if usesWideLayout {
                safetyHeaderSection

                DataManagementSecondaryFlowShortcutGrid(
                    usesWideLayout: true,
                    cards: secondaryShortcutCards,
                    onSelect: selectSecondaryTarget(_:)
                )
            } else {
                mobileSafetyHeader
            }

            if usesWideLayout {
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

            Group {
                switch selectedTab {
                case .export:
                    ExportView(showsNavigationTitle: false, bottomContentInset: embeddedScrollBottomInset)
                case .backupAndRestore:
                    BackupView(
                        autoOpenImporter: shouldAutoOpenBackupImporter,
                        showsNavigationTitle: false,
                        bottomContentInset: embeddedScrollBottomInset,
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
            .clipped()
        }
        .navigationTitle(String(localized: "数据安全中心"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !usesWideLayout {
                ToolbarItem(placement: .topBarTrailing) {
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded(collapseMobileSafetyHeaderIfNeeded(_:))
        )
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
    var mobileSafetyHeader: some View {
        if isCompactSafetyHeader {
            DataManagementSecondaryFlowShortcutGrid(
                usesWideLayout: false,
                cards: secondaryShortcutCards,
                onSelect: selectSecondaryTarget(_:)
            )
            .padding(.vertical, 4)
            .background(.bar)
            .transition(.move(edge: .top).combined(with: .opacity))
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onEnded(expandMobileSafetyHeaderIfNeeded(_:))
            )
        } else {
            VStack(spacing: AppSpacing.tight) {
                safetyHeaderSection

                DataManagementSecondaryFlowShortcutGrid(
                    usesWideLayout: false,
                    cards: secondaryShortcutCards,
                    onSelect: selectSecondaryTarget(_:),
                    usesCompactRow: false
                )
            }
            .contentShape(Rectangle())
            .transition(.opacity)
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onEnded(collapseMobileSafetyHeaderIfNeeded(_:))
            )
        }
    }

    func collapseMobileSafetyHeaderIfNeeded(_ value: DragGesture.Value) {
        guard !usesWideLayout, !isCompactSafetyHeader, value.translation.height < -36 else { return }
        withAnimation(.snappy) {
            isCompactSafetyHeader = true
        }
    }

    func expandMobileSafetyHeaderIfNeeded(_ value: DragGesture.Value) {
        guard !usesWideLayout, isCompactSafetyHeader, value.translation.height > 48 else { return }
        withAnimation(.snappy) {
            isCompactSafetyHeader = false
        }
    }
}
