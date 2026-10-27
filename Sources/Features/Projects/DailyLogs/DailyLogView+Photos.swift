import SwiftUI
import PhotosUI
import UIKit

extension DailyLogView {
    func importSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }

        photoImportTask?.cancel()
        let token = photoImportSession.beginImport()
        let remainingSlots = max(6 - composer.photoDrafts.count, 0)
        photoImportTask = Task { @MainActor in
            var drafts: [PhotoDraft] = []
            for item in items.prefix(remainingSlots) {
                guard !Task.isCancelled else { return }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    guard !Task.isCancelled else { return }
                    if let normalizedData = ImageDownsampleService.downsampledJPEGData(
                        data,
                        maxPixelSize: 1600,
                        compressionQuality: 0.8
                    ) {
                        drafts.append(PhotoDraft(data: normalizedData))
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    StorageIssueLog.recordEvent(
                        "daily_log.photo_import_failed",
                        category: .fileStorage,
                        details: [
                            "source": "DailyLogView.composeLogForm.photoPicker"
                        ],
                        error: error
                    )
                }
            }

            guard !Task.isCancelled, photoImportSession.accepts(token) else { return }
            let availableSlots = max(6 - composer.photoDrafts.count, 0)
            composer.photoDrafts.append(contentsOf: drafts.prefix(availableSlots))
            composer.selectedPhotos = []
            photoImportSession.finishImport(token)
            photoImportTask = nil
        }
    }

    func cancelPhotoImportAndResetSession() {
        photoImportTask?.cancel()
        photoImportTask = nil
        photoImportSession.reset()
    }

    func updatePhoto(context: SelectedPhotoContext, note: String, tag: PhotoTag) {
        guard store.updateDailyLogPhoto(
            logId: context.logId,
            photoId: context.photoId,
            legacyFileName: context.legacyFileName,
            note: note,
            tag: tag
        ) else { return }
        store.scheduleSave()
    }

    func deletePhoto(context: SelectedPhotoContext) {
        let snapshot = store.dailyLogs
        guard let deletedFileName = store.removeDailyLogPhoto(
            logId: context.logId,
            photoId: context.photoId,
            legacyFileName: context.legacyFileName
        ) else { return }
        let deferredCleanup = DataStoreDeferredFileCleanup.photoFiles(
            [deletedFileName],
            summary: "dailyLog.photoFiles.single"
        )
        undoableDeletion.queue(
            notice: $operationNotice,
            message: AppLocalization.string("已删除日志照片"),
            commit: {
                deferredCleanup?.perform()
                store.scheduleSave()
            },
            undo: {
                store.replaceDailyLogs(UndoableDeletionCoordinator.restoringItems(
                    snapshot: snapshot,
                    current: store.dailyLogs,
                    deletedIDs: Set([context.logId])
                ))
                store.scheduleSave()
            },
            audit: UndoableDeletionAuditContext(
                summary: AppLocalization.string("删除施工日志照片"),
                detail: deletedFileName,
                source: "DailyLogView"
            )
        )
    }

    func appendCameraPhoto(_ image: UIImage, capturedAt: Date) {
        guard composer.photoDrafts.count < 6,
              let normalizedData = ImageDownsampleService.downsampledJPEGData(
                image,
                maxPixelSize: 1600,
                compressionQuality: 0.8
              ) else { return }
        composer.photoDrafts.append(
            PhotoDraft(
                data: normalizedData,
                note: logWatermarkPhotoNote(capturedAt: capturedAt),
                tag: composer.cameraPhotoTag
            )
        )
    }
}

extension DailyLogView {
    func handleExportCompletion(_ result: Result<URL, Error>) {
        let outcome = ExportCompletionHandler.evaluate(result, source: "DailyLogView.photoWall")
        operationNotice = ExportCompletionHandler.notice(for: outcome) {
            guard exportPayload != nil else { return }
            showExporter = true
        }
    }

    func filteredPhotoWallItems() -> [PhotoWallItem] {
        let allItems = filtered.flatMap { log in
            log.photoAttachments.map { PhotoWallItem(logId: log.id, logDate: log.date, projectId: log.projectId, photo: $0) }
        }
        guard let photoTagFilter else { return allItems }
        return allItems.filter { $0.photo.tag == photoTagFilter }
    }

    func photoSelectionKey(_ item: PhotoWallItem) -> String {
        "\(item.logId.uuidString)-\(item.photo.fileName)"
    }

    func togglePhotoSelection(_ item: PhotoWallItem) {
        let key = photoSelectionKey(item)
        if selectedPhotoKeys.contains(key) {
            selectedPhotoKeys.remove(key)
        } else {
            selectedPhotoKeys.insert(key)
        }
    }

    func applyBatchTagToSelectedPhotos() {
        guard !selectedPhotoKeys.isEmpty else { return }
        var dailyLogs = store.dailyLogs
        for logIndex in dailyLogs.indices {
            for photoIndex in dailyLogs[logIndex].photos.indices {
                let photo = dailyLogs[logIndex].photos[photoIndex]
                let key = "\(dailyLogs[logIndex].id.uuidString)-\(photo.fileName)"
                if selectedPhotoKeys.contains(key) {
                    dailyLogs[logIndex].photos[photoIndex].tag = batchPhotoTag
                }
            }
            if let legacy = dailyLogs[logIndex].photoFileName {
                let key = "\(dailyLogs[logIndex].id.uuidString)-\(legacy)"
                if selectedPhotoKeys.contains(key) {
                    if let idx = dailyLogs[logIndex].photos.firstIndex(where: { $0.fileName == legacy }) {
                        dailyLogs[logIndex].photos[idx].tag = batchPhotoTag
                    } else {
                        dailyLogs[logIndex].photos.append(LogPhoto(fileName: legacy, tag: batchPhotoTag))
                    }
                }
            }
        }
        store.replaceDailyLogs(dailyLogs)
        store.scheduleSave()
        selectedPhotoKeys.removeAll()
    }

    func hasRectificationPair(logId: UUID) -> Bool {
        guard let log = store.dailyLogs.first(where: { $0.id == logId }) else { return false }
        let tags = Set(log.photoAttachments.map(\.tag))
        return tags.contains(.rectificationBefore) && tags.contains(.rectificationAfter)
    }

    func exportPhotoWallPDF(items: [PhotoWallItem]) {
        let projectName: String
        if let filterProjectId, let project = store.projects.first(where: { $0.id == filterProjectId }) {
            projectName = project.name
        } else {
            projectName = AppLocalization.string("全部项目")
        }
        let payloads = items.map { item in
            ReportPhotoItem(
                date: item.logDate,
                projectName: item.projectId.flatMap { pid in store.projects.first(where: { $0.id == pid })?.name } ?? AppLocalization.string("未归属"),
                tag: item.photo.tag.displayName,
                note: item.photo.note,
                fileName: item.photo.fileName
            )
        }
        photoWallExportTask?.cancel()
        photoWallExportTask = Task {
            let data = await ReportBuilder.makePhotoWallPDFAsync(
                title: String(format: AppLocalization.string("%@-现场照片页"), projectName),
                items: payloads
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                exportPayload = ExportPayload(
                    data: data,
                    contentType: .pdf,
                    defaultFilename: String(format: AppLocalization.string("%@_现场照片页.pdf"), projectName)
                )
                showExporter = true
                photoWallExportTask = nil
            }
        }
    }
}
