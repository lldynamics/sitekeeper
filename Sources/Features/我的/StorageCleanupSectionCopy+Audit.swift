import Foundation

extension StorageCleanupSectionCopy {
    static var auditSummaryRestoreCleanupTrash: String {
        String(localized: "恢复清理回收站")
    }

    static var auditSummaryPermanentlyDeleteCleanupTrash: String {
        String(localized: "永久删除清理回收站")
    }

    static var auditSummaryRestoreQuarantinedFile: String {
        String(localized: "恢复隔离文件")
    }

    static var auditSummaryPermanentlyDeleteQuarantinedFile: String {
        String(localized: "永久删除隔离文件")
    }

    static var auditSummaryCleanupByProject: String {
        String(localized: "按项目清理")
    }

    static func restoredCleanupTrashStatus(_ summary: String) -> String {
        String(format: String(localized: "已从清理回收站恢复：%@。"), summary)
    }

    static func restoreCleanupTrashFailedStatus(_ errorDescription: String) -> String {
        String(format: String(localized: "清理回收站恢复失败：%@"), errorDescription)
    }

    static func permanentlyDeletedCleanupTrashStatus(_ summary: String) -> String {
        String(format: String(localized: "已永久删除清理回收站批次：%@。"), summary)
    }

    static func permanentlyDeleteCleanupTrashFailedStatus(_ errorDescription: String) -> String {
        String(format: String(localized: "永久删除清理回收站失败：%@"), errorDescription)
    }

    static func restoredQuarantinedFileStatus(_ fileName: String) -> String {
        String(format: String(localized: "已从回收站恢复隔离文件：%@。"), fileName)
    }

    static func restoreQuarantinedFileFailedStatus(_ errorDescription: String) -> String {
        String(format: String(localized: "隔离文件恢复失败：%@"), errorDescription)
    }

    static func permanentlyDeletedQuarantinedFileStatus(_ fileName: String) -> String {
        String(format: String(localized: "已永久删除隔离文件：%@。"), fileName)
    }

    static func permanentlyDeleteQuarantinedFileFailedStatus(_ errorDescription: String) -> String {
        String(format: String(localized: "隔离文件永久删除失败：%@"), errorDescription)
    }

    static func projectCleanupAuditDetail(projectName: String, categoryDisplayName: String) -> String {
        String(format: String(localized: "%@ · %@"), projectName, categoryDisplayName)
    }

    static func projectCleanupSummary(projectName: String, categoryResultTitle: String) -> String {
        String(format: String(localized: "%@ · %@"), projectName, categoryResultTitle)
    }

    static func projectFilesMovedToTrashStatus(
        projectName: String,
        categoryResultTitle: String,
        fileCount: Int,
        recoverableDateText: String
    ) -> String {
        String(
            format: String(localized: "已将 %@ 的%@移入清理回收站：%lld 个文件，可恢复至 %@。"),
            projectName,
            categoryResultTitle,
            Int64(fileCount),
            recoverableDateText
        )
    }

    static func cleanupTrashWriteFailedStatus(_ errorDescription: String) -> String {
        String(format: String(localized: "清理回收站写入失败：%@"), errorDescription)
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
