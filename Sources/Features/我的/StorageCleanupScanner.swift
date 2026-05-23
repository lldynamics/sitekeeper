import Foundation
import SwiftUI

@MainActor
enum StorageCleanupScanner {
    static func scan(
        store: DataStore,
        cloudBackups: [CloudBackupFile],
        projectBackupEstimateByID: [UUID: Int],
        largeFileThresholdBytes: Int,
        videoFileExtensions: Set<String>,
        drawingSourceFileExtensions: Set<String>
    ) -> StorageCleanupScanResult {
        let photoEntries = scanPhotoEntries(store: store)
        let videoEntries = scanVideoEntries(
            store: store,
            videoFileExtensions: videoFileExtensions
        )
        let drawingEntries = scanDrawingSourceEntries(
            store: store,
            drawingFileExtensions: drawingSourceFileExtensions
        )
        let ticketEntries = scanTicketEntries(store: store)
        let backupEntries = scanBackupEntries(cloudBackups: cloudBackups)
        let historyBytes = (try? JSONEncoder().encode(store.historyRecords).count) ?? 0

        let categorySummaries = buildCategorySummaries(
            store: store,
            cloudBackups: cloudBackups,
            historyBytes: historyBytes,
            photoEntries: photoEntries,
            videoEntries: videoEntries,
            drawingEntries: drawingEntries,
            ticketEntries: ticketEntries
        )
        let largeFileItems = buildLargeFileItems(
            store: store,
            largeFileThresholdBytes: largeFileThresholdBytes,
            historyBytes: historyBytes,
            photoEntries: photoEntries,
            videoEntries: videoEntries,
            drawingEntries: drawingEntries,
            ticketEntries: ticketEntries,
            backupEntries: backupEntries
        )
        let projectUsages = buildProjectUsages(
            store: store,
            projectBackupEstimateByID: projectBackupEstimateByID,
            photoEntries: photoEntries,
            videoEntries: videoEntries,
            drawingEntries: drawingEntries,
            ticketEntries: ticketEntries
        )

        return StorageCleanupScanResult(
            categorySummaries: categorySummaries,
            largeFileItems: largeFileItems,
            projectUsages: projectUsages
        )
    }

    static func cleanupPreview(
        store: DataStore,
        projectId: UUID,
        category: ProjectStorageCleanupCategory,
        videoFileExtensions: Set<String>,
        drawingSourceFileExtensions: Set<String>
    ) -> CleanupImpactSummary {
        switch category {
        case .photos:
            return photoCleanupPreview(store: store, projectId: projectId)
        case .videos:
            return videoCleanupPreview(
                store: store,
                projectId: projectId,
                videoFileExtensions: videoFileExtensions
            )
        case .drawings:
            return drawingCleanupPreview(
                store: store,
                projectId: projectId,
                drawingFileExtensions: drawingSourceFileExtensions
            )
        case .tickets:
            return ticketCleanupPreview(store: store, projectId: projectId)
        case .all:
            var summary = CleanupImpactSummary()
            summary.merge(photoCleanupPreview(store: store, projectId: projectId))
            summary.merge(
                videoCleanupPreview(
                    store: store,
                    projectId: projectId,
                    videoFileExtensions: videoFileExtensions
                )
            )
            summary.merge(
                drawingCleanupPreview(
                    store: store,
                    projectId: projectId,
                    drawingFileExtensions: drawingSourceFileExtensions
                )
            )
            summary.merge(ticketCleanupPreview(store: store, projectId: projectId))
            return summary
        }
    }

