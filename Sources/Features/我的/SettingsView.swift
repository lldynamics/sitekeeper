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
            Section(String(localized: "数据管理")) {
                Stepper(value: $backupHealthReminderDays, in: 1 ... 30) {
                    LabeledContent(
                        String(localized: "备份健康提醒阈值"),
                        value: String(format: String(localized: "%lld 天"), Int64(backupHealthReminderDays))
                    )
                }
                Text(String(localized: "超过该天数未成功备份时，工作台会显示“备份超期”提醒。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(String(localized: "到期系统通知"), isOn: $dueNotificationsEnabled)
                .disabled(isUpdatingDueNotifications)
                .onChange(of: dueNotificationsEnabled) { _, enabled in
                    updateDueNotifications(enabled)
                }
                Text(String(localized: "为未完成待办和待提醒的应收/应付流水安排本地通知，最多保留最近 60 条。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !dueNotificationStatusMessage.isEmpty {
                    Text(dueNotificationStatusMessage)
                        .font(.caption)
                        .foregroundStyle(dueNotificationsEnabled ? Color.appSuccess : Color.appWarning)
                }
                Picker(String(localized: "回收站保留时间"), selection: $cleanupTrashRetentionDays) {
                    ForEach(StorageCleanupTrashRetentionOption.allCases) { option in
                        Text(option.displayName)
                            .tag(option.days)
                    }
                }
                Text(String(localized: "该设置会影响文件清理后的可恢复窗口，到期后将进入永久删除队列。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(String(localized: "清空本机全部数据（需先备份）"), role: .destructive) {
                    clearLocalDataPreview = buildClearLocalDataPreview()
                    clearLocalDataFlowStartedAt = Date().timeIntervalSince1970
                    showClearLocalDataBackupGate = true
                }
                .disabled(isClearingLocalData)
                Text(String(localized: "将删除本机所有项目、附件与导入文件，不会影响你已导出的备份 ZIP。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isClearingLocalData {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(
                            clearLocalDataPhase.isEmpty
                                ? String(localized: "正在清空本机数据，请稍候...")
                                : String(format: String(localized: "%@..."), clearLocalDataPhase)
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
            Section(String(localized: "关于")) {
                HStack {
                    Text(String(localized: "版本"))
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(String(localized: "设置")).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showClearLocalDataBackupGate) {
            ClearLocalDataBackupGateSheet(flowStartedAt: clearLocalDataFlowStartedAt) {
                showClearLocalDataBackupGate = false
                showClearLocalDataSheet = true
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
                        clearLocalDataPhase = String(localized: "正在准备")
                        OperationAuditLog.record(
                            action: .delete,
                            outcome: .started,
                            summary: String(localized: "清空本机全部数据"),
                            detail: snapshot,
                            source: "SettingsView"
                        )
                    }
                    let cleared = await store.clearAllBusinessDataAsync(deleteStoredFiles: true) { phase in
                        clearLocalDataPhase = phase
                    }
                    await MainActor.run {
                        isClearingLocalData = false
                        clearLocalDataPhase = ""
                        clearLocalDataFailed = !cleared
                        clearLocalDataResultMessage = cleared
                            ? String(localized: "本机数据已清空")
                            : (store.persistenceErrorMessage ?? String(localized: "清空本机数据失败，请稍后重试。"))
                        OperationAuditLog.record(
                            action: .delete,
                            outcome: cleared ? .succeeded : .failed,
                            summary: String(localized: "清空本机全部数据"),
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
                    summary: String(localized: "清空本机全部数据"),
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
                    ? String(localized: "到期通知已开启")
                    : String(localized: "系统未授权通知，可在“设置—通知”中开启。")
            } else {
                dueNotificationsEnabled = false
                await DueReminderNotificationScheduler.shared.clearPendingNotifications()
                dueNotificationStatusMessage = String(localized: "到期通知已关闭")
            }
            isUpdatingDueNotifications = false
        }
    }

    private func buildClearLocalDataPreview() -> ClearLocalDataImpactPreview {
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
            attachmentFileCount: QuickNoteAttachmentStorage.allStoredFileNames().count
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

private struct ClearLocalDataImpactPreview {
    struct Item: Identifiable {
        let title: String
        let count: Int

        var id: String { title }
    }

    let projectCount: Int
    let photoCount: Int
    let ticketCount: Int
    let documentCount: Int
    let historyCount: Int
    let photoFileCount: Int
    let drawingFileCount: Int
    let documentFileCount: Int
    let attachmentFileCount: Int

    static let empty = ClearLocalDataImpactPreview(
        projectCount: 0,
        photoCount: 0,
        ticketCount: 0,
        documentCount: 0,
        historyCount: 0,
        photoFileCount: 0,
        drawingFileCount: 0,
        documentFileCount: 0,
        attachmentFileCount: 0
    )

    var recordItems: [Item] {
        [
            Item(title: String(localized: "项目"), count: projectCount),
            Item(title: String(localized: "照片记录"), count: photoCount),
            Item(title: String(localized: "票据记录"), count: ticketCount),
            Item(title: String(localized: "资料记录"), count: documentCount),
            Item(title: String(localized: "历史记录"), count: historyCount)
        ]
    }

    var fileItems: [Item] {
        [
            Item(title: String(localized: "照片文件（含缩略图）"), count: photoFileCount),
            Item(title: String(localized: "图纸文件"), count: drawingFileCount),
            Item(title: String(localized: "资料文件"), count: documentFileCount),
            Item(title: String(localized: "附件文件"), count: attachmentFileCount)
        ]
    }

    var totalFileCount: Int {
        fileItems.reduce(0) { partial, item in
            partial + item.count
        }
    }

    var auditSnapshot: String {
        [
            "projects=\(projectCount)",
            "photoRecords=\(photoCount)",
            "ticketRecords=\(ticketCount)",
            "documentRecords=\(documentCount)",
            "historyRecords=\(historyCount)",
            "photoFiles=\(photoFileCount)",
            "drawingFiles=\(drawingFileCount)",
            "documentFiles=\(documentFileCount)",
            "attachmentFiles=\(attachmentFileCount)"
        ].joined(separator: ", ")
    }
}

private struct ClearLocalDataBackupGateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(UserPreferenceKeys.localBackupLastSuccessAt) private var localBackupLastSuccessAt = 0.0

    let flowStartedAt: Double
    let onContinue: () -> Void

    private var hasBackupCreatedInThisFlow: Bool {
        localBackupLastSuccessAt > flowStartedAt
    }

    private var canContinueClearing: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["UITEST_ALLOW_CLEAR_WITHOUT_BACKUP"] == "1" || hasBackupCreatedInThisFlow
#else
        hasBackupCreatedInThisFlow
#endif
    }

    private var backupStatusText: String {
        guard localBackupLastSuccessAt > 0 else {
            return String(localized: "尚未生成本机备份")
        }
        let date = Date(timeIntervalSince1970: localBackupLastSuccessAt)
        return String(format: String(localized: "最近本机备份：%@"), Formatters.dateTime.string(from: date))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label(String(localized: "先备份再清空"), systemImage: "externaldrive.badge.checkmark")
                    .font(.title3.weight(.semibold))

                Text(String(localized: "清空本机数据前，必须先生成一份新的本机备份 ZIP。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    DataManagementView(initialRoute: .backup)
                } label: {
                    Label(String(localized: "去备份并导出 ZIP"), systemImage: "externaldrive")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Text(String(localized: "导出完成后回到这里继续。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(backupStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if hasBackupCreatedInThisFlow {
                    Label(String(localized: "已检测到本次流程内的新备份"), systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appSuccess)
                } else {
                    Label(String(localized: "请先完成本机备份后再继续清空。"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.appRisk)
                }

                Spacer(minLength: 0)

                HStack(spacing: 12) {
                    Button(String(localized: "取消"), role: .cancel) {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button(String(localized: "继续清空"), role: .destructive) {
                        onContinue()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(!canContinueClearing)
                }
            }
            .padding(20)
            .navigationTitle(String(localized: "清空本机数据"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ClearLocalDataConfirmationSheet: View {
    let preview: ClearLocalDataImpactPreview
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var input = ""
    @FocusState private var isFocused: Bool

    private var requiredPhrase: String {
        String(localized: "确认删除数据")
    }

    private var isInputValid: Bool {
        input == requiredPhrase
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.appRisk)
                        .padding(.top, 24)

                    Text(String(localized: "即将清空本机全部数据"))
                        .font(.title2.weight(.semibold))

                    Text(String(localized: "此操作不可恢复。以下内容将被删除："))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "预计影响记录："))
                            .font(.callout.weight(.semibold))
                        ForEach(preview.recordItems) { item in
                            Text(
                                String(
                                    format: String(localized: "- %@ %lld 条"),
                                    item.title,
                                    Int64(item.count)
                                )
                            )
                            .font(.callout)
                        }

                        Text(String(localized: "预计删除文件："))
                            .font(.callout.weight(.semibold))
                            .padding(.top, 4)
                        ForEach(preview.fileItems) { item in
                            Text(
                                String(
                                    format: String(localized: "- %@ %lld 个"),
                                    item.title,
                                    Int64(item.count)
                                )
                            )
                            .font(.callout)
                        }
                        Text(
                            String(
                                format: String(localized: "合计 %lld 个文件。"),
                                Int64(preview.totalFileCount)
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: String(localized: "请输入「%@」以确认："), requiredPhrase))
                            .font(.callout.weight(.medium))
                        TextField(requiredPhrase, text: $input)
                            .textFieldStyle(.roundedBorder)
                            .focused($isFocused)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal)

                    HStack(spacing: 16) {
                        Button(String(localized: "取消"), role: .cancel) {
                            onCancel()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button(String(localized: "确认清空"), role: .destructive) {
                            onConfirm()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!isInputValid)
                    }
                    .padding(.top, 8)

                    Spacer(minLength: 0)
                }
            }
            .interactiveDismissDisabled()
            .onAppear { isFocused = true }
        }
    }
}
