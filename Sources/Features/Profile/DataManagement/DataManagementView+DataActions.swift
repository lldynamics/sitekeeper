import SwiftUI

extension DataManagementView {
    func clearCalculationHistoryWithUndo() {
        let count = store.historyRecords.count
        let deletion = store.clearCalculationHistory(
            audit: DataStoreDeletionAuditContext(
                summary: String(format: AppLocalization.string("清空计算历史 %lld 条"), Int64(count)),
                source: "DataManagementView"
            )
        )
        queueHistoryDeletion(
            deletion,
            message: String(format: AppLocalization.string("已清空 %lld 条计算历史"), Int64(deletion.deletedCount))
        )
    }

    func trimCalculationHistoryWithUndo() {
        let count = historyTrimCount
        let deletion = store.enforceCalculationHistoryRetention(
            audit: DataStoreDeletionAuditContext(
                summary: String(format: AppLocalization.string("按保留策略清理计算历史 %lld 条"), Int64(count)),
                source: "DataManagementView"
            )
        )
        queueHistoryDeletion(
            deletion,
            message: String(format: AppLocalization.string("已按策略清理 %lld 条计算历史"), Int64(deletion.deletedCount))
        )
    }

    func queueHistoryDeletion(_ deletion: DataStoreRemovalResult<HistoryRecord>, message: String) {
        guard !deletion.isEmpty else { return }
        undoableDeletion.queue(
            notice: $operationNotice,
            message: message,
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.restoreHistoryRecords(from: deletion)
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    func importSampleDataWithNotice() {
        let summary = AppLocalization.string("清空并导入测试数据")
        let detail = AppLocalization.string("测试数据恢复")
        OperationAuditLog.record(
            action: .import,
            outcome: .started,
            summary: summary,
            detail: detail,
            source: "DataManagementView"
        )

        if store.importSampleData(replacingExisting: true) {
            store.persistenceErrorMessage = nil
            OperationAuditLog.record(
                action: .import,
                outcome: .succeeded,
                summary: summary,
                detail: detail,
                source: "DataManagementView"
            )
            operationNotice = .info(AppLocalization.string("已恢复测试数据"))
        } else {
            let errorDetail = store.persistenceErrorMessage ?? AppLocalization.string("测试数据导入失败")
            OperationAuditLog.record(
                action: .import,
                outcome: .failed,
                summary: summary,
                detail: errorDetail,
                source: "DataManagementView"
            )
            operationNotice = .info(errorDetail)
        }
    }
}
