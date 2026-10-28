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
            do {
                let result = try await BackupImportWorkflow.run(
                    sourceURL: pendingImportFileURL,
                    preparedMetadata: metadataSnapshot,
                    operations: LiveBackupImportWorkflowOperations(store: store, selectedImportMode: { importMode }),
                    onEvent: { event in
                        presentImportWorkflowEvent(event, sourceSize: sourceSize)
                    }
                )
                finishApplyingImport(result, sourceURL: pendingImportFileURL)
            } catch {
                presentApplyingImportFailure(error, sourceURL: pendingImportFileURL)
            }
        }
    }

    private func finishApplyingImport(_ result: BackupImportWorkflowResult, sourceURL: URL) {
        isImportingBackup = false
        importTask = nil
        showPreview = false
        lastImportSucceeded = true
        lastExportSucceeded = false
        hasSeenBackupGuide = true
        if result.restoredFileCount > 0 {
            setStatus(String(format: AppLocalization.string("导入完成（恢复 %d 个原文件）"), result.restoredFileCount))
        } else {
            setStatus(AppLocalization.string("导入完成"))
        }
        OperationAuditLog.record(
            action: .import,
            outcome: .succeeded,
            summary: AppLocalization.string("导入完成"),
            detail: BackupImportStage.cleaningOverwrittenFiles.auditDetail(
                fileName: sourceURL.lastPathComponent,
                extra: "mode=\(result.mode.rawValue), restore=\(result.restoredFileCount), remove=\(result.overwrittenFileCount)"
            ),
            source: "BackupView"
        )
        cleanupPendingImportFileIfNeeded()
    }

    private func presentApplyingImportFailure(_ error: Error, sourceURL: URL) {
        let failure = error as? BackupImportWorkflowFailure
        let stage = failure?.phase.importStage ?? .readingMetadata
        if failure?.cancelledBeforeCommit == true {
            finalizeImportTask(
                status: AppLocalization.string("已取消导入，当前数据未变更。"),
                cleanupPendingFile: true,
                closePreview: true
            )
            OperationAuditLog.record(
                action: .import,
                outcome: .cancelled,
                summary: AppLocalization.string("已取消导入，当前数据未变更。"),
                detail: stage.auditDetail(fileName: sourceURL.lastPathComponent),
                source: "BackupView"
            )
            return
        }
        let underlyingError = failure?.underlyingError ?? error
        isImportingBackup = false
        importTask = nil
        setStatus(stage.failureSummary(error: underlyingError))
        OperationAuditLog.record(
            action: .import,
            outcome: .failed,
            summary: stage.failureSummary(error: underlyingError),
            detail: stage.auditDetail(
                fileName: sourceURL.lastPathComponent,
                extra: failure?.auditExtra
            ),
            source: "BackupView"
        )
    }

    private func presentImportWorkflowEvent(_ event: BackupImportWorkflowEvent, sourceSize: Int64) {
        switch event {
        case let .progress(_, progress):
            importProgress = BackupImportProgress(
                completedBytes: progress.completedBytes,
                totalBytes: progress.totalBytes,
                currentItem: progress.currentItem
            )
        case let .phase(phase):
            switch phase {
            case .readingMetadata, .cleaningOverwrittenFiles:
                break
            case .stagingFiles:
                importProgressTitle = AppLocalization.string("正在恢复原文件")
                importProgress = BackupImportProgress(
                    completedBytes: 0,
                    totalBytes: sourceSize,
                    currentItem: AppLocalization.string("准备恢复")
                )
            case .applyingMetadata:
                importProgressTitle = AppLocalization.string("正在应用数据索引")
            case .committingFiles:
                importProgressTitle = AppLocalization.string("正在提交原文件")
                importProgress = BackupImportProgress(
                    completedBytes: sourceSize,
                    totalBytes: max(sourceSize, 1),
                    currentItem: AppLocalization.string("提交原文件")
                )
            case .persistingMetadata:
                importProgressTitle = AppLocalization.string("正在写入本地数据")
                importProgress = BackupImportProgress(
                    completedBytes: sourceSize,
                    totalBytes: max(sourceSize, 1),
                    currentItem: AppLocalization.string("写入数据索引")
                )
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
