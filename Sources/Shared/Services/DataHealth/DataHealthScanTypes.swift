import Foundation

enum DataHealthScanReason: String, Codable, Hashable, Sendable {
    case startup
    case scheduled
    case dataChanged
    case manual
}

struct DataHealthScanFileSnapshot: Codable, Equatable, Sendable {
    let missingPhotoFileNames: [String]
    let missingDocumentFileNames: [String]
    let missingQuickNoteAttachmentFileNames: [String]
    let orphanPhotoFileNames: [String]
    let orphanDrawingFileNames: [String]
    let orphanDocumentFileNames: [String]
    let orphanQuickNoteAttachmentFileNames: [String]
}

struct DataHealthStorageUsageSnapshot: Codable, Equatable, Sendable {
    let photoStorageBytes: Int
    let projectDocumentBytes: Int
    let projectDrawingBytes: Int
    let quickNoteAttachmentBytes: Int
    let photoThumbnailCacheBytes: Int
    let quickNoteThumbnailCacheBytes: Int
    let cloudBackupBytes: Int
    let historyRecordBytes: Int

    var mediaThumbnailCacheBytes: Int {
        photoThumbnailCacheBytes + quickNoteThumbnailCacheBytes
    }

    var projectAssetBytes: Int {
        projectDocumentBytes + projectDrawingBytes + quickNoteAttachmentBytes
    }

    var totalStorageBytes: Int {
        photoStorageBytes
            + projectAssetBytes
            + mediaThumbnailCacheBytes
            + cloudBackupBytes
            + historyRecordBytes
    }

    // Backward-compatible aliases used by data health views.
    var photoBytes: Int { photoStorageBytes }
    var totalBytes: Int { totalStorageBytes }
}

struct DataHealthScanSnapshot: Codable, Equatable, Sendable {
    let scannedAt: Date
    let reason: DataHealthScanReason
    let missingPhotoFileNames: [String]
    let missingDocumentFileNames: [String]
    let missingQuickNoteAttachmentFileNames: [String]
    let orphanPhotoFileNames: [String]
    let orphanDrawingFileNames: [String]
    let orphanDocumentFileNames: [String]
    let orphanQuickNoteAttachmentFileNames: [String]
    let storageIssues: [String]
    let storageUsage: DataHealthStorageUsageSnapshot
    let widgetHealth: WidgetDataHealthSnapshot

    init(
        scannedAt: Date,
        reason: DataHealthScanReason,
        missingPhotoFileNames: [String],
        missingDocumentFileNames: [String],
        missingQuickNoteAttachmentFileNames: [String],
        orphanPhotoFileNames: [String],
        orphanDrawingFileNames: [String],
        orphanDocumentFileNames: [String],
        orphanQuickNoteAttachmentFileNames: [String],
        storageIssues: [String],
        storageUsage: DataHealthStorageUsageSnapshot,
        widgetHealth: WidgetDataHealthSnapshot
    ) {
        self.scannedAt = scannedAt
        self.reason = reason
        self.missingPhotoFileNames = missingPhotoFileNames
        self.missingDocumentFileNames = missingDocumentFileNames
        self.missingQuickNoteAttachmentFileNames = missingQuickNoteAttachmentFileNames
        self.orphanPhotoFileNames = orphanPhotoFileNames
        self.orphanDrawingFileNames = orphanDrawingFileNames
        self.orphanDocumentFileNames = orphanDocumentFileNames
        self.orphanQuickNoteAttachmentFileNames = orphanQuickNoteAttachmentFileNames
        self.storageIssues = storageIssues
        self.storageUsage = storageUsage
        self.widgetHealth = widgetHealth
    }

    init(
        summary: DataHealthScanSummary,
        fallbackStorageUsage: DataHealthStorageUsageSnapshot?,
        fallbackWidgetHealth: WidgetDataHealthSnapshot?
    ) {
        scannedAt = summary.scannedAt
        reason = summary.reason
        missingPhotoFileNames = summary.fileSnapshot.missingPhotoFileNames
        missingDocumentFileNames = summary.fileSnapshot.missingDocumentFileNames
        missingQuickNoteAttachmentFileNames = summary.fileSnapshot.missingQuickNoteAttachmentFileNames
        orphanPhotoFileNames = summary.fileSnapshot.orphanPhotoFileNames
        orphanDrawingFileNames = summary.fileSnapshot.orphanDrawingFileNames
        orphanDocumentFileNames = summary.fileSnapshot.orphanDocumentFileNames
        orphanQuickNoteAttachmentFileNames = summary.fileSnapshot.orphanQuickNoteAttachmentFileNames
        storageIssues = summary.storageIssueEntries
        storageUsage = summary.storageUsage ?? fallbackStorageUsage ?? .zero
        widgetHealth = summary.widgetHealth ?? fallbackWidgetHealth ?? WidgetDataHealthSnapshot(
            appGroupReadable: false,
            lastUpdatedAt: nil,
            projectCount: 0,
            pendingTodos: 0
        )
    }
}

