import SwiftUI
import Foundation

private enum BackupImportStage: String {
    case copyingSourceFile = "copying_source_file"
    case readingPreview = "reading_preview"
    case readingMetadata = "reading_metadata"
    case stagingFiles = "staging_files"
    case applyingMetadata = "applying_metadata"
    case committingFiles = "committing_files"
    case cleaningOverwrittenFiles = "cleaning_overwritten_files"

    var displayName: String {
        switch self {
        case .copyingSourceFile:
            return String(localized: "复制备份文件")
        case .readingPreview:
            return String(localized: "读取备份预览")
        case .readingMetadata:
            return String(localized: "读取数据索引")
        case .stagingFiles:
            return String(localized: "暂存原文件")
        case .applyingMetadata:
            return String(localized: "应用数据索引")
        case .committingFiles:
            return String(localized: "提交原文件")
        case .cleaningOverwrittenFiles:
            return String(localized: "清理旧文件")
        }
    }

    func failureSummary(error: Error) -> String {
        String(
            format: String(localized: "导入失败（%@）：%@"),
            displayName,
            error.localizedDescription
        )
    }

    func auditDetail(fileName: String? = nil, extra: String? = nil) -> String {
        var parts = ["stage=\(rawValue)", "stageName=\(displayName)"]
        if let fileName, !fileName.isEmpty {
            parts.append("file=\(fileName)")
        }
        if let extra, !extra.isEmpty {
            parts.append(extra)
        }
        return parts.joined(separator: ", ")
    }
}

extension BackupView {
    func importPreview(preview: BackupImportPreview) -> some View {
        BackupImportPreviewView(
            preview: preview,
            importMode: $importMode,
            isOverwriteImportArmed: $isOverwriteImportArmed,
            onApplyImport: startApplyingImport,
            onCancel: {
                showPreview = false
                OperationAuditLog.record(
                    action: .import,
                    outcome: .cancelled,
                    summary: String(localized: "取消导入"),
                    source: "BackupView"
                )
                cleanupPendingImportFileIfNeeded()
            }
        )
    }

    func startPreviewImport(from selectedURL: URL) {
        clearStatus()
        OperationAuditLog.record(
            action: .import,
            outcome: .started,
            summary: String(localized: "正在读取备份预览"),
            detail: selectedURL.lastPathComponent,
            source: "BackupView"
        )
        do {
            let copiedURL = try BackupImportCoordinator.copySelectedBackupToSandbox(selectedURL)
            startPreviewImportFromPreparedFile(copiedURL)
        } catch {
            let stage = BackupImportStage.copyingSourceFile
            setStatus(stage.failureSummary(error: error))
            OperationAuditLog.record(
                action: .import,
                outcome: .failed,
                summary: stage.failureSummary(error: error),
                detail: stage.auditDetail(fileName: selectedURL.lastPathComponent),
                source: "BackupView"
            )
            cleanupPendingImportFileIfNeeded()
        }
    }

