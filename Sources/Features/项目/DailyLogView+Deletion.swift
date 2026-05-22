import SwiftUI

extension DailyLogView {
    func deleteLogs(_ idx: IndexSet) {
        let ids = idx.map { filtered[$0].id }
        deleteLogIds(ids)
    }

    func deleteLogIds(_ ids: [UUID]) {
        let idSet = Set(ids)
        guard !idSet.isEmpty else { return }

        let targets = store.dailyLogs.filter { idSet.contains($0.id) }
        guard !targets.isEmpty else { return }

        let photoFileNames = targets.flatMap(\.allPhotoFileNames)
        let deletion = store.removeDailyLogs(
            ids: idSet,
            audit: DataStoreDeletionAuditContext(
                summary: String(format: String(localized: "删除施工日志 %lld 条"), Int64(targets.count)),
                detail: String(format: String(localized: "关联照片文件 %lld 个"), Int64(photoFileNames.count)),
                source: "DailyLogView"
            ),
            deferredFileCleanup: DataStoreDeferredFileCleanup.photoFiles(
                photoFileNames,
                summary: "dailyLog.photoFiles"
            )
        )
        guard !deletion.isEmpty else { return }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: String(localized: "已删除 %lld 条施工日志"), Int64(deletion.deletedCount)),
            commit: {
                deletion.performDeferredFileCleanup()
                store.scheduleSave()
            },
            undo: {
                store.restoreDailyLogs(from: deletion)
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }
}
