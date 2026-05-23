import Foundation
import SwiftUI

@MainActor
extension StorageCleanupScanner {
    static func buildCategorySummaries(
        store: DataStore,
        cloudBackups: [CloudBackupFile],
        historyBytes: Int,
        photoEntries: [StorageLargeFileItem],
        videoEntries: [StorageLargeFileItem],
        drawingEntries: [StorageLargeFileItem],
        ticketEntries: [StorageLargeFileItem]
    ) -> [StorageCategorySummary] {
        [
            StorageCategorySummary(
                title: String(localized: "照片"),
                icon: "photo.fill",
                tint: .appWarning,
                bytes: photoEntries.reduce(0) { $0 + $1.bytes },
                count: photoEntries.count
            ),
            StorageCategorySummary(
                title: String(localized: "视频"),
                icon: "video.fill",
                tint: .appPhoto,
                bytes: videoEntries.reduce(0) { $0 + $1.bytes },
                count: videoEntries.count
            ),
            StorageCategorySummary(
                title: String(localized: "图纸原件"),
                icon: "doc.viewfinder",
                tint: .appDoc,
                bytes: drawingEntries.reduce(0) { $0 + $1.bytes },
                count: drawingEntries.count
            ),
            StorageCategorySummary(
                title: String(localized: "票据资料"),
                icon: "doc.text.fill",
                tint: .appRisk,
                bytes: ticketEntries.reduce(0) { $0 + $1.bytes },
                count: ticketEntries.count
            ),
            StorageCategorySummary(
                title: String(localized: "备份（iCloud）"),
                icon: "icloud.and.arrow.up.fill",
                tint: .appPrimaryAction,
                bytes: cloudBackups.reduce(0) { $0 + $1.byteSize },
                count: cloudBackups.count
            ),
            StorageCategorySummary(
                title: String(localized: "历史计算"),
                icon: "clock.arrow.circlepath",
                tint: .appSuccess,
                bytes: historyBytes,
                count: store.historyRecords.count
            )
        ]
    }

    static func buildLargeFileItems(
        store: DataStore,
        largeFileThresholdBytes: Int,
        historyBytes: Int,
        photoEntries: [StorageLargeFileItem],
        videoEntries: [StorageLargeFileItem],
        drawingEntries: [StorageLargeFileItem],
        ticketEntries: [StorageLargeFileItem],
        backupEntries: [StorageLargeFileItem]
    ) -> [StorageLargeFileItem] {
        var items = (photoEntries + videoEntries + drawingEntries + ticketEntries + backupEntries)
            .filter { $0.bytes >= largeFileThresholdBytes }
        if historyBytes >= largeFileThresholdBytes {
            items.append(
                StorageLargeFileItem(
                    id: "history-records",
                    category: .history,
                    title: String(localized: "历史计算记录"),
                    detail: String(format: String(localized: "%lld 条"), Int64(store.historyRecords.count)),
                    projectName: nil,
                    bytes: historyBytes
                )
            )
        }
        return items.sorted { lhs, rhs in
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    static func buildProjectUsages(
        store: DataStore,
        projectBackupEstimateByID: [UUID: Int],
        photoEntries: [StorageLargeFileItem],
        videoEntries: [StorageLargeFileItem],
        drawingEntries: [StorageLargeFileItem],
        ticketEntries: [StorageLargeFileItem]
    ) -> [ProjectStorageUsage] {
        store.projects.compactMap { project in
            let projectId = project.id
            let photoBytes = photoEntries
                .filter { $0.projectId == projectId }
                .reduce(0) { $0 + $1.bytes }
            let videoBytes = videoEntries
                .filter { $0.projectId == projectId }
                .reduce(0) { $0 + $1.bytes }
            let drawingBytes = drawingEntries
                .filter { $0.projectId == projectId }
                .reduce(0) { $0 + $1.bytes }
            let ticketBytes = ticketEntries
                .filter { $0.projectId == projectId }
                .reduce(0) { $0 + $1.bytes }
            let total = photoBytes + videoBytes + drawingBytes + ticketBytes
            guard total > 0 else { return nil }
            return ProjectStorageUsage(
                projectId: projectId,
                projectName: project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? String(localized: "未命名项目")
                    : project.name,
                photoBytes: photoBytes,
                videoBytes: videoBytes,
                drawingBytes: drawingBytes,
                ticketBytes: ticketBytes,
                backupEstimatedBytes: projectBackupEstimateByID[projectId]
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalBytes != rhs.totalBytes { return lhs.totalBytes > rhs.totalBytes }
            return lhs.projectName.localizedStandardCompare(rhs.projectName) == .orderedAscending
        }
    }
}
