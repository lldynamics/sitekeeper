import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct BackupView: View {
    @Environment(DataStore.self) private var store
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
    @State private var showOverwriteImportConfirm = false
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
    @State private var backupEstimate = BackupArchiveEstimate(metadataBytes: 0, rawFilesBytes: 0, missingFiles: [])
    @State private var isEstimatingBackup = false
    @State private var backupEstimateTask: Task<Void, Never>?
    @State private var lastBackupEstimateSignature = 0
    @State private var cloudBackups: [CloudBackupFile] = []
    @State private var cloudStatusMessage = ""
    @State private var isRefreshingCloudBackups = false
    @State private var isUploadingCloudBackup = false
    @State private var cloudBackupTask: Task<Void, Never>?
    @State private var pendingCloudRestore: CloudBackupFile?
    @State private var showCloudRestoreConfirm = false
    private let autoOpenImporter: Bool
    private let cloudBackupScopeHint = "可按业务模块选择备份范围。关闭“原文件附件”可显著减小体积。"
    private let cloudCellularTrafficHint = "提示：在蜂窝网络下手动或自动备份 iCloud 会消耗移动数据流量，建议大包资料优先在 Wi‑Fi 下操作。"

    init(autoOpenImporter: Bool = false) {
        self.autoOpenImporter = autoOpenImporter
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

        hasher.combine(dailyLogPhotoCount)
        hasher.combine(todoPhotoCount)
        hasher.combine(quickNoteAttachmentCount)
        return hasher.finalize()
    }

    private var shouldShowFirstBackupGuide: Bool {
        !hasCompletedBackupExportTask && !hasSeenBackupGuide && !lastImportSucceeded
    }

    private var shouldShowMicroGuides: Bool {
        !isExportingArchive
            && !isImportingBackup
            && (backupEstimate.missingFiles.count > 0 || lastExportSucceeded || lastImportSucceeded)
    }

    private var showsUITestPreviewShortcut: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest-backup-preview")
            || ProcessInfo.processInfo.environment["UITEST_BACKUP_PREVIEW"] == "1"
    }

    private var isBusy: Bool {
        isExportingArchive || isImportingBackup || isUploadingCloudBackup
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
        CloudBackupAutoInterval(rawValue: cloudAutoIntervalRawValue) ?? .disabled
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

    private var cloudStatusHintColor: Color {
        if cloudStatusMessage.contains("失败") || cloudStatusMessage.contains("未能") {
            return .orange
        }
        return .secondary
    }

    private var cloudBackupSection: some View {
        Section("iCloud 云备份") {
            cloudBackupActionRows
            cloudBackupContentScopeRows
            cloudBackupAutoBackupRows
            cloudBackupHistoryRows
            cloudBackupStatusRows
        }
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

    @ViewBuilder
    private var cloudBackupActionRows: some View {
        Button {
            uploadBackupToICloud()
        } label: {
            Label("立即备份到 iCloud", systemImage: "icloud.and.arrow.up")
        }
        .disabled(isBusy)

        Button {
            refreshCloudBackups(force: true)
        } label: {
            Label("刷新云端备份列表", systemImage: "arrow.clockwise")
        }
        .disabled(isBusy || isRefreshingCloudBackups)

        if isRefreshingCloudBackups {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在读取 iCloud 备份…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Text(cloudCellularTrafficHint)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var cloudBackupContentScopeRows: some View {
        Toggle("业务数据", isOn: $cloudIncludeBusinessRecords)
        Toggle("项目记录", isOn: $cloudIncludeProjectRecords)
        Toggle("项目资料与随手记", isOn: $cloudIncludeProjectFilesAndNotes)
            .disabled(!cloudIncludeProjectRecords)
        Toggle("原文件附件（照片/图纸/文档）", isOn: $cloudIncludeAttachments)
            .disabled(!cloudIncludeProjectRecords || !cloudIncludeProjectFilesAndNotes)
        Toggle("资料库（材料价/供应商/工艺）", isOn: $cloudIncludeKnowledgeBase)

        Text(cloudBackupScopeHint)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var cloudBackupAutoBackupRows: some View {
        Picker("自动备份", selection: $cloudAutoIntervalRawValue) {
            ForEach(CloudBackupAutoInterval.allCases, id: \.rawValue) { interval in
                Text(interval.title).tag(interval.rawValue)
            }
        }

        if cloudAutoInterval != .disabled {
            Toggle("仅在 Wi‑Fi 下自动备份", isOn: $cloudAutoBackupRequiresWiFi)
                .disabled(isBusy)
            Text(cloudAutoNetworkHint)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let nextDate = cloudNextAutoBackupDate {
                LabeledContent("下次预计", value: Formatters.dateTime.string(from: nextDate))
            }
        }

        if let lastSuccessDate = cloudLastSuccessDate {
            LabeledContent("最近成功", value: Formatters.dateTime.string(from: lastSuccessDate))
        }
        if !cloudAutoLastStatus.isEmpty {
            Text(cloudAutoLastStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var cloudBackupHistoryRows: some View {
        if cloudBackups.isEmpty {
            if !isRefreshingCloudBackups {
                Text("iCloud 中还没有备份。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            ForEach(Array(cloudBackups.enumerated()), id: \.element.id) { index, file in
                CloudBackupListRow(file: file, isLatest: index == 0) {
                    pendingCloudRestore = file
                    showCloudRestoreConfirm = true
                }
            }
        }
    }

    @ViewBuilder
    private var cloudBackupStatusRows: some View {
        if !cloudStatusMessage.isEmpty {
            Text(cloudStatusMessage)
                .font(.caption)
                .foregroundStyle(cloudStatusHintColor)
        }
    }

    var body: some View {
        ZStack {
            Form {
                if shouldShowFirstBackupGuide {
                    Section("备份建议") {
                        BackupQuickStartCard(
                            onExport: {
                                exportBackupZIP()
                            },
                            onDismiss: {
                                hasSeenBackupGuide = true
                            }
                        )
                    }
                }

                Section("本地备份") {
                    Button { exportBackupZIP() } label: {
                        Label("导出完整备份 ZIP", systemImage: "archivebox")
                    }
                    .disabled(isBusy)
                    Button { showImporter = true } label: {
                        Label("导入备份 ZIP", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isBusy)
                    if showsUITestPreviewShortcut {
                        Button("UI测试：模拟覆盖导入预览") {
                            injectUITestPreview()
                        }
                        .accessibilityIdentifier("ui-test-backup-preview")

                        Button("UI测试：触发覆盖二次确认") {
                            showUITestOverwriteImportConfirm = true
                        }
                        .accessibilityIdentifier("ui-test-overwrite-confirm")
                    }
                }

                cloudBackupSection

                if shouldShowMicroGuides {
                    Section("建议下一步") {
                        if backupEstimate.missingFiles.count > 0 {
                            BackupMicroGuideRow(
                                icon: "exclamationmark.triangle.fill",
                                color: .orange,
                                title: String(localized: "检测到 \(backupEstimate.missingFiles.count) 个原文件缺失"),
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

                Section("预计体积") {
                    if isEstimatingBackup {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在后台估算备份体积…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("数据索引", value: formattedFileSize(backupEstimate.metadataBytes))
                    LabeledContent("原文件", value: formattedFileSize(backupEstimate.rawFilesBytes))
                    LabeledContent("预计合计", value: formattedFileSize(backupEstimate.estimatedBytes))
                    Text("备份导出不设体积上限，会按 ZIP64 流式打包；大文件导出前请确认设备剩余空间充足。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !backupEstimate.missingFiles.isEmpty {
                        Text(String(localized: "发现 \(backupEstimate.missingFiles.count) 个原文件缺失，备份包会记录缺失清单。"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if backupEstimate.estimatedBytes >= BackupArchiveService.largeArchiveWarningBytes {
                        Text("预计体积较大，导出可能持续较久；请保持 App 在前台、电量充足，并预留导出包体积以上的可用空间。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section("版本") {
                    HStack { Text("备份格式版本"); Spacer(); Text("2 · ZIP").foregroundStyle(.secondary) }
                }
                if !statusMessage.isEmpty {
                    Section { Text(statusMessage).font(.caption) }
                }
            }
            if isExportingArchive || isUploadingCloudBackup {
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
        .navigationTitle("数据备份")
        .sheet(isPresented: $showExporter) {
            if let exportFileURL {
                FileURLDocumentExporter(fileURL: exportFileURL) { result in
                    if case .success = result {
                        statusMessage = exportSummary.isEmpty ? "导出成功" : exportSummary
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
                statusMessage = "未能读取所选文件：\(error.localizedDescription)"
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
        .alert("从 iCloud 恢复备份？", isPresented: $showCloudRestoreConfirm) {
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
            backupEstimateTask?.cancel()
            backupEstimateTask = nil
            isEstimatingBackup = false
            exportTask?.cancel()
            exportTask = nil
            cloudBackupTask?.cancel()
            cloudBackupTask = nil
            isExportingArchive = false
            isUploadingCloudBackup = false
            importTask?.cancel()
            importTask = nil
            isImportingBackup = false
            cleanupExportArchiveIfNeeded()
            cleanupPendingImportFileIfNeeded()
        }
    }

    private func importPreview(preview: BackupImportPreview) -> some View {
        let snapshot = preview.snapshot
        return NavigationStack {
            Form {
                Section("导入预览") {
                    LabeledContent("材料", value: "\(snapshot.materialItems.count) 条")
                    LabeledContent("报价", value: "\(snapshot.quoteItems.count) 条")
                    LabeledContent("人工记录", value: "\(snapshot.laborRecords.count) 条")
                    LabeledContent("项目", value: "\(snapshot.projects.count) 个")
                    LabeledContent("回路方案", value: "\(snapshot.lightingCircuitPlans.count) 条")
                    LabeledContent("现场待办", value: "\(snapshot.siteTodos.count) 条")
                    LabeledContent("收款记录", value: "\(snapshot.paymentRecords.count) 条")
                    LabeledContent("项目图纸", value: "\(snapshot.projectDrawings.count) 份")
                    LabeledContent("项目联系人", value: "\(snapshot.projectContacts.count) 位")
                    LabeledContent("零星收支", value: "\(snapshot.projectFinancialRecords.count) 条")
                    LabeledContent("项目资料", value: "\(snapshot.projectDocuments.count) 份")
                    LabeledContent("随手记", value: "\(snapshot.quickNotes.count) 条")
                    LabeledContent("施工日志", value: "\(snapshot.dailyLogs.count) 条")
                    LabeledContent("现场照片", value: "\(preview.photoFileCount) 张")
                    LabeledContent("图纸文件", value: "\(preview.drawingFileCount) 份")
                    LabeledContent("扫描资料", value: "\(preview.documentFileCount) 份")
                    LabeledContent("随手记附件", value: "\(preview.quickNoteAttachmentFileCount) 份")
                    LabeledContent("材料价格库", value: "\(snapshot.materialPriceEntries.count) 条")
                    LabeledContent("供应商库", value: "\(snapshot.supplierProfiles.count) 条")
                    LabeledContent("施工工艺库", value: "\(snapshot.constructionMethods.count) 条")
                    LabeledContent("进度任务", value: "\(snapshot.progressTasks.count) 条")
                    LabeledContent("历史计算", value: "\(snapshot.historyRecords.count) 条")
                }
                Section("导入方式") {
                    Picker("方式", selection: $importMode) {
                        Text("合并（保留现有数据）").tag(ImportMode.merge)
                        Text("覆盖（替换全部数据）").tag(ImportMode.overwrite)
                    }
                    .pickerStyle(.segmented)
                    if importMode == .overwrite {
                        Text("覆盖会删除当前本机数据，请先导出备份。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    Button("确认导入") {
                        if importMode == .overwrite {
                            showOverwriteImportConfirm = true
                        } else {
                            startApplyingImport()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                        .tint(.orange)
                }
            }
            .navigationTitle("确认导入").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showPreview = false
                        cleanupPendingImportFileIfNeeded()
                    }
                }
            }
            .alert("确认覆盖导入？", isPresented: $showOverwriteImportConfirm) {
                Button("取消", role: .cancel) {}
                Button("覆盖导入", role: .destructive) {
                    startApplyingImport()
                }
            } message: {
                Text("覆盖会删除当前本机数据，请先导出备份。")
            }
        }
    }

    private func startPreviewImport(from selectedURL: URL) {
        statusMessage = ""
        do {
            let copiedURL = try copySelectedBackupToSandbox(selectedURL)
            startPreviewImportFromPreparedFile(copiedURL)
        } catch {
            statusMessage = error.localizedDescription
            cleanupPendingImportFileIfNeeded()
        }
    }

    private func startPreviewImportFromPreparedFile(_ copiedURL: URL) {
        cleanupPendingImportFileIfNeeded()
        pendingImportPreview = nil
        pendingImportFileURL = copiedURL

        importTask?.cancel()
        isImportingBackup = true
        importProgressTitle = "正在读取备份预览"
        importProgress = BackupImportProgress(completedBytes: 0, totalBytes: Int64(max(QuickNoteAttachmentStorage.fileSize(at: copiedURL), 1)), currentItem: "准备读取")
        importTask = Task {
            do {
                let preview = try await Task.detached(priority: .userInitiated) {
                    try BackupArchiveService.previewBackup(
                        from: copiedURL,
                        progress: { progress in
                            Task { @MainActor in
                                importProgress = progress
                            }
                        },
                        shouldCancel: { Task.isCancelled }
                    )
                }.value
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
                    statusMessage = "文件格式不正确：\(error.localizedDescription)"
                    cleanupPendingImportFileIfNeeded()
                }
            }
        }
    }

    private func copySelectedBackupToSandbox(_ selectedURL: URL) throws -> URL {
        let hasAccess = selectedURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                selectedURL.stopAccessingSecurityScopedResource()
            }
        }

        let ext = selectedURL.pathExtension.isEmpty ? "zip" : selectedURL.pathExtension
        let copiedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-import-\(UUID().uuidString).\(ext)")
        if FileManager.default.fileExists(atPath: copiedURL.path) {
            try FileManager.default.removeItem(at: copiedURL)
        }
        try FileManager.default.copyItem(at: selectedURL, to: copiedURL)
        return copiedURL
    }

    private func startApplyingImport() {
        guard let pendingImportFileURL else {
            statusMessage = "备份源文件已失效，请重新选择导入文件。"
            showPreview = false
            return
        }

        let metadataSnapshot = pendingImportPreview?.snapshot
        let sourceSize = Int64(max(QuickNoteAttachmentStorage.fileSize(at: pendingImportFileURL), 1))

        importTask?.cancel()
        isImportingBackup = true
        importProgressTitle = "正在应用数据索引"
        importProgress = BackupImportProgress(completedBytes: 0, totalBytes: sourceSize, currentItem: "准备导入")

        importTask = Task {
            do {
                let snapshot: BackupSnapshot
                if let metadataSnapshot {
                    snapshot = metadataSnapshot
                } else {
                    let preview = try await Task.detached(priority: .userInitiated) {
                        try BackupArchiveService.previewBackup(
                            from: pendingImportFileURL,
                            progress: { progress in
                                Task { @MainActor in
                                    importProgress = progress
                                }
                            },
                            shouldCancel: { Task.isCancelled }
                        )
                    }.value
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

                let restoredCounts = try await Task.detached(priority: .userInitiated) {
                    try BackupArchiveService.restoreEmbeddedFiles(
                        from: pendingImportFileURL,
                        progress: { progress in
                            Task { @MainActor in
                                importProgress = progress
                            }
                        },
                        shouldCancel: { Task.isCancelled }
                    )
                }.value

                await MainActor.run {
                    importProgressTitle = "正在应用数据索引"
                    applyImportMetadata(snapshot)
                    if importMode == .overwrite {
                        cleanupOverwrittenFiles(previous: existingSnapshot, imported: snapshot)
                    }
                    isImportingBackup = false
                    importTask = nil
                    store.save(includePhotoFiles: false)
                    showPreview = false
                    lastImportSucceeded = true
                    lastExportSucceeded = false
                    hasSeenBackupGuide = true
                    if restoredCounts.totalCount > 0 {
                        statusMessage = "导入完成（恢复 \(restoredCounts.totalCount) 个原文件）"
                    } else {
                        statusMessage = "导入完成"
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
                    statusMessage = "导入失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func applyImportMetadata(_ snapshot: BackupSnapshot) {
        switch importMode {
        case .merge:
            appendUniqueByID(snapshot.materialItems, to: &store.materialItems)
            appendUniqueByID(snapshot.quoteItems, to: &store.quoteItems)
            appendUniqueByID(snapshot.laborRecords, to: &store.laborRecords)
            appendUniqueByID(snapshot.projects, to: &store.projects)
            appendUniqueByID(snapshot.dailyLogs, to: &store.dailyLogs)
            appendUniqueByID(snapshot.historyRecords, to: &store.historyRecords)
            appendUniqueByID(snapshot.progressTasks, to: &store.progressTasks)
            appendUniqueByID(snapshot.lightingCircuitPlans, to: &store.lightingCircuitPlans)
            appendUniqueByID(snapshot.siteTodos, to: &store.siteTodos)
            appendUniqueByID(snapshot.paymentRecords, to: &store.paymentRecords)
            appendUniqueByID(snapshot.projectDrawings, to: &store.projectDrawings)
            appendUniqueByID(snapshot.projectContacts, to: &store.projectContacts)
            appendUniqueByID(snapshot.projectFinancialRecords, to: &store.projectFinancialRecords)
            appendUniqueByID(snapshot.projectDocuments, to: &store.projectDocuments)
            appendUniqueByID(snapshot.quickNotes, to: &store.quickNotes)
            appendUniqueByID(snapshot.projectWarehouseMovements, to: &store.projectWarehouseMovements)
            appendUniqueByID(snapshot.templates, to: &store.templates)
            appendUniqueByID(snapshot.materialPriceEntries, to: &store.materialPriceEntries)
            appendUniqueByID(snapshot.supplierProfiles, to: &store.supplierProfiles)
            appendUniqueByID(snapshot.constructionMethods, to: &store.constructionMethods)
            store.favoriteMaterialKeys = mergeUniqueStrings(existing: store.favoriteMaterialKeys, incoming: snapshot.favoriteMaterialKeys)
            store.recentMaterialKeys = mergeUniqueStrings(existing: store.recentMaterialKeys, incoming: snapshot.recentMaterialKeys)
            appendUniqueByID(snapshot.userMaterials, to: &store.userMaterials)
            appendUniqueByID(snapshot.deletedUserMaterials, to: &store.deletedUserMaterials)
            store.hiddenPresetKeys.formUnion(snapshot.hiddenPresetKeys)
        case .overwrite:
            store.materialItems = snapshot.materialItems
            store.quoteItems = snapshot.quoteItems
            store.laborRecords = snapshot.laborRecords
            store.projects = snapshot.projects
            store.dailyLogs = snapshot.dailyLogs
            store.historyRecords = snapshot.historyRecords
            store.progressTasks = snapshot.progressTasks
            store.lightingCircuitPlans = snapshot.lightingCircuitPlans
            store.siteTodos = snapshot.siteTodos
            store.paymentRecords = snapshot.paymentRecords
            store.projectDrawings = snapshot.projectDrawings
            store.projectContacts = snapshot.projectContacts
            store.projectFinancialRecords = snapshot.projectFinancialRecords
            store.projectDocuments = snapshot.projectDocuments
            store.quickNotes = snapshot.quickNotes
            store.projectWarehouseMovements = snapshot.projectWarehouseMovements
            store.templates = snapshot.templates
            store.materialPriceEntries = snapshot.materialPriceEntries
            store.supplierProfiles = snapshot.supplierProfiles
            store.constructionMethods = snapshot.constructionMethods
            store.favoriteMaterialKeys = snapshot.favoriteMaterialKeys
            store.recentMaterialKeys = snapshot.recentMaterialKeys
            store.userMaterials = snapshot.userMaterials
            store.deletedUserMaterials = snapshot.deletedUserMaterials
            store.hiddenPresetKeys = snapshot.hiddenPresetKeys
        }
    }

    private func appendUniqueByID<T: Identifiable>(_ incoming: [T], to current: inout [T]) where T.ID: Hashable {
        var existing = Set(current.map(\.id))
        for item in incoming where !existing.contains(item.id) {
            current.append(item)
            existing.insert(item.id)
        }
    }

    private func mergeUniqueStrings(existing: [String], incoming: [String]) -> [String] {
        var seen = Set(existing)
        var merged = existing
        for key in incoming where !key.isEmpty && !seen.contains(key) {
            merged.append(key)
            seen.insert(key)
        }
        return merged
    }

    private func cleanupOverwrittenFiles(previous: BackupSnapshot, imported: BackupSnapshot) {
        let oldPhotoNames = photoFileNames(in: previous)
        let newPhotoNames = photoFileNames(in: imported)
        let oldDrawingNames = Set(previous.projectDrawings.map(\.fileName).filter { !$0.isEmpty })
        let newDrawingNames = Set(imported.projectDrawings.map(\.fileName).filter { !$0.isEmpty })
        let oldDocumentNames = Set(previous.projectDocuments.map(\.fileName).filter { !$0.isEmpty })
        let newDocumentNames = Set(imported.projectDocuments.map(\.fileName).filter { !$0.isEmpty })
        let oldQuickNoteAttachmentNames = quickNoteAttachmentFileNames(in: previous)
        let newQuickNoteAttachmentNames = quickNoteAttachmentFileNames(in: imported)

        PhotoStorage.delete(fileNames: Array(oldPhotoNames.subtracting(newPhotoNames)))
        DrawingStorage.delete(fileNames: Array(oldDrawingNames.subtracting(newDrawingNames)))
        ProjectDocumentStorage.delete(fileNames: Array(oldDocumentNames.subtracting(newDocumentNames)))
        QuickNoteAttachmentStorage.delete(fileNames: Array(oldQuickNoteAttachmentNames.subtracting(newQuickNoteAttachmentNames)))
    }

    private func photoFileNames(in snapshot: BackupSnapshot) -> Set<String> {
        var names = Set(snapshot.dailyLogs.flatMap(\.allPhotoFileNames).filter { !$0.isEmpty })
        names.formUnion(snapshot.siteTodos.compactMap(\.rectificationBeforePhotoFileName).filter { !$0.isEmpty })
        names.formUnion(snapshot.siteTodos.compactMap(\.rectificationAfterPhotoFileName).filter { !$0.isEmpty })
        return names
    }

    private func quickNoteAttachmentFileNames(in snapshot: BackupSnapshot) -> Set<String> {
        Set(snapshot.quickNotes.flatMap { $0.attachments.map(\.fileName) }.filter { !$0.isEmpty })
    }

    private func exportBackupZIP() {
        cleanupExportArchiveIfNeeded()
        lastExportSucceeded = false
        statusMessage = ""
        isExportingArchive = true
        exportProgress = BackupArchiveProgress(completedSteps: 0, totalSteps: 1, currentItem: "准备导出")
        let snapshot = store.makeSnapshot(includePhotoFiles: false)
        exportTask?.cancel()
        exportTask = Task {
            do {
                let archive = try await Task.detached(priority: .userInitiated) {
                    try BackupArchiveService.makeArchive(
                        from: snapshot,
                        progress: { progress in
                            Task { @MainActor in
                                exportProgress = progress
                            }
                        },
                        shouldCancel: { Task.isCancelled }
                    )
                }.value
                let archiveTotalBytes = archive.totalBytes
                let preparedURL = try ExportFileURLPreparer.prepare(
                    sourceFileURL: archive.fileURL,
                    suggestedFileName: "\(AppBrand.exportFilePrefix)_完整备份.zip"
                )
                guard !Task.isCancelled else {
                    ExportFileURLPreparer.cleanup(fileURL: preparedURL)
                    await MainActor.run {
                        finalizeExportTask(status: "已取消导出", cleanupExportFile: true)
                    }
                    return
                }
                await MainActor.run {
                    isExportingArchive = false
                    exportTask = nil
                    exportFileURL = preparedURL
                    exportSummary = "导出成功：包含 \(archive.includedFileCount) 个原文件，大小 \(formattedFileSize(archiveTotalBytes))。"
                    if !archive.missingFiles.isEmpty {
                        exportSummary += " 有 \(archive.missingFiles.count) 个原文件缺失，已写入备份包清单。"
                    }
                    showExporter = true
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeExportTask(status: "已取消导出", cleanupExportFile: true)
                    }
                    return
                }
                await MainActor.run {
                    isExportingArchive = false
                    exportTask = nil
                    statusMessage = "备份生成失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func refreshCloudBackups(force: Bool = false) {
        if isRefreshingCloudBackups && !force {
            return
        }

        cloudBackupTask?.cancel()
        isRefreshingCloudBackups = true
        cloudBackupTask = Task {
            do {
                let files = try await Task.detached(priority: .utility) {
                    try CloudBackupService.listBackups()
                }.value
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    cloudBackups = files
                    if files.isEmpty && force {
                        cloudStatusMessage = "iCloud 中还没有备份。"
                    } else if !files.isEmpty && cloudStatusMessage.contains("没有备份") {
                        cloudStatusMessage = ""
                    }
                    isRefreshingCloudBackups = false
                    cloudBackupTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    cloudBackups = []
                    cloudStatusMessage = "iCloud 读取失败：\(error.localizedDescription)"
                    isRefreshingCloudBackups = false
                    cloudBackupTask = nil
                }
            }
        }
    }

    private func uploadBackupToICloud() {
        cloudBackupTask?.cancel()
        lastExportSucceeded = false
        cloudStatusMessage = ""
        statusMessage = ""
        let options = cloudBackupOptions
        guard options.hasSelectedContent else {
            cloudStatusMessage = CloudBackupContentError.noSelection.localizedDescription
            return
        }
        isUploadingCloudBackup = true
        exportProgress = BackupArchiveProgress(completedSteps: 0, totalSteps: 1, currentItem: "准备生成云备份")
        let snapshot = store.makeCloudBackupSnapshot(options: options)

        cloudBackupTask = Task {
            do {
                let result = try await CloudBackupCoordinator.shared.backupToCloud(
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
                    cloudBackups = result.allBackups
                    cloudStatusMessage = "已备份到 iCloud：\(result.savedFile.formattedSize)，\(result.savedFile.formattedModifiedAt)。"
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
        guard let file = pendingCloudRestore else {
            cloudStatusMessage = CloudBackupError.backupNotFound.localizedDescription
            return
        }
        pendingCloudRestore = nil
        importMode = .merge
        statusMessage = ""
        cloudStatusMessage = ""
        importTask?.cancel()
        isImportingBackup = true
        importProgressTitle = "正在读取 iCloud 备份"
        importProgress = BackupImportProgress(
            completedBytes: 0,
            totalBytes: Int64(max(file.byteSize, 1)),
            currentItem: "准备读取"
        )

        importTask = Task {
            do {
                let copiedURL = try await Task.detached(priority: .userInitiated) {
                    try CloudBackupService.copyBackupToTemporaryFile(file)
                }.value
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeImportTask(cleanupPendingFile: true)
                    }
                    return
                }
                await MainActor.run {
                    isImportingBackup = false
                    importTask = nil
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
        isUploadingCloudBackup = false
        isRefreshingCloudBackups = false
        cloudBackupTask = nil
        if let status {
            cloudStatusMessage = status
        }
    }

    @MainActor
    private func finalizeImportTask(
        status: String? = nil,
        cleanupPendingFile: Bool = false,
        closePreview: Bool = false
    ) {
        isImportingBackup = false
        importTask = nil
        if closePreview {
            showPreview = false
        }
        if let status {
            statusMessage = status
        }
        if cleanupPendingFile {
            cleanupPendingImportFileIfNeeded()
        }
    }

    @MainActor
    private func finalizeExportTask(status: String? = nil, cleanupExportFile: Bool = false) {
        isExportingArchive = false
        exportTask = nil
        if let status {
            statusMessage = status
        }
        if cleanupExportFile {
            cleanupExportArchiveIfNeeded()
        }
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

        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-uitest-preview-\(UUID().uuidString).json")
        try? data.write(to: tempURL, options: .atomic)

        cleanupPendingImportFileIfNeeded()
        pendingImportFileURL = tempURL
        pendingImportPreview = BackupImportPreview(
            snapshot: snapshot,
            photoFileCount: 0,
            drawingFileCount: 0,
            documentFileCount: 0,
            quickNoteAttachmentFileCount: 0
        )
        // UI 测试快捷入口默认使用覆盖模式，便于稳定验证二次确认弹窗。
        importMode = .overwrite
        showOverwriteImportConfirm = false
        showPreview = false
        DispatchQueue.main.async {
            showPreview = true
        }
    }

    private var exportProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isUploadingCloudBackup ? "正在生成 iCloud 备份" : "正在生成备份 ZIP")
                .font(.headline)
            Text(exportProgress.currentItem)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: exportProgress.fractionCompleted)
            Text("\(exportProgress.completedSteps)/\(max(exportProgress.totalSteps, 1))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消导出", role: .destructive) {
                    exportProgress = BackupArchiveProgress(
                        completedSteps: exportProgress.completedSteps,
                        totalSteps: max(exportProgress.totalSteps, 1),
                        currentItem: "正在取消..."
                    )
                    exportTask?.cancel()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 320)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private var importProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(importProgressTitle)
                .font(.headline)
            Text(importProgress.currentItem)
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: importProgress.fractionCompleted)
            Text("\(formattedFileSize(Int(importProgress.completedBytes)))/\(formattedFileSize(Int(importProgress.totalBytes)))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消导入", role: .destructive) {
                    importProgress = BackupImportProgress(
                        completedBytes: importProgress.completedBytes,
                        totalBytes: max(importProgress.totalBytes, 1),
                        currentItem: "正在取消..."
                    )
                    importTask?.cancel()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 320)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private func cleanupExportArchiveIfNeeded() {
        guard let exportFileURL else { return }
        ExportFileURLPreparer.cleanup(fileURL: exportFileURL)
        self.exportFileURL = nil
    }

    private func cleanupPendingImportFileIfNeeded() {
        guard let pendingImportFileURL else { return }
        if FileManager.default.fileExists(atPath: pendingImportFileURL.path) {
            try? FileManager.default.removeItem(at: pendingImportFileURL)
        }
        self.pendingImportFileURL = nil
        self.pendingImportPreview = nil
    }

    private func refreshBackupEstimateIfNeeded(force: Bool = false) {
        let signature = backupEstimateSignature
        if !force, signature == lastBackupEstimateSignature {
            return
        }

        backupEstimateTask?.cancel()
        isEstimatingBackup = true
        let snapshot = store.makeSnapshot(includePhotoFiles: false)

        backupEstimateTask = Task {
            let estimate = await Task.detached(priority: .utility) {
                BackupArchiveService.estimateArchive(from: snapshot)
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run {
                backupEstimate = estimate
                lastBackupEstimateSignature = signature
                isEstimatingBackup = false
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

    private func formattedFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

enum ImportMode: String, CaseIterable { case merge, overwrite }

private struct CloudBackupListRow: View {
    let file: CloudBackupFile
    let isLatest: Bool
    let onRestore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isLatest ? "clock.arrow.circlepath" : "icloud")
                .foregroundStyle(isLatest ? .orange : .blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(file.formattedModifiedAt)
                        .font(.subheadline.weight(.semibold))
                    if isLatest {
                        Text("最近")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(file.formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(file.fileName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("恢复") {
                onRestore()
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
    }
}

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zipArchive] }
    var data: Data
    var sourceFileURL: URL?

    init(data: Data, sourceFileURL: URL? = nil) {
        self.data = data
        self.sourceFileURL = sourceFileURL
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        sourceFileURL = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        if let sourceFileURL,
           FileManager.default.fileExists(atPath: sourceFileURL.path) {
            return try FileWrapper(url: sourceFileURL, options: .immediate)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

private struct BackupQuickStartCard: View {
    let onExport: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("先完成首份备份", systemImage: "shield.lefthalf.filled.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Button("不再提示", action: onDismiss)
                    .font(.caption.weight(.semibold))
            }

            Text("建议先导出一份完整 ZIP。后续误删、覆盖导入或换机时都能快速恢复。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: onExport) {
                Label("立即导出首份备份 ZIP", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Text("导入备份可在下方“本地备份”中选择 ZIP；旧版备份会自动兼容。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct BackupMicroGuideRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
    }
}