    func startPreviewImportFromPreparedFile(_ copiedURL: URL) {
        cleanupPendingImportFileIfNeeded()
        pendingImportPreview = nil
        pendingImportFileURL = copiedURL
        isOverwriteImportArmed = false

        beginImportTask(
            title: String(localized: "正在读取备份预览"),
            totalBytes: Int64(max(QuickNoteAttachmentStorage.fileSize(at: copiedURL), 1)),
            currentItem: String(localized: "准备读取")
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
                        OperationAuditLog.record(
                            action: .import,
                            outcome: .cancelled,
                            summary: String(localized: "取消导入"),
                            detail: BackupImportStage.readingPreview.auditDetail(fileName: copiedURL.lastPathComponent),
                            source: "BackupView"
                        )
                    }
                    return
                }
                let enrichedPreview = await MainActor.run {
                    enrichImportPreviewWithLocalImpact(preview)
                }
                await MainActor.run {
                    isImportingBackup = false
                    importTask = nil
                    pendingImportPreview = enrichedPreview
                    showPreview = true
                    let detail = [
                        "incoming=\(enrichedPreview.incomingFiles.totalCount)",
                        "outgoing=\(enrichedPreview.overwrittenLocalFiles.totalCount)",
                        "photo=\(enrichedPreview.photoFileCount)",
                        "drawing=\(enrichedPreview.drawingFileCount)",
                        "document=\(enrichedPreview.documentFileCount)",
                        "attachment=\(enrichedPreview.quickNoteAttachmentFileCount)"
                    ].joined(separator: ", ")
                    OperationAuditLog.record(
                        action: .import,
                        outcome: .succeeded,
                        summary: String(localized: "正在读取备份预览"),
                        detail: BackupImportStage.readingPreview.auditDetail(
                            fileName: copiedURL.lastPathComponent,
                            extra: detail
                        ),
                        source: "BackupView"
                    )
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeImportTask(cleanupPendingFile: true)
                        OperationAuditLog.record(
                            action: .import,
                            outcome: .cancelled,
                            summary: String(localized: "取消导入"),
                            detail: BackupImportStage.readingPreview.auditDetail(fileName: copiedURL.lastPathComponent),
                            source: "BackupView"
                        )
                    }
                    return
                }
                await MainActor.run {
                    isImportingBackup = false
                    importTask = nil
                    let stage = BackupImportStage.readingPreview
                    setStatus(stage.failureSummary(error: error))
                    OperationAuditLog.record(
                        action: .import,
                        outcome: .failed,
                        summary: stage.failureSummary(error: error),
                        detail: stage.auditDetail(fileName: copiedURL.lastPathComponent),
                        source: "BackupView"
                    )
                    cleanupPendingImportFileIfNeeded()
                }
            }
        }
    }

    func startApplyingImport() {
        guard let pendingImportFileURL else {
            setStatus(String(localized: "备份源文件已失效，请重新选择导入文件。"))
            showPreview = false
            OperationAuditLog.record(
                action: .import,
                outcome: .failed,
                summary: String(localized: "备份源文件已失效，请重新选择导入文件。"),
                source: "BackupView"
            )
            return
        }
        isOverwriteImportArmed = false
        OperationAuditLog.record(
            action: .import,
            outcome: .started,
            summary: importMode == .overwrite ? String(localized: "覆盖导入") : String(localized: "合并导入"),
            detail: pendingImportFileURL.lastPathComponent,
            source: "BackupView"
        )

        let metadataSnapshot = pendingImportPreview?.snapshot
        let sourceSize = Int64(max(QuickNoteAttachmentStorage.fileSize(at: pendingImportFileURL), 1))

        beginImportTask(
            title: String(localized: "正在应用数据索引"),
            totalBytes: sourceSize,
            currentItem: String(localized: "准备导入")
        )

        importTask = Task {
            var failureStage = BackupImportStage.readingMetadata
            var failureDetail = ""
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
                        finalizeImportTask(
                            status: String(localized: "已取消导入，当前数据未变更。"),
                            cleanupPendingFile: true,
                            closePreview: true
                        )
                        OperationAuditLog.record(
                            action: .import,
                            outcome: .cancelled,
                            summary: String(localized: "已取消导入，当前数据未变更。"),
                            detail: failureStage.auditDetail(fileName: pendingImportFileURL.lastPathComponent),
                            source: "BackupView"
                        )
                    }
                    return
                }

                let (existingSnapshot, selectedImportMode) = await MainActor.run {
                    (store.makeSnapshot(includePhotoFiles: false), importMode)
                }
                let overwrittenLocalFiles = selectedImportMode == .overwrite
                    ? BackupImportCoordinator.overwrittenLocalFiles(previous: existingSnapshot, imported: snapshot)
                    : BackupFileImpactSummary()

                failureStage = .stagingFiles
                failureDetail = failureStage.auditDetail(
                    fileName: pendingImportFileURL.lastPathComponent,
                    extra: selectedImportMode == .overwrite ? "mode=overwrite" : "mode=merge"
                )
                await MainActor.run {
                    importProgressTitle = String(localized: "正在恢复原文件")
                    importProgress = BackupImportProgress(
                        completedBytes: 0,
                        totalBytes: sourceSize,
                        currentItem: String(localized: "准备恢复")
                    )
                }

                let relay = TaskCancellationRelay()
                let restoreTransaction = try await withTaskCancellationHandler {
                    try await Task.detached(priority: .userInitiated) {
                        try BackupArchiveService.prepareEmbeddedFileRestore(
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
                guard !Task.isCancelled else {
                    restoreTransaction.cancel()
                    throw BackupArchiveError.cancelled
                }

                failureStage = .applyingMetadata
                failureDetail = failureStage.auditDetail(
                    fileName: pendingImportFileURL.lastPathComponent,
                    extra: selectedImportMode == .overwrite ? "mode=overwrite" : "mode=merge"
                )
                await MainActor.run {
                    importProgressTitle = String(localized: "正在应用数据索引")
                    BackupImportCoordinator.applyImportMetadata(snapshot: snapshot, mode: selectedImportMode, store: store)
                }

                failureStage = .committingFiles
                failureDetail = failureStage.auditDetail(
                    fileName: pendingImportFileURL.lastPathComponent,
                    extra: "restore=\(restoreTransaction.counts.totalCount)"
                )
                await MainActor.run {
                    importProgressTitle = String(localized: "正在提交原文件")
                    importProgress = BackupImportProgress(
                        completedBytes: sourceSize,
                        totalBytes: max(sourceSize, 1),
                        currentItem: String(localized: "提交原文件")
                    )
                }

                let restoredCounts: BackupEmbeddedRestoreCounts
                do {
                    restoredCounts = try await Task.detached(priority: .userInitiated) {
                        try restoreTransaction.commit()
                    }.value
                } catch {
                    restoreTransaction.cancel()
                    await MainActor.run {
                        BackupImportCoordinator.applyImportMetadata(snapshot: existingSnapshot, mode: .overwrite, store: store)
                        store.save(includePhotoFiles: false)
                    }
                    throw error
                }

                failureStage = .cleaningOverwrittenFiles
                failureDetail = failureStage.auditDetail(
                    fileName: pendingImportFileURL.lastPathComponent,
                    extra: "remove=\(overwrittenLocalFiles.totalCount)"
                )
                await MainActor.run {
                    if selectedImportMode == .overwrite {
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
                        setStatus(String(format: String(localized: "导入完成（恢复 %d 个原文件）"), restoredCounts.totalCount))
                    } else {
                        setStatus(String(localized: "导入完成"))
                    }
                    OperationAuditLog.record(
                        action: .import,
                        outcome: .succeeded,
                        summary: String(localized: "导入完成"),
                        detail: BackupImportStage.cleaningOverwrittenFiles.auditDetail(
                            fileName: pendingImportFileURL.lastPathComponent,
                            extra: "\(selectedImportMode == .overwrite ? "mode=overwrite" : "mode=merge"), restore=\(restoredCounts.totalCount), remove=\(overwrittenLocalFiles.totalCount)"
                        ),
                        source: "BackupView"
                    )
                    cleanupPendingImportFileIfNeeded()
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeImportTask(
                            status: String(localized: "已取消导入，当前数据未变更。"),
                            cleanupPendingFile: true,
                            closePreview: true
                        )
                        OperationAuditLog.record(
                            action: .import,
                            outcome: .cancelled,
                            summary: String(localized: "已取消导入，当前数据未变更。"),
                            detail: failureStage.auditDetail(fileName: pendingImportFileURL.lastPathComponent),
                            source: "BackupView"
                        )
                    }
                    return
                }
                await MainActor.run {
                    isImportingBackup = false
                    importTask = nil
                    setStatus(failureStage.failureSummary(error: error))
                    OperationAuditLog.record(
                        action: .import,
                        outcome: .failed,
                        summary: failureStage.failureSummary(error: error),
                        detail: failureDetail.isEmpty
                            ? failureStage.auditDetail(fileName: pendingImportFileURL.lastPathComponent)
                            : failureDetail,
                        source: "BackupView"
                    )
                }
            }
        }
    }

    func exportBackupZIP() {
        cleanupExportArchiveIfNeeded()
        lastExportSucceeded = false
        clearStatus()
        beginExportTask(currentItem: String(localized: "准备导出"))
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
                        finalizeExportTask(status: String(localized: "已取消导出"), cleanupExportFile: true)
                    }
                    return
                }
                if let archiveError = error as? BackupArchiveError, case .cancelled = archiveError {
                    await MainActor.run {
                        finalizeExportTask(status: String(localized: "已取消导出"), cleanupExportFile: true)
                    }
                    return
                }
                await MainActor.run {
                    finalizeExportTask(status: String(format: String(localized: "备份生成失败：%@"), error.localizedDescription))
                }
            }
        }
    }

    func restorePendingCloudBackup() {
        guard let file = cloudState.pendingCloudRestore else {
            setCloudStatus(CloudBackupError.backupNotFound.localizedDescription)
            OperationAuditLog.record(
                action: .restore,
                outcome: .failed,
                summary: CloudBackupError.backupNotFound.localizedDescription,
                source: "BackupView"
            )
            return
        }
        cloudState.pendingCloudRestore = nil
        importMode = .merge
        clearAllStatusMessages()
        OperationAuditLog.record(
            action: .restore,
            outcome: .started,
            summary: String(localized: "正在读取 iCloud 备份"),
            detail: "\(file.fileName) · \(file.formattedSize)",
            source: "BackupView"
        )
        beginImportTask(
            title: String(localized: "正在读取 iCloud 备份"),
            totalBytes: Int64(max(file.byteSize, 1)),
            currentItem: String(localized: "准备读取")
        )

        importTask = Task {
            do {
                let copiedURL = try await BackupCloudTaskCoordinator.copyCloudBackupToTemporaryFile(file)
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeImportTask(cleanupPendingFile: true)
                        OperationAuditLog.record(
                            action: .restore,
                            outcome: .cancelled,
                            summary: String(localized: "已取消读取 iCloud 备份"),
                            source: "BackupView"
                        )
                    }
                    return
                }
                await MainActor.run {
                    finalizeImportTask()
                    startPreviewImportFromPreparedFile(copiedURL)
                    OperationAuditLog.record(
                        action: .restore,
                        outcome: .succeeded,
                        summary: String(localized: "正在读取 iCloud 备份"),
                        detail: copiedURL.lastPathComponent,
                        source: "BackupView"
                    )
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeImportTask(
                            status: String(localized: "已取消读取 iCloud 备份"),
                            cleanupPendingFile: true
                        )
                        OperationAuditLog.record(
                            action: .restore,
                            outcome: .cancelled,
                            summary: String(localized: "已取消读取 iCloud 备份"),
                            source: "BackupView"
                        )
                    }
                    return
                }
                await MainActor.run {
                    finalizeImportTask(
                        status: String(format: String(localized: "iCloud 备份读取失败：%@"), error.localizedDescription),
                        cleanupPendingFile: true
                    )
                    OperationAuditLog.record(
                        action: .restore,
                        outcome: .failed,
                        summary: String(format: String(localized: "iCloud 备份读取失败：%@"), error.localizedDescription),
                        source: "BackupView"
                    )
                }
            }
        }
    }

    func injectUITestPreview() {
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
            StorageIssueLog.record(String(
                format: String(localized: "UI 测试预览备份写入失败：%@，%@"),
                tempURL.lastPathComponent,
                error.localizedDescription
            ))
            return
        }

        cleanupPendingImportFileIfNeeded()
        pendingImportFileURL = tempURL
        pendingImportPreview = BackupImportPreview(
            snapshot: snapshot,
            manifest: BackupArchiveManifest(
                schemaVersion: snapshot.schemaVersion,
                appVersion: snapshot.appVersion,
                appBuild: snapshot.appBuild,
                appName: AppBrand.displayName,
                exportedAt: snapshot.backupCreatedAt,
                metadataPath: BackupArchiveService.metadataPath
            ),
            incomingFiles: BackupFileImpactSummary(),
            overwrittenLocalFiles: BackupImportCoordinator.overwrittenLocalFiles(
                previous: store.makeSnapshot(includePhotoFiles: false),
                imported: snapshot
            )
        )
        // UI 测试快捷入口默认使用覆盖模式，便于稳定验证覆盖导入确认流程。
        importMode = .overwrite
        isOverwriteImportArmed = false
        showPreview = false
        Task { @MainActor in
            showPreview = true
        }
    }

    func cleanupExportArchiveIfNeeded() {
        guard let exportFileURL else { return }
        ExportFileURLPreparer.cleanup(fileURL: exportFileURL)
        self.exportFileURL = nil
    }

    func cleanupPendingImportFileIfNeeded() {
        guard let pendingImportFileURL else { return }
        do {
            _ = try FileOps.removeIfExists(
                at: pendingImportFileURL,
                context: .init(
                    event: "backup_view.cleanup_pending_import_file",
                    category: .fileStorage,
                    source: "BackupView.cleanupPendingImportFileIfNeeded"
                )
            )
        } catch {
            StorageIssueLog.recordEvent(
                "backup_view.cleanup_pending_import_file_failed",
                category: .fileStorage,
                details: ["file": pendingImportFileURL.lastPathComponent],
                error: error
            )
        }
        self.pendingImportFileURL = nil
        self.pendingImportPreview = nil
    }

    @MainActor
    private func enrichImportPreviewWithLocalImpact(_ preview: BackupImportPreview) -> BackupImportPreview {
        let existingSnapshot = store.makeSnapshot(includePhotoFiles: false)
        return BackupImportPreview(
            snapshot: preview.snapshot,
            manifest: preview.manifest,
            incomingFiles: preview.incomingFiles,
            overwrittenLocalFiles: BackupImportCoordinator.overwrittenLocalFiles(
                previous: existingSnapshot,
                imported: preview.snapshot
            )
        )
    }
}
