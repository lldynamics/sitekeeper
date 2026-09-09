import Foundation

extension BackupView {
    func exportBackupZIP() {
        cleanupExportArchiveIfNeeded()
        lastExportSucceeded = false
        clearStatus()
        beginExportTask(currentItem: String(localized: "准备导出"))
        exportTask = Task {
            do {
                let outcome = try await store.withBackupExport {
                    let snapshot = store.makeSnapshot(includePhotoFiles: false)
                    return try await BackupExportCoordinator.exportBackup(
                        snapshot: snapshot,
                        suggestedFileName: "\(AppBrand.exportFilePrefix)_完整备份.zip",
                        progress: { progress in
                            Task { @MainActor in
                                exportProgress = progress
                            }
                        },
                        shouldCancel: { Task.isCancelled }
                    )
                }
                if try await completeUITestRoundTripExportIfNeeded(outcome) { return }
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

    private func completeUITestRoundTripExportIfNeeded(_ outcome: BackupExportOutcome) async throws -> Bool {
        guard let slotURL = uiTestRoundTripSlotURL else { return false }
        defer { ExportFileURLPreparer.cleanup(fileURL: outcome.preparedFileURL) }
        try await stageAndValidateUITestBackup(from: outcome.preparedFileURL, at: slotURL)
        await MainActor.run {
            finalizeExportTask()
            localBackupLastSuccessAt = Date().timeIntervalSince1970
            hasCompletedBackupExportTask = true
            lastExportSucceeded = true
            lastImportSucceeded = false
            setStatus(String(localized: "UI测试备份已生成并验证"))
        }
        return true
    }

    var isUITestRoundTripEnabled: Bool {
#if DEBUG
        let processInfo = ProcessInfo.processInfo
        return processInfo.arguments.contains("-ui-testing")
            && processInfo.environment["UITEST_BACKUP_ROUNDTRIP"] == "1"
            && uiTestRoundTripSlotURL != nil
#else
        false
#endif
    }

    var uiTestRoundTripSlotURL: URL? {
#if DEBUG
        let processInfo = ProcessInfo.processInfo
        guard processInfo.arguments.contains("-ui-testing"),
              processInfo.environment["UITEST_BACKUP_ROUNDTRIP"] == "1",
              let rawSlot = processInfo.environment["UITEST_BACKUP_ROUNDTRIP_SLOT"],
              !rawSlot.isEmpty,
              rawSlot.count <= 80,
              rawSlot.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            return nil
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("sitekeeper-ui-backup-roundtrip", isDirectory: true)
            .appendingPathComponent(rawSlot, isDirectory: true)
            .appendingPathComponent("verified-backup.zip")
#else
        nil
#endif
    }

    var isUITestRoundTripBackupReady: Bool {
        guard let uiTestRoundTripSlotURL else { return false }
        return FileManager.default.fileExists(atPath: uiTestRoundTripSlotURL.path)
    }

    func startUITestRoundTripImport() {
        guard let slotURL = uiTestRoundTripSlotURL,
              FileManager.default.fileExists(atPath: slotURL.path) else {
            setStatus(String(localized: "UI测试备份槽位不可用"))
            return
        }
        startPreviewImport(from: slotURL)
        cleanupUITestRoundTripSlot()
    }

    private func stageAndValidateUITestBackup(from sourceURL: URL, at slotURL: URL) async throws {
        try await FileIOTaskRunner.runWithRelay(
            priority: .userInitiated,
            logContext: .init(
                event: "backup.ui_test.stage_roundtrip",
                source: "BackupView.stageAndValidateUITestBackup",
                category: .zipArchive,
                details: ["slot": slotURL.deletingLastPathComponent().lastPathComponent]
            )
        ) { relay in
            let directoryURL = slotURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: slotURL.path) {
                    try FileManager.default.removeItem(at: slotURL)
                }
                guard !relay.isCancelled(), !Task.isCancelled else {
                    throw BackupArchiveError.cancelled
                }
                try FileManager.default.copyItem(at: sourceURL, to: slotURL)
                _ = try BackupArchiveService.previewBackup(
                    from: slotURL,
                    shouldCancel: { relay.isCancelled() || Task.isCancelled }
                )
                guard FileManager.default.fileExists(atPath: slotURL.path),
                      !relay.isCancelled(),
                      !Task.isCancelled else {
                    throw BackupArchiveError.cancelled
                }
            } catch {
                try? FileManager.default.removeItem(at: directoryURL)
                throw error
            }
        }
    }

    private func cleanupUITestRoundTripSlot() {
        guard let directoryURL = uiTestRoundTripSlotURL?.deletingLastPathComponent() else { return }
        try? FileManager.default.removeItem(at: directoryURL)
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
