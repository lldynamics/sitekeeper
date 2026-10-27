import Foundation
import SwiftUI

extension StorageCleanupSectionCopy {
    static func storageFileCategoryDisplayName(_ category: StorageFileCategory) -> String {
        switch category {
        case .photo:
            return AppLocalization.string("照片")
        case .video:
            return AppLocalization.string("视频")
        case .drawing:
            return AppLocalization.string("图纸原件")
        case .ticket:
            return AppLocalization.string("票据")
        case .backup:
            return AppLocalization.string("备份")
        case .history:
            return AppLocalization.string("历史计算")
        }
    }

    static func storageFileCategoryStyle(_ category: StorageFileCategory) -> StorageCleanupCategoryStyle {
        switch category {
        case .photo:
            return StorageCleanupCategoryStyle(icon: "photo.fill", tint: .appWarning)
        case .video:
            return StorageCleanupCategoryStyle(icon: "video.fill", tint: .appPhoto)
        case .drawing:
            return StorageCleanupCategoryStyle(icon: "doc.viewfinder", tint: .appDoc)
        case .ticket:
            return StorageCleanupCategoryStyle(icon: "doc.text.fill", tint: .appRisk)
        case .backup:
            return StorageCleanupCategoryStyle(icon: "externaldrive.fill", tint: .appPrimaryAction)
        case .history:
            return StorageCleanupCategoryStyle(icon: "clock.arrow.circlepath", tint: .appSuccess)
        }
    }

    static func cleanupCategoryDisplayName(_ category: ProjectStorageCleanupCategory) -> String {
        switch category {
        case .photos:
            return AppLocalization.string("照片")
        case .videos:
            return AppLocalization.string("视频")
        case .drawings:
            return AppLocalization.string("图纸原件")
        case .tickets:
            return AppLocalization.string("票据资料")
        case .all:
            return AppLocalization.string("全部可清理文件")
        }
    }

    static func cleanupCategoryResultTitle(_ category: ProjectStorageCleanupCategory) -> String {
        switch category {
        case .photos:
            return AppLocalization.string("照片")
        case .videos:
            return AppLocalization.string("视频")
        case .drawings:
            return AppLocalization.string("图纸原件")
        case .tickets:
            return AppLocalization.string("票据资料")
        case .all:
            return AppLocalization.string("项目文件")
        }
    }

    static func cleanupCategoryStyle(_ category: ProjectStorageCleanupCategory) -> StorageCleanupCategoryStyle {
        switch category {
        case .photos:
            return StorageCleanupCategoryStyle(icon: "photo.fill", tint: .appWarning)
        case .videos:
            return StorageCleanupCategoryStyle(icon: "video.fill", tint: .appPhoto)
        case .drawings:
            return StorageCleanupCategoryStyle(icon: "doc.viewfinder", tint: .appDoc)
        case .tickets:
            return StorageCleanupCategoryStyle(icon: "doc.text.fill", tint: .appRisk)
        case .all:
            return StorageCleanupCategoryStyle(icon: "trash", tint: .red)
        }
    }

    static var storageSummaryHeader: String {
        AppLocalization.string("空间汇总")
    }

    static func summaryItemCount(_ count: Int) -> String {
        String(format: AppLocalization.string("%lld 项"), Int64(count))
    }

    static var projectCleanupHeader: String {
        AppLocalization.string("按项目清理")
    }

    static var noProjectCleanupMessage: String {
        AppLocalization.string("暂无可清理项目文件。")
    }

    static func projectUsage(_ title: String, sizeText: String) -> String {
        String(format: AppLocalization.string("%@ %@"), title, sizeText)
    }

    static var usagePhotoTitle: String {
        AppLocalization.string("照片")
    }

    static var usageVideoTitle: String {
        AppLocalization.string("视频")
    }

    static var usageDrawingTitle: String {
        AppLocalization.string("图纸")
    }

    static var usageTicketTitle: String {
        AppLocalization.string("票据")
    }

    static var usageDrawingOriginalTitle: String {
        AppLocalization.string("图纸原件")
    }

    static var usageTicketDocumentTitle: String {
        AppLocalization.string("票据资料")
    }

    static var usageBackupEstimateTitle: String {
        AppLocalization.string("备份估算")
    }

    static func projectBackupEstimate(_ sizeText: String) -> String {
        String(format: AppLocalization.string("备份估算 %@"), sizeText)
    }

    static var usageSummaryHeader: String {
        AppLocalization.string("占用汇总")
    }

    static var projectTotalUsageTitle: String {
        AppLocalization.string("项目总占用")
    }

    static var cleanupByTypeHeader: String {
        AppLocalization.string("按类型清理")
    }

    static var cleanupByTypeFooter: String {
        AppLocalization.string("分项清理只处理对应文件类型，项目文本、金额、日志正文不会删除。")
    }

    static var cleanupAllProjectFilesTitle: String {
        AppLocalization.string("清理该项目全部可清理文件")
    }

    static var backupSpaceNote: String {
        AppLocalization.string("备份是全局快照，不会按单个项目直接删除；如需释放备份空间，请回到“数据管理 → 备份”处理。")
    }

    static func cleanupCategoryTitle(_ categoryDisplayName: String) -> String {
        String(format: AppLocalization.string("清理%@"), categoryDisplayName)
    }
}