    nonisolated static func makeProjectScopedSnapshot(from baseSnapshot: BackupSnapshot, projectId: UUID) -> BackupSnapshot {
        var snapshot = baseSnapshot
        snapshot.materialItems = snapshot.materialItems.filter { $0.projectId == projectId }
        snapshot.quoteItems = snapshot.quoteItems.filter { $0.projectId == projectId }
        snapshot.laborRecords = snapshot.laborRecords.filter { $0.projectId == projectId }
        snapshot.projects = snapshot.projects.filter { $0.id == projectId }
        snapshot.dailyLogs = snapshot.dailyLogs.filter { $0.projectId == projectId }
        snapshot.historyRecords = []
        snapshot.progressTasks = snapshot.progressTasks.filter { $0.projectId == projectId }
        snapshot.siteTodos = snapshot.siteTodos.filter { $0.projectId == projectId }
        snapshot.projectDrawings = snapshot.projectDrawings.filter { $0.projectId == projectId }
        snapshot.projectContacts = snapshot.projectContacts.filter { $0.projectId == projectId }
        snapshot.projectFinancialRecords = snapshot.projectFinancialRecords.filter { $0.projectId == projectId }
        snapshot.projectDocuments = snapshot.projectDocuments.filter { $0.projectId == projectId }
        snapshot.quickNotes = snapshot.quickNotes.filter { $0.projectId == projectId }
        snapshot.projectWarehouseMovements = snapshot.projectWarehouseMovements.filter { $0.projectId == projectId }
        snapshot.templates = []
        snapshot.materialPriceEntries = []
        snapshot.materialSheetDrafts = snapshot.materialSheetDrafts.filter { $0.projectId == projectId }
        snapshot.supplierProfiles = []
        snapshot.constructionMethods = []
        snapshot.favoriteMaterialKeys = []
        snapshot.recentMaterialKeys = []
        snapshot.userMaterials = []
        snapshot.deletedUserMaterials = []
        snapshot.hiddenPresetKeys = []
        snapshot.photoFiles = []
        snapshot.drawingFiles = []
        snapshot.documentFiles = []
        snapshot.quickNoteAttachmentFiles = []
        return snapshot
    }

    nonisolated static func estimateBackupBytes(for snapshot: BackupSnapshot) -> Int {
        let metadataBytes = (try? JSONEncoder().encode(snapshot).count) ?? 0

        let photoNames = Set(
            snapshot.dailyLogs.flatMap(\.allPhotoFileNames).filter { !$0.isEmpty }
                + snapshot.siteTodos.compactMap(\.rectificationBeforePhotoFileName).filter { !$0.isEmpty }
                + snapshot.siteTodos.compactMap(\.rectificationAfterPhotoFileName).filter { !$0.isEmpty }
        )
        let drawingNames = Set(snapshot.projectDrawings.map(\.fileName).filter { !$0.isEmpty })
        let documentNames = Set(snapshot.projectDocuments.map(\.fileName).filter { !$0.isEmpty })
        let attachmentNames = Set(snapshot.quickNotes.flatMap { $0.attachments.map(\.fileName) }.filter { !$0.isEmpty })

        let rawFilesBytes =
            sumFileBytes(fileNames: photoNames, size: PhotoStorage.fileSize(for:))
            + sumFileBytes(fileNames: drawingNames, size: DrawingStorage.fileSize(for:))
            + sumFileBytes(fileNames: documentNames, size: ProjectDocumentStorage.fileSize(for:))
            + sumFileBytes(fileNames: attachmentNames, size: QuickNoteAttachmentStorage.fileSize(for:))

        return metadataBytes + rawFilesBytes
    }

    static func projectName(for projectId: UUID?, projects: [Project]) -> String? {
        guard let projectId else { return nil }
        if let project = projects.first(where: { $0.id == projectId }) {
            let trimmed = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? String(localized: "未命名项目") : trimmed
        }
        return String(localized: "未知项目")
    }

    static func isTicketCategory(_ category: ProjectDocumentCategory) -> Bool {
        switch category {
        case .invoice, .receipt, .paymentRequest:
            return true
        default:
            return false
        }
    }

    private nonisolated static func sumFileBytes(fileNames: Set<String>, size: (String) -> Int) -> Int {
        fileNames.reduce(0) { partial, fileName in
            partial + size(fileName)
        }
    }
}
