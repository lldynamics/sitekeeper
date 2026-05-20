import Foundation
import SwiftUI

struct StorageCleanupScanResult {
    let categorySummaries: [StorageCategorySummary]
    let largeFileItems: [StorageLargeFileItem]
    let projectUsages: [ProjectStorageUsage]
}

@MainActor
enum StorageCleanupScanner {
    static func scan(
        store: DataStore,
        cloudBackups: [CloudBackupFile],
        projectBackupEstimateByID: [UUID: Int],
        largeFileThresholdBytes: Int,
        videoFileExtensions: Set<String>,
        cadFileExtensions: Set<String>
    ) -> StorageCleanupScanResult {
        let photoEntries = scanPhotoEntries(store: store)
        let videoEntries = scanVideoEntries(
            store: store,
            videoFileExtensions: videoFileExtensions
        )
        let cadEntries = scanCADEntries(
            store: store,
            cadFileExtensions: cadFileExtensions
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
            cadEntries: cadEntries,
            ticketEntries: ticketEntries
        )
        let largeFileItems = buildLargeFileItems(
            store: store,
            largeFileThresholdBytes: largeFileThresholdBytes,
            historyBytes: historyBytes,
            photoEntries: photoEntries,
            videoEntries: videoEntries,
            cadEntries: cadEntries,
            ticketEntries: ticketEntries,
            backupEntries: backupEntries
        )
        let projectUsages = buildProjectUsages(
            store: store,
            projectBackupEstimateByID: projectBackupEstimateByID,
            photoEntries: photoEntries,
            videoEntries: videoEntries,
            cadEntries: cadEntries,
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
        cadFileExtensions: Set<String>
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
        case .cad:
            return cadCleanupPreview(
                store: store,
                projectId: projectId,
                cadFileExtensions: cadFileExtensions
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
                cadCleanupPreview(
                    store: store,
                    projectId: projectId,
                    cadFileExtensions: cadFileExtensions
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

    private static func scanPhotoEntries(store: DataStore) -> [StorageLargeFileItem] {
        var entries: [StorageLargeFileItem] = []
        var seen = Set<String>()
        for log in store.dailyLogs {
            let projectName = projectName(for: log.projectId, projects: store.projects)
            for photo in log.photoAttachments {
                guard seen.insert(photo.fileName).inserted else { continue }
                let bytes = PhotoStorage.fileSize(for: photo.fileName)
                guard bytes > 0 else { continue }
                entries.append(
                    StorageLargeFileItem(
                        id: "photo-\(photo.fileName)",
                        category: .photo,
                        title: photo.fileName,
                        detail: log.date,
                        projectId: log.projectId,
                        projectName: projectName,
                        bytes: bytes
                    )
                )
            }
        }
        for todo in store.siteTodos {
            let projectName = projectName(for: todo.projectId, projects: store.projects)
            let candidates: [(String?, String)] = [
                (todo.rectificationBeforePhotoFileName, String(localized: "整改前")),
                (todo.rectificationAfterPhotoFileName, String(localized: "整改后"))
            ]
            for (fileName, phase) in candidates {
                guard let fileName, seen.insert(fileName).inserted else { continue }
                let bytes = PhotoStorage.fileSize(for: fileName)
                guard bytes > 0 else { continue }
                entries.append(
                    StorageLargeFileItem(
                        id: "photo-\(fileName)",
                        category: .photo,
                        title: "\(todo.title) · \(phase)",
                        detail: fileName,
                        projectId: todo.projectId,
                        projectName: projectName,
                        bytes: bytes
                    )
                )
            }
        }
        return entries
    }

    private static func scanVideoEntries(
        store: DataStore,
        videoFileExtensions: Set<String>
    ) -> [StorageLargeFileItem] {
        var entries: [StorageLargeFileItem] = []
        var seen = Set<String>()

        for note in store.quickNotes {
            let projectName = projectName(for: note.projectId, projects: store.projects)
            for attachment in note.attachments where attachment.attachmentKind == .video {
                guard seen.insert(attachment.fileName).inserted else { continue }
                let bytes = QuickNoteAttachmentStorage.fileSize(for: attachment.fileName)
                guard bytes > 0 else { continue }
                entries.append(
                    StorageLargeFileItem(
                        id: "video-\(attachment.fileName)",
                        category: .video,
                        title: attachment.displayName,
                        detail: note.title.isEmpty ? note.createdAt : note.title,
                        projectId: note.projectId,
                        projectName: projectName,
                        bytes: bytes
                    )
                )
            }
        }

        for document in store.projectDocuments {
            let ext = document.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard videoFileExtensions.contains(ext),
                  !isTicketCategory(document.category),
                  seen.insert(document.fileName).inserted else { continue }
            let bytes = ProjectDocumentStorage.fileSize(for: document.fileName)
            guard bytes > 0 else { continue }
            entries.append(
                StorageLargeFileItem(
                    id: "video-doc-\(document.fileName)",
                    category: .video,
                    title: document.title.isEmpty ? document.fileName : document.title,
                    detail: document.fileName,
                    projectId: document.projectId,
                    projectName: projectName(for: document.projectId, projects: store.projects),
                    bytes: bytes
                )
            )
        }
        return entries
    }

    private static func scanCADEntries(
        store: DataStore,
        cadFileExtensions: Set<String>
    ) -> [StorageLargeFileItem] {
        store.projectDrawings.compactMap { drawing in
            let ext = drawing.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard cadFileExtensions.contains(ext) else { return nil }
            let bytes = DrawingStorage.fileSize(for: drawing.fileName)
            guard bytes > 0 else { return nil }
            return StorageLargeFileItem(
                id: "cad-\(drawing.fileName)",
                category: .cad,
                title: drawing.name.isEmpty ? drawing.fileName : drawing.name,
                detail: "\(drawing.version) · \(drawing.fileName)",
                projectId: drawing.projectId,
                projectName: projectName(for: drawing.projectId, projects: store.projects),
                bytes: bytes
            )
        }
    }

    private static func scanTicketEntries(store: DataStore) -> [StorageLargeFileItem] {
        store.projectDocuments.compactMap { document in
            guard isTicketCategory(document.category) else { return nil }
            let bytes = ProjectDocumentStorage.fileSize(for: document.fileName)
            guard bytes > 0 else { return nil }
            let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return StorageLargeFileItem(
                id: "ticket-\(document.id.uuidString)",
                category: .ticket,
                title: title.isEmpty ? document.fileName : title,
                detail: "\(document.category.displayName) · \(document.fileName)",
                projectId: document.projectId,
                projectName: projectName(for: document.projectId, projects: store.projects),
                bytes: bytes
            )
        }
    }

    private static func scanBackupEntries(cloudBackups: [CloudBackupFile]) -> [StorageLargeFileItem] {
        cloudBackups.map { backup in
            StorageLargeFileItem(
                id: "backup-\(backup.id)",
                category: .backup,
                title: backup.fileName,
                detail: backup.formattedModifiedAt,
                projectName: nil,
                bytes: backup.byteSize
            )
        }
    }

    private static func buildCategorySummaries(
        store: DataStore,
        cloudBackups: [CloudBackupFile],
        historyBytes: Int,
        photoEntries: [StorageLargeFileItem],
        videoEntries: [StorageLargeFileItem],
        cadEntries: [StorageLargeFileItem],
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
                title: String(localized: "CAD 图纸"),
                icon: "compass.drawing",
                tint: .appDoc,
                bytes: cadEntries.reduce(0) { $0 + $1.bytes },
                count: cadEntries.count
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

    private static func buildLargeFileItems(
        store: DataStore,
        largeFileThresholdBytes: Int,
        historyBytes: Int,
        photoEntries: [StorageLargeFileItem],
        videoEntries: [StorageLargeFileItem],
        cadEntries: [StorageLargeFileItem],
        ticketEntries: [StorageLargeFileItem],
        backupEntries: [StorageLargeFileItem]
    ) -> [StorageLargeFileItem] {
        var items = (photoEntries + videoEntries + cadEntries + ticketEntries + backupEntries)
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

    private static func buildProjectUsages(
        store: DataStore,
        projectBackupEstimateByID: [UUID: Int],
        photoEntries: [StorageLargeFileItem],
        videoEntries: [StorageLargeFileItem],
        cadEntries: [StorageLargeFileItem],
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
            let cadBytes = cadEntries
                .filter { $0.projectId == projectId }
                .reduce(0) { $0 + $1.bytes }
            let ticketBytes = ticketEntries
                .filter { $0.projectId == projectId }
                .reduce(0) { $0 + $1.bytes }
            let total = photoBytes + videoBytes + cadBytes + ticketBytes
            guard total > 0 else { return nil }
            return ProjectStorageUsage(
                projectId: projectId,
                projectName: project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "未命名项目") : project.name,
                photoBytes: photoBytes,
                videoBytes: videoBytes,
                cadBytes: cadBytes,
                ticketBytes: ticketBytes,
                backupEstimatedBytes: projectBackupEstimateByID[projectId]
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalBytes != rhs.totalBytes { return lhs.totalBytes > rhs.totalBytes }
            return lhs.projectName.localizedStandardCompare(rhs.projectName) == .orderedAscending
        }
    }

    private static func photoCleanupPreview(store: DataStore, projectId: UUID) -> CleanupImpactSummary {
        let projectLogs = store.dailyLogs.filter { $0.projectId == projectId }
        let projectTodos = store.siteTodos.filter { $0.projectId == projectId }
        let logsWithPhotos = projectLogs.filter { !$0.allPhotoFileNames.isEmpty }
        let todosWithPhotos = projectTodos.filter {
            $0.rectificationBeforePhotoFileName != nil || $0.rectificationAfterPhotoFileName != nil
        }

        var selectedPhotoNames = Set<String>()
        for log in projectLogs {
            selectedPhotoNames.formUnion(log.allPhotoFileNames)
        }
        for todo in projectTodos {
            if let before = todo.rectificationBeforePhotoFileName {
                selectedPhotoNames.insert(before)
            }
            if let after = todo.rectificationAfterPhotoFileName {
                selectedPhotoNames.insert(after)
            }
        }
        let remainingLogs = store.dailyLogs.filter { $0.projectId != projectId }
        let remainingTodos = store.siteTodos.filter { $0.projectId != projectId }
        let remainingPhotoNames = PhotoStorage.referencedFileNames(logs: remainingLogs, todos: remainingTodos)
        let deletablePhotoNames = selectedPhotoNames.filter { !remainingPhotoNames.contains($0) }

        var summary = CleanupImpactSummary()
        summary.addFile(title: String(localized: "照片原文件"), count: deletablePhotoNames.count)
        summary.addRecord(title: String(localized: "日志照片记录"), count: logsWithPhotos.count)
        summary.addRecord(title: String(localized: "待办整改照片"), count: todosWithPhotos.count)
        summary.addSampleFileNames(deletablePhotoNames)
        return summary
    }

    private static func videoCleanupPreview(
        store: DataStore,
        projectId: UUID,
        videoFileExtensions: Set<String>
    ) -> CleanupImpactSummary {
        let projectNotes = store.quickNotes.filter { $0.projectId == projectId }
        let notesWithVideos = projectNotes.filter { note in
            note.attachments.contains { $0.attachmentKind == .video }
        }

        var selectedAttachmentNames = Set<String>()
        for note in projectNotes {
            let names = note.attachments
                .filter { $0.attachmentKind == .video }
                .map(\.fileName)
            selectedAttachmentNames.formUnion(names)
        }

        let videoDocuments = store.projectDocuments
            .filter { $0.projectId == projectId }
            .filter { document in
                let ext = document.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return videoFileExtensions.contains(ext) && !isTicketCategory(document.category)
            }
        let videoDocumentIDs = Set(videoDocuments.map(\.id))
        let videoDocumentFileNames = Set(videoDocuments.map(\.fileName))

        let notesAfterCleanup = store.quickNotes.map { note -> QuickNote in
            guard note.projectId == projectId else { return note }
            var value = note
            value.attachments.removeAll { $0.attachmentKind == .video }
            return value
        }

        let extraMethodAttachments = store.constructionMethods.flatMap(\.attachments)
            + store.constructionMethods.flatMap(\.tutorialAttachments)
        let remainingAttachmentNames = QuickNoteAttachmentStorage.referencedFileNames(
            for: notesAfterCleanup,
            extraAttachments: extraMethodAttachments
        )
        let deletableAttachmentNames = selectedAttachmentNames.filter { !remainingAttachmentNames.contains($0) }

        let remainingDocumentNamesAfterCleanup = Set(
            store.projectDocuments
                .filter { !videoDocumentIDs.contains($0.id) }
                .map(\.fileName)
        )
        let deletableDocumentNames = videoDocumentFileNames.filter { !remainingDocumentNamesAfterCleanup.contains($0) }

        let financialLinkedCount = store.projectFinancialRecords.filter { record in
            record.linkedDocumentIds.contains(where: videoDocumentIDs.contains)
        }.count
        let warehouseLinkedCount = store.projectWarehouseMovements.filter { movement in
            movement.linkedDocumentIds.contains(where: videoDocumentIDs.contains)
        }.count

        var summary = CleanupImpactSummary()
        summary.addFile(title: String(localized: "随手记视频文件"), count: deletableAttachmentNames.count)
        summary.addFile(title: String(localized: "资料视频文件"), count: deletableDocumentNames.count)
        summary.addRecord(title: String(localized: "随手记视频记录"), count: notesWithVideos.count)
        summary.addRecord(title: String(localized: "视频资料记录"), count: videoDocumentIDs.count)
        summary.addRecord(title: String(localized: "财务关联变更"), count: financialLinkedCount)
        summary.addRecord(title: String(localized: "仓库关联变更"), count: warehouseLinkedCount)
        summary.addSampleFileNames(Set(deletableAttachmentNames).union(deletableDocumentNames))
        return summary
    }

    private static func cadCleanupPreview(
        store: DataStore,
        projectId: UUID,
        cadFileExtensions: Set<String>
    ) -> CleanupImpactSummary {
        let drawings = store.projectDrawings
            .filter { $0.projectId == projectId }
            .filter { drawing in
                let ext = drawing.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return cadFileExtensions.contains(ext)
            }
        let drawingFileNames = Set(drawings.map(\.fileName))
        let remainingDrawingNamesAfterCleanup = Set(
            store.projectDrawings
                .filter { drawing in
                    let ext = drawing.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let shouldRemove = drawing.projectId == projectId && cadFileExtensions.contains(ext)
                    return !shouldRemove
                }
                .map(\.fileName)
        )
        let deletableDrawingNames = drawingFileNames.filter { !remainingDrawingNamesAfterCleanup.contains($0) }

        var summary = CleanupImpactSummary()
        summary.addFile(title: String(localized: "CAD 文件"), count: deletableDrawingNames.count)
        summary.addRecord(title: String(localized: "CAD 图纸记录"), count: drawings.count)
        summary.addSampleFileNames(deletableDrawingNames)
        return summary
    }

    private static func ticketCleanupPreview(store: DataStore, projectId: UUID) -> CleanupImpactSummary {
        let ticketDocuments = store.projectDocuments.filter { $0.projectId == projectId && isTicketCategory($0.category) }
        let removedDocumentIDs = Set(ticketDocuments.map(\.id))
        let documentFileNames = Set(ticketDocuments.map(\.fileName))
        let remainingDocumentNamesAfterCleanup = Set(
            store.projectDocuments
                .filter { !removedDocumentIDs.contains($0.id) }
                .map(\.fileName)
        )
        let deletableDocumentNames = documentFileNames.filter { !remainingDocumentNamesAfterCleanup.contains($0) }

        let financialLinkedCount = store.projectFinancialRecords.filter { record in
            record.linkedDocumentIds.contains(where: removedDocumentIDs.contains)
        }.count
        let warehouseLinkedCount = store.projectWarehouseMovements.filter { movement in
            movement.linkedDocumentIds.contains(where: removedDocumentIDs.contains)
        }.count

        var summary = CleanupImpactSummary()
        summary.addFile(title: String(localized: "票据文件"), count: deletableDocumentNames.count)
        summary.addRecord(title: String(localized: "票据资料记录"), count: removedDocumentIDs.count)
        summary.addRecord(title: String(localized: "财务关联变更"), count: financialLinkedCount)
        summary.addRecord(title: String(localized: "仓库关联变更"), count: warehouseLinkedCount)
        summary.addSampleFileNames(deletableDocumentNames)
        return summary
    }

    private static func projectName(for projectId: UUID?, projects: [Project]) -> String? {
        guard let projectId else { return nil }
        if let project = projects.first(where: { $0.id == projectId }) {
            let trimmed = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? String(localized: "未命名项目") : trimmed
        }
        return String(localized: "未知项目")
    }

    private static func isTicketCategory(_ category: ProjectDocumentCategory) -> Bool {
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