extension DataHealthStorageUsageSnapshot {
    static let zero = DataHealthStorageUsageSnapshot(
        photoStorageBytes: 0,
        projectDocumentBytes: 0,
        projectDrawingBytes: 0,
        quickNoteAttachmentBytes: 0,
        photoThumbnailCacheBytes: 0,
        quickNoteThumbnailCacheBytes: 0,
        cloudBackupBytes: 0,
        historyRecordBytes: 0
    )
}

struct DataHealthScanSummary: Equatable, Sendable {
    let scannedAt: Date
    let reason: DataHealthScanReason
    let missingPhotoFiles: Int
    let missingDocumentFiles: Int
    let missingQuickNoteAttachmentFiles: Int
    let orphanPhotoFiles: Int
    let orphanDrawingFiles: Int
    let orphanDocumentFiles: Int
    let orphanQuickNoteAttachmentFiles: Int
    let orphanAttachmentMappings: Int
    let orphanWarehouseAttachmentMappings: Int
    let danglingDocumentLinks: Int
    let invalidProjectRefs: Int
    let storageIssues: Int
    let fileSnapshot: DataHealthScanFileSnapshot
    let storageIssueEntries: [String]
    let widgetHealth: WidgetDataHealthSnapshot?
    let storageUsage: DataHealthStorageUsageSnapshot?

    /// Scan timestamps and triggers do not change the findings shown by automatic scans.
    func hasSameFindings(as other: DataHealthScanSummary) -> Bool {
        missingPhotoFiles == other.missingPhotoFiles
            && missingDocumentFiles == other.missingDocumentFiles
            && missingQuickNoteAttachmentFiles == other.missingQuickNoteAttachmentFiles
            && orphanPhotoFiles == other.orphanPhotoFiles
            && orphanDrawingFiles == other.orphanDrawingFiles
            && orphanDocumentFiles == other.orphanDocumentFiles
            && orphanQuickNoteAttachmentFiles == other.orphanQuickNoteAttachmentFiles
            && orphanAttachmentMappings == other.orphanAttachmentMappings
            && orphanWarehouseAttachmentMappings == other.orphanWarehouseAttachmentMappings
            && danglingDocumentLinks == other.danglingDocumentLinks
            && invalidProjectRefs == other.invalidProjectRefs
            && storageIssues == other.storageIssues
            && fileSnapshot == other.fileSnapshot
            && storageIssueEntries == other.storageIssueEntries
            && widgetHealth == other.widgetHealth
            && storageUsage == other.storageUsage
    }

    var totalIssues: Int {
        missingPhotoFiles
            + missingDocumentFiles
            + missingQuickNoteAttachmentFiles
            + orphanPhotoFiles
            + orphanDrawingFiles
            + orphanDocumentFiles
            + orphanQuickNoteAttachmentFiles
            + orphanAttachmentMappings
            + orphanWarehouseAttachmentMappings
            + danglingDocumentLinks
            + invalidProjectRefs
            + storageIssues
    }

    var hasIssues: Bool {
        totalIssues > 0
    }

    func fillingSupplementalMetrics(from previous: DataHealthScanSummary?) -> DataHealthScanSummary {
        guard let previous else { return self }
        guard storageUsage == nil || widgetHealth == nil else { return self }
        return DataHealthScanSummary(
            scannedAt: scannedAt,
            reason: reason,
            missingPhotoFiles: missingPhotoFiles,
            missingDocumentFiles: missingDocumentFiles,
            missingQuickNoteAttachmentFiles: missingQuickNoteAttachmentFiles,
            orphanPhotoFiles: orphanPhotoFiles,
            orphanDrawingFiles: orphanDrawingFiles,
            orphanDocumentFiles: orphanDocumentFiles,
            orphanQuickNoteAttachmentFiles: orphanQuickNoteAttachmentFiles,
            orphanAttachmentMappings: orphanAttachmentMappings,
            orphanWarehouseAttachmentMappings: orphanWarehouseAttachmentMappings,
            danglingDocumentLinks: danglingDocumentLinks,
            invalidProjectRefs: invalidProjectRefs,
            storageIssues: storageIssues,
            fileSnapshot: fileSnapshot,
            storageIssueEntries: storageIssueEntries,
            widgetHealth: widgetHealth ?? previous.widgetHealth,
            storageUsage: storageUsage ?? previous.storageUsage
        )
    }
}
