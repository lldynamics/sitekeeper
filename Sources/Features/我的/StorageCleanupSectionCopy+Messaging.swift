import Foundation

extension StorageCleanupSectionCopy {
    static var centerNavigationTitle: String {
        String(localized: "存储清理中心")
    }

    static func cloudBackupReadFailed(_ errorDescription: String) -> String {
        String(format: String(localized: "云备份读取失败：%@"), errorDescription)
    }

    static var cleanupProjectFilesAlertTitle: String {
        String(localized: "清理项目文件？")
    }

    static var cancelActionTitle: String {
        String(localized: "取消")
    }

    static var cleanupAllConfirmationButtonTitle: String {
        String(localized: "清理全部")
    }

    static func cleanupConfirmationButtonTitle(categoryDisplayName: String) -> String {
        String(format: String(localized: "清理%@"), categoryDisplayName)
    }

    static func cleanupPhotosConfirmationMessage(projectName: String) -> String {
        String(
            format: String(localized: "将清理 %@ 日志和待办整改中的照片原文件，并断开照片关联。文本记录会保留。"),
            projectName
        )
    }

    static func cleanupVideosConfirmationMessage(projectName: String) -> String {
        String(
            format: String(localized: "将清理 %@ 随手记视频和资料中的视频原文件，并断开视频关联。"),
            projectName
        )
    }

    static func cleanupDrawingsConfirmationMessage(projectName: String) -> String {
        String(
            format: String(localized: "将清理 %@ 的图纸原件和图纸索引。"),
            projectName
        )
    }

    static func cleanupTicketsConfirmationMessage(projectName: String) -> String {
        String(
            format: String(localized: "将清理 %@ 的发票、收据和付款申请资料原文件，并断开财务/仓库关联。"),
            projectName
        )
    }

    static func cleanupAllFilesConfirmationMessage(projectName: String) -> String {
        String(
            format: String(localized: "将清理 %@ 的照片、视频、图纸原件和票据资料原文件，保留其他文本记录。"),
            projectName
        )
    }

    static func largeFileRuleSuggestion(photo: String, video: String, ticket: String) -> String {
        String(
            format: String(localized: "建议规则：照片≥%@、视频≥%@、票据资料≥%@ 时优先检查。"),
            photo,
            video,
            ticket
        )
    }

    static func cleanupConfirmationDeletedFileCount(_ count: Int) -> String {
        String(format: String(localized: "预计删除文件 %lld 个："), Int64(count))
    }

    static func cleanupConfirmationFileLine(title: String, count: Int) -> String {
        String(format: String(localized: "- %@ %lld 个"), title, Int64(count))
    }

    static var cleanupConfirmationNoFileDeletion: String {
        String(localized: "预计删除文件 0 个。")
    }

    static var cleanupConfirmationAffectedRecordsHeader: String {
        String(localized: "预计影响记录：")
    }

    static var cleanupConfirmationNoRecordChange: String {
        String(localized: "- 无关联记录变更")
    }

    static func cleanupConfirmationRecordLine(title: String, count: Int) -> String {
        String(format: String(localized: "- %@ %lld 条"), title, Int64(count))
    }

    static var cleanupConfirmationSampleSeparator: String {
        String(localized: "、")
    }

    static func cleanupConfirmationSampleFiles(_ fileNames: String) -> String {
        String(format: String(localized: "示例文件：%@"), fileNames)
    }

    static func cleanupConfirmationRecoverableHint(dateText: String, retentionDays: Int) -> String {
        String(
            format: String(localized: "清理后文件将进入回收站，可恢复至 %@（%lld 天内）。"),
            dateText,
            Int64(retentionDays)
        )
    }

    static var backupReminderNoBackup: String {
        String(localized: "最近备份：未检测到本机或云备份，建议先执行备份后再清理。")
    }

    static func backupReminderExpired(dateText: String, daysSinceBackup: Int) -> String {
        String(
            format: String(localized: "最近备份：%@（%lld 天前），建议先备份后再清理。"),
            dateText,
            Int64(daysSinceBackup)
        )
    }

    static func backupReminderRecent(dateText: String) -> String {
        String(format: String(localized: "最近备份：%@。"), dateText)
    }

    static var backupEstimateCalculatingText: String {
        String(localized: "计算中…")
    }
}
