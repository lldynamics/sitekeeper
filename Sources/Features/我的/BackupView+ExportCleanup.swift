import Foundation

extension BackupView {
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

        let archive: BackupArchive
        do {
            archive = try BackupArchiveService.makeArchive(from: snapshot)
        } catch {
            StorageIssueLog.recordEvent(
                "backup_view.ui_test_preview_archive_failed",
                category: .zipArchive,
                details: [
                    "source": "BackupViewExportCleanup.injectUITestPreview"
                ],
                error: error
            )
            return
        }

        cleanupPendingImportFileIfNeeded()
        pendingImportFileURL = archive.fileURL
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
}
