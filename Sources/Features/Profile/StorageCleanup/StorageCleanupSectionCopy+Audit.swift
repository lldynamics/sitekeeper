import Foundation

extension StorageCleanupSectionCopy {
    static var auditSummaryRestoreCleanupTrash: String {
        AppLocalization.string("恢复清理回收站")
    }

    static var auditSummaryPermanentlyDeleteCleanupTrash: String {
        AppLocalization.string("永久删除清理回收站")
    }

    static var auditSummaryRestoreQuarantinedFile: String {
        AppLocalization.string("恢复隔离文件")
    }

    static var auditSummaryPermanentlyDeleteQuarantinedFile: String {
        AppLocalization.string("永久删除隔离文件")
    }

    static var auditSummaryCleanupByProject: String {
        AppLocalization.string("按项目清理")
    }

    static func restoredCleanupTrashStatus(_ summary: String) -> String {
        String(format: AppLocalization.string("已从清理回收站恢复：%@。"), summary)
    }

    static func restoreCleanupTrashFailedStatus(_ errorDescription: String) -> String {
        String(format: AppLocalization.string("清理回收站恢复失败：%@"), errorDescription)
    }

    static func permanentlyDeletedCleanupTrashStatus(_ summary: String) -> String {
        String(format: AppLocalization.string("已永久删除清理回收站批次：%@。"), summary)
    }

    static func permanentlyDeleteCleanupTrashFailedStatus(_ errorDescription: String) -> String {
        String(format: AppLocalization.string("永久删除清理回收站失败：%@"), errorDescription)
    }

    static func restoredQuarantinedFileStatus(_ fileName: String) -> String {
        String(format: AppLocalization.string("已从回收站恢复隔离文件：%@。"), fileName)
    }

    static func restoreQuarantinedFileFailedStatus(_ errorDescription: String) -> String {
        String(format: AppLocalization.string("隔离文件恢复失败：%@"), errorDescription)
    }

    static func permanentlyDeletedQuarantinedFileStatus(_ fileName: String) -> String {
        String(format: AppLocalization.string("已永久删除隔离文件：%@。"), fileName)
    }

    static func permanentlyDeleteQuarantinedFileFailedStatus(_ errorDescription: String) -> String {
        String(format: AppLocalization.string("隔离文件永久删除失败：%@"), errorDescription)
    }

    static func projectCleanupAuditDetail(projectName: String, categoryDisplayName: String) -> String {
        String(format: AppLocalization.string("%@ · %@"), projectName, categoryDisplayName)
    }

    static func projectCleanupSummary(projectName: String, categoryResultTitle: String) -> String {
        String(format: AppLocalization.string("%@ · %@"), projectName, categoryResultTitle)
    }

    static func projectFilesMovedToTrashStatus(
        projectName: String,
        categoryResultTitle: String,
        fileCount: Int,
        recoverableDateText: String
    ) -> String {
        String(
            format: AppLocalization.string("已将 %@ 的%@移入清理回收站：%lld 个文件，可恢复至 %@。"),
            projectName,
            categoryResultTitle,
            Int64(fileCount),
            recoverableDateText
        )
    }

    static func cleanupTrashWriteFailedStatus(_ errorDescription: String) -> String {
        String(format: AppLocalization.string("清理回收站写入失败：%@"), errorDescription)
    }

    static func auditDetailWithError(_ baseDetail: String, errorDescription: String) -> String {
        "\(baseDetail) · error=\(errorDescription)"
    }

    static func auditDetailRestoredCleanupBatch(_ summary: String, fileCount: Int) -> String {
        "\(summary) · restored=\(fileCount)"
    }

    static func auditDetailDeletedCleanupBatch(_ summary: String, fileCount: Int) -> String {
        "\(summary) · deleted=\(fileCount)"
    }

    static func auditDetailWithRetention(_ baseDetail: String, fileCount: Int, retentionDays: Int) -> String {
        "\(baseDetail) · trashed=\(fileCount) · retentionDays=\(retentionDays)"
    }
}
