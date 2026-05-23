import Foundation
import SwiftUI

extension StorageCleanupSectionCopy {
    static func storageFileCategoryDisplayName(_ category: StorageFileCategory) -> String {
        switch category {
        case .photo:
            return String(localized: "照片")
        case .video:
            return String(localized: "视频")
        case .drawing:
            return String(localized: "图纸原件")
        case .ticket:
            return String(localized: "票据")
        case .backup:
            return String(localized: "备份")
        case .history:
            return String(localized: "历史计算")
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
            return String(localized: "照片")
        case .videos:
            return String(localized: "视频")
        case .drawings:
            return String(localized: "图纸原件")
        case .tickets:
            return String(localized: "票据资料")
        case .all:
            return String(localized: "全部可清理文件")
        }
    }

    static func cleanupCategoryResultTitle(_ category: ProjectStorageCleanupCategory) -> String {
        switch category {
        case .photos:
            return String(localized: "照片")
        case .videos:
            return String(localized: "视频")
        case .drawings:
            return String(localized: "图纸原件")
        case .tickets:
            return String(localized: "票据资料")
        case .all:
            return String(localized: "项目文件")
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
        String(localized: "空间汇总")
    }

    static func summaryItemCount(_ count: Int) -> String {
        String(format: String(localized: "%lld 项"), Int64(count))
    }

    static var projectCleanupHeader: String {
        String(localized: "按项目清理")
    }

    static var noProjectCleanupMessage: String {
        String(localized: "暂无可清理项目文件。")
    }

    static func projectUsage(_ title: String, sizeText: String) -> String {
        String(format: String(localized: "%@ %@"), title, sizeText)
    }

    static var usagePhotoTitle: String {
        String(localized: "照片")
    }

    static var usageVideoTitle: String {
        String(localized: "视频")
    }

    static var usageDrawingTitle: String {
        String(localized: "图纸")
    }

    static var usageTicketTitle: String {
        String(localized: "票据")
    }

    static var usageDrawingOriginalTitle: String {
        String(localized: "图纸原件")
    }

    static var usageTicketDocumentTitle: String {
        String(localized: "票据资料")
    }

    static var usageBackupEstimateTitle: String {
        String(localized: "备份估算")
    }

    static func projectBackupEstimate(_ sizeText: String) -> String {
        String(format: String(localized: "备份估算 %@"), sizeText)
    }

    static var usageSummaryHeader: String {
        String(localized: "占用汇总")
    }

    static var projectTotalUsageTitle: String {
        String(localized: "项目总占用")
    }

    static var cleanupByTypeHeader: String {
        String(localized: "按类型清理")
    }

    static var cleanupByTypeFooter: String {
        String(localized: "分项清理只处理对应文件类型，项目文本、金额、日志正文不会删除。")
    }

    static var cleanupAllProjectFilesTitle: String {
        String(localized: "清理该项目全部可清理文件")
    }

    static var backupSpaceNote: String {
        String(localized: "备份是全局快照，不会按单个项目直接删除；如需释放备份空间，请回到“数据管理 → 备份”处理。")
    }

    static func cleanupCategoryTitle(_ categoryDisplayName: String) -> String {
        String(format: String(localized: "清理%@"), categoryDisplayName)
    }
}
