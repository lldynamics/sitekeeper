import SwiftUI
import Foundation
import UniformTypeIdentifiers

private enum BackupSection: String, CaseIterable {
    case local = "本地备份"
    case cloud = "iCloud 云备份"
    case overview = "备份概览"

    var displayName: String { rawValue }
    var systemImage: String {
        switch self {
        case .local: "externaldrive"
        case .cloud: "icloud"
        case .overview: "info.circle"
        }
    }
}

struct BackupView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(UserPreferenceKeys.hasCompletedBackupExportTask) private var hasCompletedBackupExportTask = false
    @AppStorage(UserPreferenceKeys.hasSeenBackupGuide) private var hasSeenBackupGuide = false
    @AppStorage(UserPreferenceKeys.cloudBackupIncludeBusinessRecords) private var cloudIncludeBusinessRecords = true
    @AppStorage(UserPreferenceKeys.cloudBackupIncludeProjectRecords) private var cloudIncludeProjectRecords = true
    @AppStorage(UserPreferenceKeys.cloudBackupIncludeProjectFilesAndNotes) private var cloudIncludeProjectFilesAndNotes = true
    @AppStorage(UserPreferenceKeys.cloudBackupIncludeKnowledgeBase) private var cloudIncludeKnowledgeBase = true
    @AppStorage(UserPreferenceKeys.cloudBackupIncludeAttachments) private var cloudIncludeAttachments = true
    @AppStorage(UserPreferenceKeys.cloudBackupAutoInterval) private var cloudAutoIntervalRawValue = CloudBackupAutoInterval.disabled.rawValue
    @AppStorage(UserPreferenceKeys.cloudBackupAutoRequiresWiFi) private var cloudAutoBackupRequiresWiFi = false
    @AppStorage(UserPreferenceKeys.cloudBackupLastSuccessAt) private var cloudLastSuccessAt = 0.0
    @AppStorage(UserPreferenceKeys.cloudBackupAutoLastStatus) private var cloudAutoLastStatus = ""
    @State private var statusMessage = ""
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var exportFileURL: URL?
    @State private var exportSummary = ""
    @State private var pendingImportPreview: BackupImportPreview?
    @State private var pendingImportFileURL: URL?
    @State private var showPreview = false
    @State private var importMode: ImportMode = .merge
    @State private var isOverwriteImportArmed = false
    @State private var showUITestOverwriteImportConfirm = false
    @State private var didAutoOpenImporter = false
    @State private var exportTask: Task<Void, Never>?
    @State private var importTask: Task<Void, Never>?
    @State private var isExportingArchive = false
    @State private var exportProgress = BackupArchiveProgress(completedSteps: 0, totalSteps: 1, currentItem: "准备导出")
    @State private var isImportingBackup = false
    @State private var importProgress = BackupImportProgress(completedBytes: 0, totalBytes: 1, currentItem: "准备导入")
    @State private var importProgressTitle = "正在读取备份"
    @State private var lastExportSucceeded = false
    @State private var lastImportSucceeded = false
    @State private var estimateState = BackupEstimateState()
    @State private var cloudState = BackupCloudState()
    @State private var selectedBackupSection: BackupSection = .local
    private let autoOpenImporter: Bool
    private let showsNavigationTitle: Bool
    private let cloudBackupScopeHint = "可按业务模块选择备份范围。关闭“原文件附件”可显著减小体积。"
    private let cloudCellularTrafficHint = "提示：在蜂窝网络下手动或自动备份 iCloud 会消耗移动数据流量，建议大包资料优先在 Wi‑Fi 下操作。"

    init(autoOpenImporter: Bool = false, showsNavigationTitle: Bool = true) {
        self.autoOpenImporter = autoOpenImporter
        self.showsNavigationTitle = showsNavigationTitle
    }

    private var backupEstimateSignature: Int {
        var hasher = Hasher()
        hasher.combine(store.materialItems.count)
        hasher.combine(store.quoteItems.count)
        hasher.combine(store.laborRecords.count)
        hasher.combine(store.projects.count)
        hasher.combine(store.dailyLogs.count)
        hasher.combine(store.historyRecords.count)
        hasher.combine(store.progressTasks.count)
        hasher.combine(store.lightingCircuitPlans.count)
        hasher.combine(store.siteTodos.count)
        hasher.combine(store.paymentRecords.count)
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

    private var cloudBackupOptions: CloudBackupContentOptions {
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
            ? "已限制为仅 Wi‑Fi 自动备份。"
            : "当前允许在蜂窝网络下自动备份，可能消耗移动数据流量。"
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
                        setStatus(exportSummary.isEmpty ? "导出成功" : exportSummary)
                        hasCompletedBackupExportTask = true
                        lastExportSucceeded = true
                        lastImportSucceeded = false
                    }
                    showExporter = false
                    cleanupExportArchiveIfNeeded()
                }
            } else {
                ProgressView("正在准备导出文件...")
                    .padding()
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.zipArchive]) { result in
            switch result {
            case .success(let url):
                startPreviewImport(from: url)
            case .failure(let error):
                setStatus("未能读取所选文件：\(error.localizedDescription)")
            }
        }
        .sheet(isPresented: $showPreview) {
            if let preview = pendingImportPreview {
                importPreview(preview: preview)
            } else {
                NavigationStack {
                    ProgressView("正在加载预览...")
                        .padding()
                }
            }
        }
        .alert("确认覆盖导入？", isPresented: $showUITestOverwriteImportConfirm) {
            Button("取消", role: .cancel) {}
            Button("覆盖导入", role: .destructive) {}
        } message: {
            Text("覆盖会删除当前本机数据，请先导出备份。")
        }
        .alert("从 iCloud 恢复备份？", isPresented: $cloudState.showCloudRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("读取备份") {
                restorePendingCloudBackup()
            }
        } message: {
            Text("将先读取云端备份预览，确认后可选择合并或覆盖当前本机数据。")
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
                    .navigationTitle("数据备份")
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
                    Label("数据备份", systemImage: "arrow.triangle.2.circlepath.icloud")
                        .font(.headline)

                    Text("导出、导入与 iCloud 同步")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemGroupedBackground)))

                VStack(alignment: .leading, spacing: 8) {
                    Text("导航")
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
                                        .foregroundStyle(.orange)
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
                    Text("快捷操作")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Button {
                        exportBackupZIP()
                    } label: {
                        Label("导出备份 ZIP", systemImage: "archivebox")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .disabled(isBusy)

                    Button {
                        showImporter = true
                    } label: {
                        Label("导入备份 ZIP", systemImage: "square.and.arrow.down")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)

                    Button {
                        uploadBackupToICloud()
                    } label: {
                        Label("备份到 iCloud", systemImage: "icloud.and.arrow.up")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
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
            Section("建议下一步") {
                if estimateState.backupEstimate.missingFiles.count > 0 {
                    BackupMicroGuideRow(
                        icon: "exclamationmark.triangle.fill",
                        color: .orange,
                        title: String(localized: "检测到 \(estimateState.backupEstimate.missingFiles.count) 个原文件缺失"),
                        detail: "建议先到项目文件页抽查缺件，再导出正式备份。"
                    )
                    NavigationLink {
                        ProjectFileBrowserView()
                    } label: {
                        Label("去项目文件排查", systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }

                if lastExportSucceeded {
                    BackupMicroGuideRow(
                        icon: "checkmark.seal.fill",
                        color: .green,
                        title: "备份已导出，建议立即做一次导入预览",
                        detail: "提前验证恢复链路，换机或误删时更稳。"
                    )
                    Button {
                        showImporter = true
                    } label: {
                        Label("马上验证导入", systemImage: "arrow.down.doc.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }

                if lastImportSucceeded {
                    BackupMicroGuideRow(
                        icon: "doc.text.magnifyingglass",
                        color: .blue,
                        title: "导入完成，建议抽查关键资料",
                        detail: "优先核对最近图纸、票据和随手记附件是否完整。"
                    )
                    NavigationLink {
                        ProjectFileBrowserView()
                    } label: {
                        Label("去抽查文件", systemImage: "arrow.right.circle.fill")
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

    private func importPreview(preview: BackupImportPreview) -> some View {
        BackupImportPreviewView(
            preview: preview,
            importMode: $importMode,
            isOverwriteImportArmed: $isOverwriteImportArmed,
            onApplyImport: startApplyingImport,
            onCancel: {
                showPreview = false
                cleanupPendingImportFileIfNeeded()
            }
        )
    }

    private func startPreviewImport(from selectedURL: URL) {
        clearStatus()
        do {
            let copiedURL = try BackupImportCoordinator.copySelectedBackupToSandbox(selectedURL)
            startPreviewImportFromPreparedFile(copiedURL)
        } catch {
            setStatus(error.localizedDescription)
            cleanupPendingImportFileIfNeeded()
        }
    }

    private func startPreviewImportFromPreparedFile(_ copiedURL: URL) {
        cleanupPendingImportFileIfNeeded()
        pendingImportPreview = nil
        pendingImportFileURL = copiedURL
        isOverwriteImportArmed = false

        beginImportTask(
            title: "正在读取备份预览",
            totalBytes: Int64(max(QuickNoteAttachmentStorage.fileSize(at: copiedURL), 1)),
            currentItem: "准备读取"
        )
        importTask = Task {
            do {
                let relay = TaskCancellationRelay()
                let preview = try await withTaskCancellationHandler {
                    try await Task.detached(priority: .userInitiated) {
                        try BackupArchiveService.previewBackup(
                            from: copiedURL,
                            progress: { progress in
                                Task { @MainActor in
                                    importProgress = progress
                                }
                            },
                            shouldCancel: { relay.isCancelled() || Task.isCancelled }
                        )
                    }.value
                } onCancel: {
                    relay.cancel()
                }
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeImportTask(cleanupPendingFile: true)
                    }
                    return
                }
                await MainActor.run {
                    isImportingBackup = false
                    importTask = nil
                    pendingImportPreview = preview
                    showPreview = true
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeImportTask(cleanupPendingFile: true)
                    }
                    return
                }
                await MainActor.run {
                    isImportingBackup = false
                    importTask = nil
                    setStatus("文件格式不正确：\(error.localizedDescription)")
                    cleanupPendingImportFileIfNeeded()
                }
            }
        }
    }

    private func startApplyingImport() {
        guard let pendingImportFileURL else {
            setStatus("备份源文件已失效，请重新选择导入文件。")
            showPreview = false
            return
        }
        isOverwriteImportArmed = false

        let metadataSnapshot = pendingImportPreview?.snapshot
        let sourceSize = Int64(max(QuickNoteAttachmentStorage.fileSize(at: pendingImportFileURL), 1))

        beginImportTask(
            title: "正在应用数据索引",
            totalBytes: sourceSize,
            currentItem: "准备导入"
        )

        importTask = Task {
            do {
                let snapshot: BackupSnapshot
                if let metadataSnapshot {
                    snapshot = metadataSnapshot
                } else {
                    let relay = TaskCancellationRelay()
                    let preview = try await withTaskCancellationHandler {
                        try await Task.detached(priority: .userInitiated) {
                            try BackupArchiveService.previewBackup(
                                from: pendingImportFileURL,
                                progress: { progress in
                                    Task { @MainActor in
                                        importProgress = progress
                                    }
                                },
                                shouldCancel: { relay.isCancelled() || Task.isCancelled }
                            )
                        }.value
                    } onCancel: {
                        relay.cancel()
                    }
                    snapshot = preview.snapshot
                }
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeImportTask(status: "已取消导入，当前数据未变更。", cleanupPendingFile: true, closePreview: true)
                    }
                    return
                }

                let existingSnapshot = await MainActor.run {
                    store.makeSnapshot(includePhotoFiles: false)
                }

                await MainActor.run {
                    importProgressTitle = "正在恢复原文件"
                    importProgress = BackupImportProgress(completedBytes: 0, totalBytes: sourceSize, currentItem: "准备恢复")
                }

                let relay = TaskCancellationRelay()
                let restoredCounts = try await withTaskCancellationHandler {
                    try await Task.detached(priority: .userInitiated) {
                        try BackupArchiveService.restoreEmbeddedFiles(
                            from: pendingImportFileURL,
                            progress: { progress in
                                Task { @MainActor in
                                    importProgress = progress
                                }
                            },
                            shouldCancel: { relay.isCancelled() || Task.isCancelled }
                        )
                    }.value
                } onCancel: {
                    relay.cancel()
                }

                await MainActor.run {
                    importProgressTitle = "正在应用数据索引"
                    BackupImportCoordinator.applyImportMetadata(snapshot: snapshot, mode: importMode, store: store)
                    if importMode == .overwrite {
                        BackupImportCoordinator.cleanupOverwrittenFiles(previous: existingSnapshot, imported: snapshot)
                    }
                    isImportingBackup = false
                    importTask = nil
                    store.save(includePhotoFiles: false)
                    showPreview = false
                    lastImportSucceeded = true
                    lastExportSucceeded = false
                    hasSeenBackupGuide = true
                    if restoredCounts.totalCount > 0 {
                        setStatus("导入完成（恢复 \(restoredCounts.totalCount) 个原文件）")
                    } else {
                        setStatus("导入完成")
                    }
                    cleanupPendingImportFileIfNeeded()
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeImportTask(status: "已取消导入，当前数据未变更。", cleanupPendingFile: true, closePreview: true)
                    }
                    return
                }
                await MainActor.run {
                    isImportingBackup = false
                    importTask = nil
                    setStatus("导入失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func exportBackupZIP() {
        cleanupExportArchiveIfNeeded()
        lastExportSucceeded = false
        clearStatus()
        beginExportTask(currentItem: "准备导出")
        let snapshot = store.makeSnapshot(includePhotoFiles: false)
        exportTask = Task {
            do {
                let outcome = try await BackupExportCoordinator.exportBackup(
                    snapshot: snapshot,
                    suggestedFileName: "\(AppBrand.exportFilePrefix)_完整备份.zip",
                    progress: { progress in
                        Task { @MainActor in
                            exportProgress = progress
                        }
                    },
                    shouldCancel: { Task.isCancelled }
                )
                await MainActor.run {
                    finalizeExportTask()
                    exportFileURL = outcome.preparedFileURL
                    exportSummary = outcome.summary
                    showExporter = true
                }
            } catch {
                if Task.isCancelled {
                    await MainActor.run {
                        finalizeExportTask(status: "已取消导出", cleanupExportFile: true)
                    }
                    return
                }
                if let archiveError = error as? BackupArchiveError, case .cancelled = archiveError {
                    await MainActor.run {
                        finalizeExportTask(status: "已取消导出", cleanupExportFile: true)
                    }
                    return
                }
                await MainActor.run {
                    finalizeExportTask(status: "备份生成失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func refreshCloudBackups(force: Bool = false) {
        if cloudState.isRefreshingCloudBackups && !force {
            return
        }

        beginCloudRefreshTask()
        cloudState.cloudBackupTask = Task {
            do {
                let files = try await BackupCloudTaskCoordinator.refreshBackups()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    applyCloudBackupsRefreshSuccess(files: files, force: force)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    applyCloudBackupsRefreshFailure(error: error)
                }
            }
        }
    }

    @MainActor
    private func applyCloudBackupsRefreshSuccess(files: [CloudBackupFile], force: Bool) {
        cloudState.cloudBackups = files
        if files.isEmpty && force {
            setCloudStatus("iCloud 中还没有备份。")
        } else if !files.isEmpty && cloudState.cloudStatusMessage.contains("没有备份") {
            clearCloudStatus()
        }
        cloudState.isRefreshingCloudBackups = false
        cloudState.cloudBackupTask = nil
    }

    @MainActor
    private func applyCloudBackupsRefreshFailure(error: Error) {
        cloudState.cloudBackups = []
        setCloudStatus("iCloud 读取失败：\(error.localizedDescription)")
        cloudState.isRefreshingCloudBackups = false
        cloudState.cloudBackupTask = nil
    }

    private func uploadBackupToICloud() {
        lastExportSucceeded = false
        clearAllStatusMessages()
        let options = cloudBackupOptions
        guard options.hasSelectedContent else {
            setCloudStatus(CloudBackupContentError.noSelection.localizedDescription)
            return
        }
        beginCloudUploadTask(currentItem: "准备生成云备份")
        let snapshot = store.makeCloudBackupSnapshot(options: options)

        cloudState.cloudBackupTask = Task {
            do {
                let result = try await BackupCloudTaskCoordinator.uploadBackup(
                    snapshot: snapshot,
                    progress: { progress in
                        Task { @MainActor in
                            exportProgress = progress
                        }
                    }
                )

                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeCloudBackupTask(status: "已取消 iCloud 备份")
                    }
                    return
                }

                await MainActor.run {
                    cloudState.cloudBackups = result.allBackups
                    setCloudStatus("已备份到 iCloud：\(result.savedFile.formattedSize)，\(result.savedFile.formattedModifiedAt)。")
                    cloudLastSuccessAt = result.savedFile.modifiedAt.timeIntervalSince1970
                    hasCompletedBackupExportTask = true
                    hasSeenBackupGuide = true
                    finalizeCloudBackupTask()
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeCloudBackupTask(status: "已取消 iCloud 备份")
                    }
                    return
                }
                await MainActor.run {
                    finalizeCloudBackupTask(status: "iCloud 备份失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func restorePendingCloudBackup() {
        guard let file = cloudState.pendingCloudRestore else {
            setCloudStatus(CloudBackupError.backupNotFound.localizedDescription)
            return
        }
        cloudState.pendingCloudRestore = nil
        importMode = .merge
        clearAllStatusMessages()
        beginImportTask(
            title: "正在读取 iCloud 备份",
            totalBytes: Int64(max(file.byteSize, 1)),
            currentItem: "准备读取"
        )

        importTask = Task {
            do {
                let copiedURL = try await BackupCloudTaskCoordinator.copyCloudBackupToTemporaryFile(file)
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeImportTask(cleanupPendingFile: true)
                    }
                    return
                }
                await MainActor.run {
                    finalizeImportTask()
                    startPreviewImportFromPreparedFile(copiedURL)
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeImportTask(status: "已取消读取 iCloud 备份", cleanupPendingFile: true)
                    }
                    return
                }
                await MainActor.run {
                    finalizeImportTask(status: "iCloud 备份读取失败：\(error.localizedDescription)", cleanupPendingFile: true)
                }
            }
        }
    }

    @MainActor
    private func finalizeCloudBackupTask(status: String? = nil) {
        BackupTaskStateReducer.finalizeCloud(state: &cloudState, status: status)
    }

    @MainActor
    private func finalizeImportTask(
        status: String? = nil,
        cleanupPendingFile: Bool = false,
        closePreview: Bool = false
    ) {
        BackupTaskStateReducer.finalizeImport(
            isImportingBackup: &isImportingBackup,
            importTask: &importTask,
            statusMessage: &statusMessage,
            status: status
        )
        if closePreview {
            showPreview = false
        }
        if cleanupPendingFile {
            cleanupPendingImportFileIfNeeded()
        }
    }

    @MainActor
    private func finalizeExportTask(status: String? = nil, cleanupExportFile: Bool = false) {
        BackupTaskStateReducer.finalizeExport(
            isExportingArchive: &isExportingArchive,
            exportTask: &exportTask,
            statusMessage: &statusMessage,
            status: status
        )
        if cleanupExportFile {
            cleanupExportArchiveIfNeeded()
        }
    }

    @MainActor
    private func resetBackupRuntimeStateOnDisappear() {
        estimateState.backupEstimateTask?.cancel()
        estimateState.backupEstimateTask = nil
        estimateState.isEstimatingBackup = false

        exportTask?.cancel()
        cloudState.cloudBackupTask?.cancel()
        importTask?.cancel()

        finalizeExportTask(cleanupExportFile: true)
        finalizeCloudBackupTask()
        finalizeImportTask(cleanupPendingFile: true)
    }

    private func injectUITestPreview() {
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-uitest-preview-\(UUID().uuidString).json")
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: tempURL, options: .atomic)
        } catch {
            StorageIssueLog.record("UI 测试预览备份写入失败：\(tempURL.lastPathComponent)，\(error.localizedDescription)")
            return
        }

        cleanupPendingImportFileIfNeeded()
        pendingImportFileURL = tempURL
        pendingImportPreview = BackupImportPreview(
            snapshot: snapshot,
            photoFileCount: 0,
            drawingFileCount: 0,
            documentFileCount: 0,
            quickNoteAttachmentFileCount: 0
        )
        // UI 测试快捷入口默认使用覆盖模式，便于稳定验证覆盖导入确认流程。
        importMode = .overwrite
        isOverwriteImportArmed = false
        showPreview = false
        Task { @MainActor in
            showPreview = true
        }
    }

    private var exportProgressCard: some View {
        BackupTaskProgressCard(
            title: cloudState.isUploadingCloudBackup ? "正在生成 iCloud 备份" : "正在生成备份 ZIP",
            subtitle: exportProgress.currentItem,
            progressValue: exportProgress.fractionCompleted,
            detail: "\(exportProgress.completedSteps)/\(max(exportProgress.totalSteps, 1))",
            cancelTitle: cloudState.isUploadingCloudBackup ? "取消云备份" : "取消导出",
            onCancel: {
                AppHaptics.warning()
                exportProgress = BackupArchiveProgress(
                    completedSteps: exportProgress.completedSteps,
                    totalSteps: max(exportProgress.totalSteps, 1),
                    currentItem: "正在取消..."
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
            cancelTitle: "取消导入",
            onCancel: {
                AppHaptics.warning()
                importProgress = BackupImportProgress(
                    completedBytes: importProgress.completedBytes,
                    totalBytes: max(importProgress.totalBytes, 1),
                    currentItem: "正在取消..."
                )
                importTask?.cancel()
            }
        )
    }

    private func cleanupExportArchiveIfNeeded() {
        guard let exportFileURL else { return }
        ExportFileURLPreparer.cleanup(fileURL: exportFileURL)
        self.exportFileURL = nil
    }

    private func cleanupPendingImportFileIfNeeded() {
        guard let pendingImportFileURL else { return }
        if FileManager.default.fileExists(atPath: pendingImportFileURL.path) {
            do {
                try FileManager.default.removeItem(at: pendingImportFileURL)
            } catch {
                StorageIssueLog.record("导入临时文件清理失败：\(pendingImportFileURL.lastPathComponent)，\(error.localizedDescription)")
            }
        }
        self.pendingImportFileURL = nil
        self.pendingImportPreview = nil
    }

    private func refreshBackupEstimateIfNeeded(force: Bool = false) {
        let signature = backupEstimateSignature
        if !force, signature == estimateState.lastBackupEstimateSignature {
            return
        }

        estimateState.backupEstimateTask?.cancel()
        estimateState.isEstimatingBackup = true
        let snapshot = store.makeSnapshot(includePhotoFiles: false)

        estimateState.backupEstimateTask = Task {
            let estimate = await Task.detached(priority: .utility) {
                BackupArchiveService.estimateArchive(from: snapshot)
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run {
                estimateState.backupEstimate = estimate
                estimateState.lastBackupEstimateSignature = signature
                estimateState.isEstimatingBackup = false
            }
        }
    }

    private func normalizeCloudBackupSettings() {
        if CloudBackupAutoInterval(rawValue: cloudAutoIntervalRawValue) == nil {
            cloudAutoIntervalRawValue = CloudBackupAutoInterval.disabled.rawValue
        }
        if !cloudIncludeProjectRecords {
            cloudIncludeProjectFilesAndNotes = false
            cloudIncludeAttachments = false
        } else if !cloudIncludeProjectFilesAndNotes {
            cloudIncludeAttachments = false
        }
    }

    private func setStatus(_ message: String) {
        statusMessage = message
        emitStatusHaptic(message)
    }

    private func clearStatus() {
        statusMessage = ""
    }

    private func setCloudStatus(_ message: String) {
        cloudState.cloudStatusMessage = message
        emitStatusHaptic(message)
    }

    private func clearCloudStatus() {
        cloudState.cloudStatusMessage = ""
    }

    private func clearAllStatusMessages() {
        clearStatus()
        clearCloudStatus()
    }

    private func emitStatusHaptic(_ message: String) {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if normalized.contains("失败")
            || normalized.contains("错误")
            || normalized.contains("未能")
            || normalized.contains("失效")
            || normalized.contains("不正确") {
            AppHaptics.error()
            return
        }
        if normalized.contains("取消")
            || normalized.contains("警告")
            || normalized.contains("提示") {
            AppHaptics.warning()
            return
        }
        AppHaptics.success()
    }

    private func beginExportTask(currentItem: String) {
        exportTask?.cancel()
        AppHaptics.impact(.light)
        isExportingArchive = true
        exportProgress = BackupArchiveProgress(completedSteps: 0, totalSteps: 1, currentItem: currentItem)
    }

    private func beginImportTask(title: String, totalBytes: Int64, currentItem: String) {
        importTask?.cancel()
        AppHaptics.impact(.light)
        isImportingBackup = true
        importProgressTitle = title
        importProgress = BackupImportProgress(
            completedBytes: 0,
            totalBytes: max(totalBytes, 1),
            currentItem: currentItem
        )
    }

    private func beginCloudRefreshTask() {
        cloudState.cloudBackupTask?.cancel()
        cloudState.isRefreshingCloudBackups = true
    }

    private func beginCloudUploadTask(currentItem: String) {
        cloudState.cloudBackupTask?.cancel()
        cloudState.isUploadingCloudBackup = true
        exportProgress = BackupArchiveProgress(completedSteps: 0, totalSteps: 1, currentItem: currentItem)
    }

    private func formattedFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}
