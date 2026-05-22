import SwiftUI
import UIKit

extension DailyLogView {
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
            message: String(localized: "已删除日志照片"),
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
                summary: String(localized: "删除施工日志照片"),
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
                sourceCompressionQuality: 0.82,
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
