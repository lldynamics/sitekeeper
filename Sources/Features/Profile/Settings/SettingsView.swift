import SwiftUI

struct SettingsView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.backupHealthReminderDays) private var backupHealthReminderDays = 7
    @AppStorage(UserPreferenceKeys.storageCleanupTrashRetentionDays) private var cleanupTrashRetentionDays = StorageCleanupTrashRetentionOption.defaultDays
    @AppStorage(UserPreferenceKeys.dueNotificationsEnabled) private var dueNotificationsEnabled = false
    @State private var isUpdatingDueNotifications = false
    @State private var dueNotificationStatusMessage = ""
    @State private var showClearLocalDataBackupGate = false
    @State private var showClearLocalDataSheet = false
    @State private var isClearingLocalData = false
    @State private var clearLocalDataFlowStartedAt = 0.0
    @State private var clearLocalDataPhase = ""
    @State private var clearLocalDataResultMessage = ""
    @State private var clearLocalDataFailed = false
    @State private var clearLocalDataPreview = ClearLocalDataImpactPreview.empty

    var body: some View {
        Form {
            Section(AppLocalization.string("数据管理")) {
                Stepper(value: $backupHealthReminderDays, in: 1 ... 30) {
                    LabeledContent(
                        AppLocalization.string("备份健康提醒阈值"),
                        value: String(format: AppLocalization.string("%lld 天"), Int64(backupHealthReminderDays))
                    )
                }
                Text(AppLocalization.string("超过该天数未成功备份时，工作台会显示“备份超期”提醒。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(AppLocalization.string("到期系统通知"), isOn: $dueNotificationsEnabled)
                .disabled(isUpdatingDueNotifications)
                .onChange(of: dueNotificationsEnabled) { _, enabled in
                    updateDueNotifications(enabled)
                }
                Text(AppLocalization.string("为未完成待办和待提醒的应收/应付流水安排本地通知，最多保留最近 60 条。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !dueNotificationStatusMessage.isEmpty {
                    Text(dueNotificationStatusMessage)
                        .font(.caption)
                        .foregroundStyle(dueNotificationsEnabled ? Color.appSuccess : Color.appWarning)
                }
                Picker(AppLocalization.string("回收站保留时间"), selection: $cleanupTrashRetentionDays) {
                    ForEach(StorageCleanupTrashRetentionOption.allCases) { option in
                        Text(option.displayName)
                            .tag(option.days)
                    }
                }
                Text(AppLocalization.string("该设置会影响文件清理后的可恢复窗口，到期后将进入永久删除队列。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(AppLocalization.string("清空本机全部数据（需先备份）"), role: .destructive) {
                    do {
                        clearLocalDataPreview = try buildClearLocalDataPreview()
                        clearLocalDataFlowStartedAt = Date().timeIntervalSince1970
                        showClearLocalDataBackupGate = true
                    } catch {
                        clearLocalDataFailed = true
                        clearLocalDataResultMessage = error.localizedDescription
                    }
                }
                .disabled(isClearingLocalData || !store.canEditBusinessData)
                Text(AppLocalization.string("将删除本机所有项目、附件与导入文件，不会影响你已导出的备份 ZIP。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isClearingLocalData {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(
                            clearLocalDataPhase.isEmpty
                                ? AppLocalization.string("正在清空本机数据，请稍候...")
                                : String(format: AppLocalization.string("%@..."), clearLocalDataPhase)
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !clearLocalDataResultMessage.isEmpty {
                    Text(clearLocalDataResultMessage)
                        .font(.caption)
                        .foregroundStyle(clearLocalDataFailed ? Color.appRisk : Color.appSuccess)
                        .accessibilityIdentifier("clear-local-data-result")
                }
            }
            Section(AppLocalization.string("试用功能")) {
                NavigationLink { RepositoryWorkspaceLauncher() } label: {
                    Text(AppLocalization.string("项目与日志试用副本"))
                }
                .accessibilityIdentifier("repository-workspace-entry")
            }
            Section(AppLocalization.string("关于")) {
                HStack {
                    Text(AppLocalization.string("版本"))
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(AppLocalization.string("设置")).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showClearLocalDataBackupGate) {
            ClearLocalDataBackupGateSheet(flowStartedAt: clearLocalDataFlowStartedAt) {
                showClearLocalDataBackupGate = false
                do {
                    clearLocalDataPreview = try buildClearLocalDataPreview()
                    showClearLocalDataSheet = true
                } catch {
                    clearLocalDataFailed = true
                    clearLocalDataResultMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: $showClearLocalDataSheet) {
            ClearLocalDataConfirmationSheet(preview: clearLocalDataPreview) {
                Task {
                    let snapshot = clearLocalDataPreview.auditSnapshot
                    await MainActor.run {
                        clearLocalDataResultMessage = ""
                        clearLocalDataFailed = false
                        showClearLocalDataSheet = false
                        isClearingLocalData = true
                        clearLocalDataPhase = AppLocalization.string("正在准备")
                        OperationAuditLog.record(
                            action: .delete,
                            outcome: .started,
                            summary: AppLocalization.string("清空本机全部数据"),
                            detail: snapshot,
                            source: "SettingsView"
                        )
                    }
                    let cleared = await store.clearAllBusinessDataAsync(deleteStoredFiles: true, expectedRepositoryCopyCount: clearLocalDataPreview.repositoryCopyCount) { phase in
                        clearLocalDataPhase = phase
                    }
                    await MainActor.run {
                        isClearingLocalData = false
                        clearLocalDataPhase = ""
                        clearLocalDataFailed = !cleared
                        clearLocalDataResultMessage = cleared
                            ? AppLocalization.string("本机数据已清空")
                            : (store.persistenceErrorMessage ?? AppLocalization.string("清空本机数据失败，请稍后重试。"))
                        OperationAuditLog.record(
                            action: .delete,
                            outcome: cleared ? .succeeded : .failed,
                            summary: AppLocalization.string("清空本机全部数据"),
                            detail: cleared
                                ? snapshot
                                : "\(snapshot) · \(clearLocalDataResultMessage)",
                            source: "SettingsView"
                        )
                    }
                }
            } onCancel: {
                showClearLocalDataSheet = false
                OperationAuditLog.record(
                    action: .delete,
                    outcome: .cancelled,
                    summary: AppLocalization.string("清空本机全部数据"),
                    source: "SettingsView"
                )
            }
        }
        .onAppear {
            backupHealthReminderDays = min(max(backupHealthReminderDays, 1), 30)
            cleanupTrashRetentionDays = StorageCleanupTrashRetentionOption.normalizedDays(cleanupTrashRetentionDays)
        }
    }

    private func updateDueNotifications(_ enabled: Bool) {
        guard !isUpdatingDueNotifications else { return }
        isUpdatingDueNotifications = true
        dueNotificationStatusMessage = ""
        let snapshot = DueReminderSnapshot(store: store)
        Task { @MainActor in
            if enabled {
                let granted = await DueReminderNotificationScheduler.shared
                    .requestAuthorizationAndRefresh(snapshot: snapshot)
                dueNotificationsEnabled = granted
                dueNotificationStatusMessage = granted
                    ? AppLocalization.string("到期通知已开启")
                    : AppLocalization.string("系统未授权通知，可在“设置—通知”中开启。")
            } else {
                dueNotificationsEnabled = false
                await DueReminderNotificationScheduler.shared.clearPendingNotifications()
                dueNotificationStatusMessage = AppLocalization.string("到期通知已关闭")
            }
            isUpdatingDueNotifications = false
        }
    }

    private func buildClearLocalDataPreview() throws -> ClearLocalDataImpactPreview {
        let copies = try RepositoryWorkspaceMaintenance.summary(beside: store.storeURL)
        let ticketDocuments = store.projectDocuments.filter { document in
            isTicketCategory(document.category)
        }
        let normalDocuments = store.projectDocuments.filter { document in
            !isTicketCategory(document.category)
        }
        return ClearLocalDataImpactPreview(
            projectCount: store.projects.count,
            photoCount: PhotoStorage.referencedFileNames(
                logs: store.dailyLogs,
                todos: store.siteTodos
            ).count,
            ticketCount: ticketDocuments.count,
            documentCount: normalDocuments.count,
            historyCount: store.historyRecords.count,
            photoFileCount: PhotoStorage.allStoredFileNames().count,
            drawingFileCount: DrawingStorage.allStoredFileNames().count,
            documentFileCount: ProjectDocumentStorage.allStoredFileNames().count,
            attachmentFileCount: QuickNoteAttachmentStorage.allStoredFileNames().count,
            repositoryCopyCount: copies.count,
            repositoryCopyBytes: copies.bytes
        )
    }

    private func isTicketCategory(_ category: ProjectDocumentCategory) -> Bool {
        switch category {
        case .invoice, .receipt, .paymentRequest:
            return true
        default:
            return false
        }
    }
}
