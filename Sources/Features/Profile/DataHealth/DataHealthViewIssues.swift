import SwiftUI
import Foundation

extension DataHealthView {
    var latestScan: DataHealthScanSummary? {
        store.latestDataHealthScan
    }

    var latestSnapshot: DataHealthScanSnapshot? {
        store.latestDataHealthSnapshot
    }

    var projectIdSet: Set<UUID> {
        Set(store.projects.map(\.id))
    }

    var missingPhotoFiles: [String] {
        latestSnapshot?.missingPhotoFileNames ?? []
    }

    var missingDocumentFiles: [String] {
        latestSnapshot?.missingDocumentFileNames ?? []
    }

    var missingQuickNoteAttachmentFiles: [String] {
        latestSnapshot?.missingQuickNoteAttachmentFileNames ?? []
    }

    var orphanQuickNoteAttachmentFiles: [String] {
        latestSnapshot?.orphanQuickNoteAttachmentFileNames ?? []
    }

    var orphanPhotoFiles: [String] {
        latestSnapshot?.orphanPhotoFileNames ?? []
    }

    var orphanDrawingFiles: [String] {
        latestSnapshot?.orphanDrawingFileNames ?? []
    }

    var orphanDocumentFiles: [String] {
        latestSnapshot?.orphanDocumentFileNames ?? []
    }

    var orphanAttachmentMappings: [String] {
        orphanAttachmentMappingIssues.map(\.exportText)
    }

    var orphanWarehouseAttachmentMappings: [String] {
        orphanWarehouseAttachmentMappingIssues.map(\.exportText)
    }

    var danglingDocumentLinks: [String] {
        danglingDocumentLinkIssues.map(\.exportText)
    }

    var autoFixableInvalidProjectRefs: [String] {
        autoFixableInvalidProjectRefIssues.map(\.exportText)
    }

    var manualInvalidProjectRefs: [String] {
        manualInvalidProjectRefIssues.map(\.exportText)
    }

    var invalidProjectRefs: [String] {
        autoFixableInvalidProjectRefs + manualInvalidProjectRefs
    }

    var storageIssues: [String] {
        latestSnapshot?.storageIssues ?? []
    }

    var widgetHealth: WidgetDataHealthSnapshot {
        latestSnapshot?.widgetHealth
            ?? latestScan?.widgetHealth
            ?? WidgetDataHealthSnapshot(
                appGroupReadable: false,
                lastUpdatedAt: nil,
                projectCount: 0,
                pendingTodos: 0
            )
    }

    var photoThumbnailCacheBytes: Int {
        latestSnapshot?.storageUsage.photoThumbnailCacheBytes ?? 0
    }

    var quickNoteThumbnailCacheBytes: Int {
        latestSnapshot?.storageUsage.quickNoteThumbnailCacheBytes ?? 0
    }

    var mediaThumbnailCacheBytes: Int {
        photoThumbnailCacheBytes + quickNoteThumbnailCacheBytes
    }

    var photoStorageBytes: Int {
        latestSnapshot?.storageUsage.photoStorageBytes ?? 0
    }

    var projectDocumentBytes: Int {
        latestSnapshot?.storageUsage.projectDocumentBytes ?? 0
    }

    var projectDrawingBytes: Int {
        latestSnapshot?.storageUsage.projectDrawingBytes ?? 0
    }

    var quickNoteAttachmentBytes: Int {
        latestSnapshot?.storageUsage.quickNoteAttachmentBytes ?? 0
    }

    var projectAssetBytes: Int {
        projectDocumentBytes + projectDrawingBytes + quickNoteAttachmentBytes
    }

    var cloudBackupBytes: Int {
        latestSnapshot?.storageUsage.cloudBackupBytes ?? 0
    }

    var historyRecordBytes: Int {
        latestSnapshot?.storageUsage.historyRecordBytes ?? 0
    }

    var totalStorageBytes: Int {
        latestSnapshot?.storageUsage.totalStorageBytes ?? 0
    }

    var totalIssues: Int {
        latestScan?.totalIssues ?? 0
    }

    var referenceIssueCount: Int {
        latestScan.map { summary in
            summary.missingPhotoFiles
                + summary.missingDocumentFiles
                + summary.missingQuickNoteAttachmentFiles
                + summary.orphanAttachmentMappings
                + summary.orphanWarehouseAttachmentMappings
                + summary.danglingDocumentLinks
                + autoFixableInvalidProjectRefs.count
        } ?? 0
    }

    var orphanFileIssueCount: Int {
        latestScan.map { summary in
            summary.orphanPhotoFiles
                + summary.orphanDrawingFiles
                + summary.orphanDocumentFiles
                + summary.orphanQuickNoteAttachmentFiles
        } ?? 0
    }
}
