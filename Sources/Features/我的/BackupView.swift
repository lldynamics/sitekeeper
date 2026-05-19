import SwiftUI
import Foundation
import UniformTypeIdentifiers

private enum BackupSection: CaseIterable {
    case local
    case cloud
    case overview

    var displayName: String {
        switch self {
        case .local:
            return String(localized: "本地备份")
        case .cloud:
            return String(localized: "iCloud 云备份")
        case .overview:
            return String(localized: "备份概览")
        }
    }
    var systemImage: String {
        switch self {
        case .local: "externaldrive"
        case .cloud: "icloud"
        case .overview: "info.circle"
        }
    }
}

struct BackupView: View {
    @Environment(DataStore.self) var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(UserPreferenceKeys.hasCompletedBackupExportTask) var hasCompletedBackupExportTask = false
    @AppStorage(UserPreferenceKeys.hasSeenBackupGuide) var hasSeenBackupGuide = false
    @AppStorage(UserPreferenceKeys.cloudBackupIncludeBusinessRecords) var cloudIncludeBusinessRecords = true
    @AppStorage(UserPreferenceKeys.cloudBackupIncludeProjectRecords) var cloudIncludeProjectRecords = true
    @AppStorage(UserPreferenceKeys.cloudBackupIncludeProjectFilesAndNotes) var cloudIncludeProjectFilesAndNotes = true
    @AppStorage(UserPreferenceKeys.cloudBackupIncludeKnowledgeBase) var cloudIncludeKnowledgeBase = true
    @AppStorage(UserPreferenceKeys.cloudBackupIncludeAttachments) var cloudIncludeAttachments = true
    @AppStorage(UserPreferenceKeys.cloudBackupAutoInterval) var cloudAutoIntervalRawValue = CloudBackupAutoInterval.disabled.rawValue
    @AppStorage(UserPreferenceKeys.cloudBackupAutoRequiresWiFi) private var cloudAutoBackupRequiresWiFi = false
    @AppStorage(UserPreferenceKeys.cloudBackupRetentionCount) var cloudBackupRetentionCount = CloudBackupRetentionCountOption.defaultValue
    @AppStorage(UserPreferenceKeys.localBackupLastSuccessAt) private var localBackupLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.cloudBackupLastSuccessAt) var cloudLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.cloudBackupAutoLastStatus) private var cloudAutoLastStatus = ""
    @State var statusMessage = ""
    @State var showExporter = false
    @State private var showImporter = false
    @State var exportFileURL: URL?
    @State var exportSummary = ""
    @State var pendingImportPreview: BackupImportPreview?
    @State var pendingImportFileURL: URL?
    @State var showPreview = false
    @State var importMode: ImportMode = .merge
    @State var isOverwriteImportArmed = false
    @State private var showUITestOverwriteImportConfirm = false
    @State private var didAutoOpenImporter = false
    @State var exportTask: Task<Void, Never>?
    @State var importTask: Task<Void, Never>?
    @State var isExportingArchive = false
    @State var exportProgress = BackupArchiveProgress(completedSteps: 0, totalSteps: 1, currentItem: String(localized: "准备导出"))
    @State var isImportingBackup = false
    @State var importProgress = BackupImportProgress(completedBytes: 0, totalBytes: 1, currentItem: String(localized: "准备导入"))
    @State var importProgressTitle = String(localized: "正在读取备份")
    @State var lastExportSucceeded = false
    @State var lastImportSucceeded = false
    @State var estimateState = BackupEstimateState()
    @State var cloudState = BackupCloudState()
    @State private var selectedBackupSection: BackupSection = .local
    private let autoOpenImporter: Bool
    private let showsNavigationTitle: Bool
    private let cloudBackupScopeHint = String(localized: "可按业务模块选择备份范围。关闭“原文件附件”可显著减小体积。")
    private let cloudCellularTrafficHint = String(localized: "提示：在蜂窝网络下手动或自动备份 iCloud 会消耗移动数据流量，建议大包资料优先在 Wi‑Fi 下操作。")

    init(autoOpenImporter: Bool = false, showsNavigationTitle: Bool = true) {
        self.autoOpenImporter = autoOpenImporter
        self.showsNavigationTitle = showsNavigationTitle
    }

    var backupEstimateSignature: Int {
        var hasher = Hasher()
        hasher.combine(store.materialItems.count)
        hasher.combine(store.quoteItems.count)
        hasher.combine(store.laborRecords.count)
        hasher.combine(store.projects.count)
        hasher.combine(store.dailyLogs.count)
        hasher.combine(store.historyRecords.count)
        hasher.combine(store.progressTasks.count)
        hasher.combine(store.siteTodos.count)
        hasher.combine(store.projectDrawings.count)
        hasher.combine(store.projectContacts.count)
        hasher.combine(store.projectFinancialRecords.count)
        hasher.combine(store.projectDocuments.count)
        hasher.combine(store.quickNotes.count)
        hasher.combine(store.projectWarehouseMovements.count)
        hasher.combine(store.templates.count)
        hasher.combine(store.materialPriceEntries.count)
        hasher.combine(store.supplierProfiles.count)
        hasher.combine(store.constructionMethods.count)
        hasher.combine(store.favoriteMaterialKeys.count)
        hasher.combine(store.recentMaterialKeys.count)

        let dailyLogPhotoCount = store.dailyLogs.reduce(0) { result, log in
            result + log.allPhotoFileNames.count
        }
        let todoPhotoCount = store.siteTodos.reduce(0) { result, todo in
            result
                + (todo.rectificationBeforePhotoFileName?.isEmpty == false ? 1 : 0)
                + (todo.rectificationAfterPhotoFileName?.isEmpty == false ? 1 : 0)
        }
        let quickNoteAttachmentCount = store.quickNotes.reduce(0) { result, note in
            result + note.attachments.count
        }
        let constructionAttachmentCount = store.constructionMethods.reduce(0) { result, method in
            result + method.attachments.count + method.tutorialAttachments.count
        }

        hasher.combine(dailyLogPhotoCount)
        hasher.combine(todoPhotoCount)
        hasher.combine(quickNoteAttachmentCount)
        hasher.combine(constructionAttachmentCount)
        return hasher.finalize()
    }

    private var shouldShowFirstBackupGuide: Bool {
        !hasCompletedBackupExportTask && !hasSeenBackupGuide && !lastImportSucceeded
    }

    private var shouldShowMicroGuides: Bool {
        !isExportingArchive
            && !isImportingBackup
            && (estimateState.backupEstimate.missingFiles.count > 0 || lastExportSucceeded || lastImportSucceeded)
    }

    private var showsUITestPreviewShortcut: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-backup-preview")
            || ProcessInfo.processInfo.environment["UITEST_BACKUP_PREVIEW"] == "1"
    }

    private var runtimeState: BackupRuntimeState {
        BackupRuntimeState(
            isExportingArchive: isExportingArchive,
            isImportingBackup: isImportingBackup,
            isUploadingCloudBackup: cloudState.isUploadingCloudBackup,
            isRefreshingCloudBackups: cloudState.isRefreshingCloudBackups
        )
    }

    private var isBusy: Bool {
        runtimeState.isBusy
    }

    var cloudBackupOptions: CloudBackupContentOptions {
        CloudBackupContentOptions(
            includeBusinessRecords: cloudIncludeBusinessRecords,
            includeProjectRecords: cloudIncludeProjectRecords,
            includeProjectFilesAndNotes: cloudIncludeProjectFilesAndNotes,
            includeKnowledgeBase: cloudIncludeKnowledgeBase,
            includeAttachments: cloudIncludeAttachments
        ).normalized()
    }

    private var cloudAutoInterval: CloudBackupAutoInterval {
        StringEnumFallback.value(cloudAutoIntervalRawValue, default: CloudBackupAutoInterval.disabled)
    }

    private var cloudLastSuccessDate: Date? {
        guard cloudLastSuccessAt > 0 else { return nil }
        return Date(timeIntervalSince1970: cloudLastSuccessAt)
    }

    private var cloudNextAutoBackupDate: Date? {
        guard let interval = cloudAutoInterval.minimumInterval else { return nil }
        let base = cloudLastSuccessDate ?? Date()
        return base.addingTimeInterval(interval)
    }

    private var cloudAutoNetworkHint: String {
        cloudAutoBackupRequiresWiFi
            ? String(localized: "已限制为仅 Wi‑Fi 自动备份。")
            : String(localized: "当前允许在蜂窝网络下自动备份，可能消耗移动数据流量。")
    }

    private var cloudBackupSection: some View {
        BackupCloudSectionView(
            cloudIncludeBusinessRecords: $cloudIncludeBusinessRecords,
            cloudIncludeProjectRecords: $cloudIncludeProjectRecords,
            cloudIncludeProjectFilesAndNotes: $cloudIncludeProjectFilesAndNotes,
            cloudIncludeKnowledgeBase: $cloudIncludeKnowledgeBase,
            cloudIncludeAttachments: $cloudIncludeAttachments,
            cloudAutoIntervalRawValue: $cloudAutoIntervalRawValue,
            cloudAutoBackupRequiresWiFi: $cloudAutoBackupRequiresWiFi,
            cloudBackupRetentionCount: $cloudBackupRetentionCount,
            isBusy: isBusy,
            isRefreshingCloudBackups: cloudState.isRefreshingCloudBackups,
            cloudBackups: cloudState.cloudBackups,
            cloudStatusMessage: cloudState.cloudStatusMessage,
            cloudBackupScopeHint: cloudBackupScopeHint,
            cloudCellularTrafficHint: cloudCellularTrafficHint,
            cloudAutoNetworkHint: cloudAutoNetworkHint,
            cloudAutoInterval: cloudAutoInterval,
            cloudLastSuccessDate: cloudLastSuccessDate,
            cloudNextAutoBackupDate: cloudNextAutoBackupDate,
            cloudAutoLastStatus: cloudAutoLastStatus,
            onUploadBackup: uploadBackupToICloud,
            onRefreshBackups: { refreshCloudBackups(force: true) },
            onRestoreBackup: { file in
                cloudState.pendingCloudRestore = file
                cloudState.showCloudRestoreConfirm = true
            }
        )
        .onChange(of: cloudIncludeProjectRecords) { _, isEnabled in
            if !isEnabled {
                cloudIncludeProjectFilesAndNotes = false
                cloudIncludeAttachments = false
            }
        }
        .onChange(of: cloudIncludeProjectFilesAndNotes) { _, isEnabled in
            if !isEnabled {
                cloudIncludeAttachments = false
            }
        }
    }

    private var usesWideLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var backupSurface: some View {
        ZStack {
            if usesWideLayout {
                HStack(alignment: .top, spacing: 14) {
                    backupSidebar
                        .frame(minWidth: 260, maxWidth: 320)
                    backupDetailContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Form {
                    backupQuickStartSection
                    backupLocalSection
                    cloudBackupSection
                    backupMicroGuideSection
                    backupEstimateSection
                    backupStatusSection
                }
            }
            if isExportingArchive || cloudState.isUploadingCloudBackup {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    exportProgressCard
                }
            }
            if isImportingBackup {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    importProgressCard
                }
            }
        }
        .sheet(isPresented: $showExporter) {
            if let exportFileURL {
                FileURLDocumentExporter(fileURL: exportFileURL) { result in
                    if case .success = result {
                        setStatus(exportSummary.isEmpty ? String(localized: "导出成功") : exportSummary)
                        localBackupLastSuccessAt = Date().timeIntervalSince1970
                        hasCompletedBackupExportTask = true
                        lastExportSucceeded = true
                        lastImportSucceeded = false
                    }
                    showExporter = false
                    cleanupExportArchiveIfNeeded()
                }
            } else {
                ProgressView(String(localized: "正在准备导出文件..."))
                    .padding()
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zipArchive]) { result in
            switch result {
            case .success(let url):
                startPreviewImport(from: url)
            case .failure(let error):
                setStatus(String(format: String(localized: "未能读取所选文件：%@"), error.localizedDescription))
                OperationAuditLog.record(
                    action: .import,
                    outcome: .failed,
                    summary: String(format: String(localized: "未能读取所选文件：%@"), error.localizedDescription),
                    source: "BackupView"
                )
            }
        }
        .sheet(isPresented: $showPreview) {
            if let preview = pendingImportPreview {
                importPreview(preview: preview)
            } else {
                NavigationStack {
                    ProgressView(String(localized: "正在加载预览..."))
                        .padding()
                }
            }
        }
        .alert(String(localized: "确认覆盖导入？"), isPresented: $showUITestOverwriteImportConfirm) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "覆盖导入"), role: .destructive) {}
        } message: {
            Text(String(localized: "覆盖会删除当前本机数据，请先导出备份。"))
        }
        .alert(String(localized: "从 iCloud 恢复备份？"), isPresented: $cloudState.showCloudRestoreConfirm) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "读取备份")) {
                restorePendingCloudBackup()
            }
        } message: {
            Text(String(localized: "将先读取云端备份预览，确认后可选择合并或覆盖当前本机数据。"))
        }
        .onAppear {
            normalizeCloudBackupSettings()
            refreshBackupEstimateIfNeeded(force: true)
            refreshCloudBackups()
            guard autoOpenImporter, !didAutoOpenImporter else { return }
            didAutoOpenImporter = true
            showImporter = true
        }
        .onChange(of: backupEstimateSignature) { _, _ in
            refreshBackupEstimateIfNeeded()
        }
        .onDisappear {
            // 展示预览/导入导出弹层时，父视图可能暂时 disappear，避免误清空待导入预览状态。
            guard !showPreview, !showImporter, !showExporter else { return }
            resetBackupRuntimeStateOnDisappear()
        }
    }

    var body: some View {
        Group {
            if showsNavigationTitle {
                backupSurface
                    .navigationTitle(String(localized: "数据备份"))
            } else {
                backupSurface
            }
        }
    }

    // MARK: - iPad 双栏布局

    private var backupSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Label(String(localized: "数据备份"), systemImage: "arrow.triangle.2.circlepath.icloud")
                        .font(.headline)

                    Text(String(localized: "导出、导入与 iCloud 同步"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemGroupedBackground)))

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "导航"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(BackupSection.allCases, id: \.self) { section in
                        Button {
                            selectedBackupSection = section
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: section.systemImage)
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 16)
                                Text(section.displayName)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if selectedBackupSection == section {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.appWarning)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedBackupSection == section ? Color.appPrimarySurface : Color(uiColor: .secondarySystemGroupedBackground))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "快捷操作"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Button {
                        exportBackupZIP()
                    } label: {
                        Label(String(localized: "导出备份 ZIP"), systemImage: "archivebox")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.appSuccess)
                    .disabled(isBusy)

                    Button {
                        showImporter = true
                    } label: {
                        Label(String(localized: "导入备份 ZIP"), systemImage: "square.and.arrow.down")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)

                    Button {
                        uploadBackupToICloud()
                    } label: {
                        Label(String(localized: "备份到 iCloud"), systemImage: "icloud.and.arrow.up")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.appPrimaryAction)
                    .disabled(isBusy)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .secondarySystemGroupedBackground)))
                }

                Spacer()
            }
            .padding(.vertical, 2)
        }
    }

    private var backupDetailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch selectedBackupSection {
                case .local:
                    backupQuickStartSection
                    backupLocalSection
                    backupMicroGuideSection
                case .cloud:
                    cloudBackupSection
                case .overview:
                    backupEstimateSection
                    backupMicroGuideSection
                }
                backupStatusSection
            }
            .padding(4)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - 提取的 Section 视图

    @ViewBuilder
    private var backupQuickStartSection: some View {
        BackupLocalSectionsView(
            shouldShowFirstBackupGuide: shouldShowFirstBackupGuide,
            includeLocalSection: false,
            showsUITestPreviewShortcut: false,
            isBusy: isBusy,
            onExport: exportBackupZIP,
            onDismissGuide: { hasSeenBackupGuide = true },
            onShowImporter: { showImporter = true },
            onInjectUITestPreview: injectUITestPreview,
            onTriggerOverwriteConfirm: { showUITestOverwriteImportConfirm = true }
        )
    }

    private var backupLocalSection: some View {
        BackupLocalSectionsView(
            shouldShowFirstBackupGuide: false,
            includeLocalSection: true,
            showsUITestPreviewShortcut: showsUITestPreviewShortcut,
            isBusy: isBusy,
            onExport: exportBackupZIP,
            onDismissGuide: { hasSeenBackupGuide = true },
            onShowImporter: { showImporter = true },
            onInjectUITestPreview: injectUITestPreview,
            onTriggerOverwriteConfirm: { showUITestOverwriteImportConfirm = true }
        )
    }

    @ViewBuilder
    private var backupMicroGuideSection: some View {
        if shouldShowMicroGuides {
            Section(String(localized: "建议下一步")) {
                if estimateState.backupEstimate.missingFiles.count > 0 {
                    BackupMicroGuideRow(
                        icon: "exclamationmark.triangle.fill",
                        color: .appWarning,
                        title: String(format: String(localized: "检测到 %d 个原文件缺失"), estimateState.backupEstimate.missingFiles.count),
                        detail: String(localized: "建议先到项目文件页抽查缺件，再导出正式备份。")
                    )
                    NavigationLink {
                        ProjectFileBrowserView()
                    } label: {
                        Label(String(localized: "去项目文件排查"), systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }

                if lastExportSucceeded {
                    BackupMicroGuideRow(
                        icon: "checkmark.seal.fill",
                        color: .appSuccess,
                        title: String(localized: "备份已导出，建议立即做一次导入预览"),
                        detail: String(localized: "提前验证恢复链路，换机或误删时更稳。")
                    )
                    Button {
                        showImporter = true
                    } label: {
                        Label(String(localized: "马上验证导入"), systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(.appProminent(tint: .appWarning))
                }

                if lastImportSucceeded {
                    BackupMicroGuideRow(
                        icon: "doc.text.magnifyingglass",
                        color: .appPrimaryAction,
                        title: String(localized: "导入完成，建议抽查关键资料"),
                        detail: String(localized: "优先核对最近图纸、票据和随手记附件是否完整。")
                    )
                    NavigationLink {
                        ProjectFileBrowserView()
                    } label: {
                        Label(String(localized: "去抽查文件"), systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var backupEstimateSection: some View {
        BackupOverviewSectionsView(
            isEstimatingBackup: estimateState.isEstimatingBackup,
            backupEstimate: estimateState.backupEstimate
        )
    }

    @ViewBuilder
    private var backupStatusSection: some View {
        if !statusMessage.isEmpty {
            Section { Text(statusMessage).font(.caption) }
        }
    }

    private var exportProgressCard: some View {
        BackupTaskProgressCard(
            title: cloudState.isUploadingCloudBackup ? String(localized: "正在生成 iCloud 备份") : String(localized: "正在生成备份 ZIP"),
            subtitle: exportProgress.currentItem,
            progressValue: exportProgress.fractionCompleted,
            detail: "\(exportProgress.completedSteps)/\(max(exportProgress.totalSteps, 1))",
            cancelTitle: cloudState.isUploadingCloudBackup ? String(localized: "取消云备份") : String(localized: "取消导出"),
            onCancel: {
                AppHaptics.warning()
                exportProgress = BackupArchiveProgress(
                    completedSteps: exportProgress.completedSteps,
                    totalSteps: max(exportProgress.totalSteps, 1),
                    currentItem: String(localized: "正在取消...")
                )
                if cloudState.isUploadingCloudBackup {
                    cloudState.cloudBackupTask?.cancel()
                } else {
                    exportTask?.cancel()
                }
            }
        )
    }

    private var importProgressCard: some View {
        BackupTaskProgressCard(
            title: importProgressTitle,
            subtitle: importProgress.currentItem,
            progressValue: importProgress.fractionCompleted,
            detail: "\(formattedFileSize(Int(importProgress.completedBytes)))/\(formattedFileSize(Int(importProgress.totalBytes)))",
            cancelTitle: String(localized: "取消导入"),
            onCancel: {
                AppHaptics.warning()
                importProgress = BackupImportProgress(
                    completedBytes: importProgress.completedBytes,
                    totalBytes: max(importProgress.totalBytes, 1),
                    currentItem: String(localized: "正在取消...")
                )
                importTask?.cancel()
            }
        )
    }

    private func formattedFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}
