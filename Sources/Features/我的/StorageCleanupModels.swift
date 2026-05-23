import Foundation
import SwiftUI

struct StorageCleanupScanResult {
    let categorySummaries: [StorageCategorySummary]
    let largeFileItems: [StorageLargeFileItem]
    let projectUsages: [ProjectStorageUsage]
}

struct StorageCategorySummary: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let tint: Color
    let bytes: Int
    let count: Int

    var formattedBytes: String {
        QuickNoteAttachmentStorage.formattedFileSize(bytes)
    }
}

struct StorageLargeFileItem: Identifiable {
    let id: String
    let category: StorageFileCategory
    let title: String
    let detail: String
    let projectId: UUID?
    let projectName: String?
    let bytes: Int

    init(
        id: String,
        category: StorageFileCategory,
        title: String,
        detail: String,
        projectId: UUID? = nil,
        projectName: String? = nil,
        bytes: Int
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.projectId = projectId
        self.projectName = projectName
        self.bytes = bytes
    }

    var formattedBytes: String {
        QuickNoteAttachmentStorage.formattedFileSize(bytes)
    }
}

enum StorageFileCategory {
    case photo
    case video
    case drawing
    case ticket
    case backup
    case history

    var displayName: String {
        StorageCleanupSectionCopy.storageFileCategoryDisplayName(self)
    }

    var icon: String {
        StorageCleanupSectionCopy.storageFileCategoryStyle(self).icon
    }

    var tint: Color {
        StorageCleanupSectionCopy.storageFileCategoryStyle(self).tint
    }
}

struct ProjectStorageUsage: Identifiable {
    let projectId: UUID
    let projectName: String
    let photoBytes: Int
    let videoBytes: Int
    let drawingBytes: Int
    let ticketBytes: Int
    let backupEstimatedBytes: Int?

    var id: UUID { projectId }
    var totalBytes: Int { photoBytes + videoBytes + drawingBytes + ticketBytes }
    var formattedTotalBytes: String { QuickNoteAttachmentStorage.formattedFileSize(totalBytes) }
    var formattedBackupEstimatedBytes: String {
        guard let backupEstimatedBytes else { return StorageCleanupSectionCopy.backupEstimateCalculatingText }
        return QuickNoteAttachmentStorage.formattedFileSize(backupEstimatedBytes)
    }
}

struct CleanupImpactSummary {
    struct Item {
        let title: String
        let count: Int
    }

    private var fileCountMap: [String: Int] = [:]
    private var recordCountMap: [String: Int] = [:]
    private var sampleFileNameSet: Set<String> = []

    mutating func addFile(title: String, count: Int) {
        guard count > 0 else { return }
        fileCountMap[title, default: 0] += count
    }

    mutating func addRecord(title: String, count: Int) {
        guard count > 0 else { return }
        recordCountMap[title, default: 0] += count
    }

    mutating func addSampleFileNames<S: Sequence>(_ names: S) where S.Element == String {
        for name in names where !name.isEmpty {
            sampleFileNameSet.insert(name)
        }
    }

    mutating func merge(_ other: CleanupImpactSummary) {
        for (title, count) in other.fileCountMap {
            fileCountMap[title, default: 0] += count
        }
        for (title, count) in other.recordCountMap {
            recordCountMap[title, default: 0] += count
        }
        sampleFileNameSet.formUnion(other.sampleFileNameSet)
    }

    var totalFileCount: Int {
        fileCountMap.values.reduce(0, +)
    }

    var fileItems: [Item] {
        fileCountMap.map { Item(title: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    var recordItems: [Item] {
        recordCountMap.map { Item(title: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    var sampleFileNames: [String] {
        sampleFileNameSet.sorted { lhs, rhs in
            lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }
}

enum ProjectStorageCleanupCategory: String, Identifiable {
    case photos
    case videos
    case drawings
    case tickets
    case all

    var id: String { rawValue }

    var displayName: String {
        StorageCleanupSectionCopy.cleanupCategoryDisplayName(self)
    }

    var resultTitle: String {
        StorageCleanupSectionCopy.cleanupCategoryResultTitle(self)
    }

    var icon: String {
        StorageCleanupSectionCopy.cleanupCategoryStyle(self).icon
    }

    var tint: Color {
        StorageCleanupSectionCopy.cleanupCategoryStyle(self).tint
    }

    var confirmationButtonTitle: String {
        switch self {
        case .all:
            return StorageCleanupSectionCopy.cleanupAllConfirmationButtonTitle
        default:
            return StorageCleanupSectionCopy.cleanupConfirmationButtonTitle(categoryDisplayName: displayName)
        }
    }

    func confirmationMessage(projectName: String) -> String {
        switch self {
        case .photos:
            return StorageCleanupSectionCopy.cleanupPhotosConfirmationMessage(projectName: projectName)
        case .videos:
            return StorageCleanupSectionCopy.cleanupVideosConfirmationMessage(projectName: projectName)
        case .drawings:
            return StorageCleanupSectionCopy.cleanupDrawingsConfirmationMessage(projectName: projectName)
        case .tickets:
            return StorageCleanupSectionCopy.cleanupTicketsConfirmationMessage(projectName: projectName)
        case .all:
            return StorageCleanupSectionCopy.cleanupAllFilesConfirmationMessage(projectName: projectName)
        }
    }
}
