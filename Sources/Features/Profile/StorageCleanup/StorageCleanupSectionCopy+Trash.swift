import Foundation

extension StorageCleanupSectionCopy {
    static var trashRetentionLabel: String {
        AppLocalization.string("回收站保留时间")
    }

    static var trashPolicyHeader: String {
        AppLocalization.string("回收站策略")
    }

    static var trashPolicyFooter: String {
        AppLocalization.string("只影响之后新清理的批次；已有回收站批次仍按原到期时间处理。")
    }

    static func trashPolicyRecoveryHint(deadlineText: String) -> String {
        String(
            format: AppLocalization.string("之后新清理的文件可恢复至 %@。"),
            deadlineText
        )
    }

    static var globalTrashHeader: String {
        AppLocalization.string("全局回收站")
    }

    static var emptyTrashMessage: String {
        AppLocalization.string("暂无可恢复的回收站项目。")
    }

    static var restoreActionTitle: String {
        AppLocalization.string("恢复")
    }

    static var permanentDeleteActionTitle: String {
        AppLocalization.string("永久删除")
    }

    static func globalTrashFooter(retentionDays: Int) -> String {
        String(
            format: AppLocalization.string("照片、图纸、票据、附件删除和项目文件清理都会先进入回收站，当前保留 %lld 天。过期项目会在进入本页时自动永久删除。"),
            Int64(retentionDays)
        )
    }

    static func cleanupBatchFileCount(_ fileCount: Int) -> String {
        String(format: AppLocalization.string("%lld 个文件"), Int64(fileCount))
    }

    static var cleanupBatchLabel: String {
        AppLocalization.string("清理批次")
    }

    static var quarantinedFileLabel: String {
        AppLocalization.string("隔离文件")
    }

    static func recoverableUntil(_ dateText: String) -> String {
        String(
            format: AppLocalization.string("可恢复至 %@"),
            dateText
        )
    }

    static func largeFileHeader(_ count: Int) -> String {
        String(format: AppLocalization.string("大文件列表（%lld）"), Int64(count))
    }

    static var largeFileThresholdLabel: String {
        AppLocalization.string("大文件阈值")
    }

    static var largeFileFooter: String {
        AppLocalization.string("展示照片、视频、图纸原件、备份和历史计算中的高占用项。")
    }

    static var noLargeFilesTitle: String {
        AppLocalization.string("暂无大文件")
    }

    static var noLargeFilesDescription: String {
        AppLocalization.string("当前各类文件都低于阈值。")
    }

    static func quarantineCategoryTitle(_ category: FileQuarantineCategory) -> String {
        switch category {
        case .photoOriginal:
            return AppLocalization.string("照片原文件")
        case .photoThumbnail:
            return AppLocalization.string("照片缩略图")
        case .drawing:
            return AppLocalization.string("图纸原件文件")
        case .drawingSidecar:
            return AppLocalization.string("图纸附属文件")
        case .projectDocument:
            return AppLocalization.string("项目资料文件")
        case .quickNoteAttachment:
            return AppLocalization.string("随手记附件")
        }
    }
}
