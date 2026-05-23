import SwiftUI
import Foundation

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
                let preview = try await FileIOTaskRunner.runWithRelay(
                    priority: .userInitiated,
                    logContext: .init(
                        event: "backup.import.preview",
                        source: "BackupView.startPreviewImportFromPreparedFile",
                        category: .zipArchive,
                        details: ["file_name": copiedURL.lastPathComponent]
                    )
                ) { relay in
                    try BackupArchiveService.previewBackup(
                        from: copiedURL,
                        progress: { progress in
                            Task { @MainActor in
                                importProgress = progress
                            }
                        },
                        shouldCancel: { relay.isCancelled() || Task.isCancelled }
                    )
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

    @MainActor
    func enrichImportPreviewWithLocalImpact(_ preview: BackupImportPreview) -> BackupImportPreview {
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
