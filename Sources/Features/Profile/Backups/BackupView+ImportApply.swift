import Foundation

extension BackupView {
    func startApplyingImport() {
        guard let pendingImportFileURL else {
            setStatus(AppLocalization.string("备份源文件已失效，请重新选择导入文件。"))
            showPreview = false
            OperationAuditLog.record(
                action: .import,
                outcome: .failed,
                summary: AppLocalization.string("备份源文件已失效，请重新选择导入文件。"),
                source: "BackupView"
            )
            return
        }
        isOverwriteImportArmed = false
        OperationAuditLog.record(
            action: .import,
            outcome: .started,
            summary: importMode == .overwrite ? AppLocalization.string("覆盖导入") : AppLocalization.string("合并导入"),
            detail: pendingImportFileURL.lastPathComponent,
            source: "BackupView"
        )

        let metadataSnapshot = pendingImportPreview?.snapshot
        let sourceSize = Int64(max(QuickNoteAttachmentStorage.fileSize(at: pendingImportFileURL), 1))

        beginImportTask(
            title: AppLocalization.string("正在应用数据索引"),
            totalBytes: sourceSize,
            currentItem: AppLocalization.string("准备导入")
        )

        importTask = Task {
            var failureStage = BackupImportStage.readingMetadata
            var failureDetail = ""
            do {
                let snapshot: BackupSnapshot
                if let metadataSnapshot {
                    snapshot = metadataSnapshot
                } else {
                    let preview = try await FileIOTaskRunner.runWithRelay(
                        priority: .userInitiated,
                        logContext: .init(
                            event: "backup.import.preview_fallback",
                            source: "BackupView.startApplyingImport",
                            category: .zipArchive,
                            details: ["file_name": pendingImportFileURL.lastPathComponent]
                        )
                    ) { relay in
                        try BackupArchiveService.previewBackup(
                            from: pendingImportFileURL,
                            progress: { progress in
                                Task { @MainActor in
                                    importProgress = progress
                                }
                            },
                            shouldCancel: { relay.isCancelled() || Task.isCancelled }
                        )
                    }
                    snapshot = preview.snapshot
                }
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeImportTask(
                            status: AppLocalization.string("已取消导入，当前数据未变更。"),
                            cleanupPendingFile: true,
                            closePreview: true
                        )
                        OperationAuditLog.record(
                            action: .import,
                            outcome: .cancelled,
                            summary: AppLocalization.string("已取消导入，当前数据未变更。"),
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
                    importProgressTitle = AppLocalization.string("正在恢复原文件")
                    importProgress = BackupImportProgress(
                        completedBytes: 0,
                        totalBytes: sourceSize,
                        currentItem: AppLocalization.string("准备恢复")
                    )
                }

                let restoreTransaction = try await FileIOTaskRunner.runWithRelay(
                    priority: .userInitiated,
                    logContext: .init(
                        event: "backup.import.prepare_restore",
                        source: "BackupView.startApplyingImport",
                        category: .zipArchive,
                        details: ["file_name": pendingImportFileURL.lastPathComponent]
                    )
                ) { relay in
                    try BackupArchiveService.prepareEmbeddedFileRestore(
                        from: pendingImportFileURL,
                        progress: { progress in
                            Task { @MainActor in
                                importProgress = progress
                            }
                        },
                        shouldCancel: { relay.isCancelled() || Task.isCancelled }
                    )
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
                    importProgressTitle = AppLocalization.string("正在应用数据索引")
                }

                failureStage = .committingFiles
                failureDetail = failureStage.auditDetail(
                    fileName: pendingImportFileURL.lastPathComponent,
                    extra: "restore=\(restoreTransaction.counts.totalCount)"
                )
                await MainActor.run {
                    importProgressTitle = AppLocalization.string("正在提交原文件")
                    importProgress = BackupImportProgress(
                        completedBytes: sourceSize,
                        totalBytes: max(sourceSize, 1),
                        currentItem: AppLocalization.string("提交原文件")
                    )
                }

                let restoredCounts = try await BackupImportCoordinator.commitAndPersistImport(
                    restoreTransaction: restoreTransaction,
                    importedSnapshot: snapshot,
                    previousSnapshot: existingSnapshot,
                    importMode: selectedImportMode,
                    store: store,
                    sourceFileName: pendingImportFileURL.lastPathComponent,
                    onPersistingMetadata: {
                        failureStage = .persistingMetadata
                        failureDetail = failureStage.auditDetail(
                            fileName: pendingImportFileURL.lastPathComponent
                        )
                        importProgressTitle = AppLocalization.string("正在写入本地数据")
                        importProgress = BackupImportProgress(
                            completedBytes: sourceSize,
                            totalBytes: max(sourceSize, 1),
                            currentItem: AppLocalization.string("写入数据索引")
                        )
                    }
                )

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
                    showPreview = false
                    lastImportSucceeded = true
                    lastExportSucceeded = false
                    hasSeenBackupGuide = true
                    if restoredCounts.totalCount > 0 {
                        setStatus(String(format: AppLocalization.string("导入完成（恢复 %d 个原文件）"), restoredCounts.totalCount))
                    } else {
                        setStatus(AppLocalization.string("导入完成"))
                    }
                    OperationAuditLog.record(
                        action: .import,
                        outcome: .succeeded,
                        summary: AppLocalization.string("导入完成"),
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
                            status: AppLocalization.string("已取消导入，当前数据未变更。"),
                            cleanupPendingFile: true,
                            closePreview: true
                        )
                        OperationAuditLog.record(
                            action: .import,
                            outcome: .cancelled,
                            summary: AppLocalization.string("已取消导入，当前数据未变更。"),
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
            summary: AppLocalization.string("正在读取 iCloud 备份"),
            detail: "\(file.fileName) · \(file.formattedSize)",
            source: "BackupView"
        )
        beginImportTask(
            title: AppLocalization.string("正在读取 iCloud 备份"),
            totalBytes: Int64(max(file.byteSize, 1)),
            currentItem: AppLocalization.string("准备读取")
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
                            summary: AppLocalization.string("已取消读取 iCloud 备份"),
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
                        summary: AppLocalization.string("正在读取 iCloud 备份"),
                        detail: copiedURL.lastPathComponent,
                        source: "BackupView"
                    )
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeImportTask(
                            status: AppLocalization.string("已取消读取 iCloud 备份"),
                            cleanupPendingFile: true
                        )
                        OperationAuditLog.record(
                            action: .restore,
                            outcome: .cancelled,
                            summary: AppLocalization.string("已取消读取 iCloud 备份"),
                            source: "BackupView"
                        )
                    }
                    return
                }
                await MainActor.run {
                    finalizeImportTask(
                        status: String(format: AppLocalization.string("iCloud 备份读取失败：%@"), error.localizedDescription),
                        cleanupPendingFile: true
                    )
                    OperationAuditLog.record(
                        action: .restore,
                        outcome: .failed,
                        summary: String(format: AppLocalization.string("iCloud 备份读取失败：%@"), error.localizedDescription),
                        source: "BackupView"
                    )
                }
            }
        }
    }
}
