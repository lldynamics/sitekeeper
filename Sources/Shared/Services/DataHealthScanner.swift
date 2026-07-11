import Foundation

struct DataHealthScanStorage {
    var photoExists: (String) -> Bool = PhotoStorage.exists(fileName:)
    var projectDocumentExists: (String) -> Bool = ProjectDocumentStorage.exists(fileName:)
    var quickNoteAttachmentExists: (String) -> Bool = QuickNoteAttachmentStorage.exists(fileName:)
    var orphanPhotoFileNames: ([DailyLog], [SiteTodo]) -> [String] = PhotoStorage.orphanFileNames(logs:todos:)
    var orphanDrawingFileNames: ([ProjectDrawing]) -> [String] = DrawingStorage.orphanFileNames(for:)
    var orphanProjectDocumentFileNames: ([ProjectDocument]) -> [String] = ProjectDocumentStorage.orphanFileNames(for:)
    var orphanQuickNoteAttachmentFileNames: ([QuickNote], [QuickNoteAttachment]) -> [String] = QuickNoteAttachmentStorage.orphanFileNames(for:extraAttachments:)
    var photoFileSize: (String) -> Int = PhotoStorage.fileSize(for:)
    var projectDocumentFileSize: (String) -> Int = ProjectDocumentStorage.fileSize(for:)
    var drawingFileSize: (String) -> Int = DrawingStorage.fileSize(for:)
    var quickNoteAttachmentFileSize: (String) -> Int = QuickNoteAttachmentStorage.fileSize(for:)
    var photoThumbnailCacheBytes: () -> Int = PhotoStorage.thumbnailCacheUsageBytes
    var quickNoteThumbnailCacheBytes: () -> Int = QuickNoteAttachmentStorage.thumbnailCacheUsageBytes
    var cloudBackupBytes: () -> Int = {
        (try? CloudBackupService.listBackups().reduce(0) { $0 + $1.byteSize }) ?? 0
    }
}

enum DataHealthScanner {
    static func scan(
        input: DataHealthScanInput,
        reason: DataHealthScanReason,
        scannedAt: Date = Date(),
        includeSupplementalMetrics: Bool = true,
        storage: DataHealthScanStorage = DataHealthScanStorage()
    ) -> DataHealthScanSummary {
        let projectIds = Set(input.projects.map(\.id))
        let quickNoteAttachments = input.quickNotes.flatMap(\.attachments)
        let methodAttachments = input.constructionMethods.flatMap(\.attachments)
            + input.constructionMethods.flatMap(\.tutorialAttachments)
        let allQuickNoteAttachments = quickNoteAttachments + methodAttachments
        let referencedPhotoNames = Set(
            input.dailyLogs.flatMap(\.allPhotoFileNames)
                + input.siteTodos.flatMap { [$0.rectificationBeforePhotoFileName, $0.rectificationAfterPhotoFileName].compactMap { $0 } }
        )

        let missingPhotoFileNames = referencedPhotoNames.filter { !storage.photoExists($0) }.sorted()
        let missingDocumentFileNames = input.projectDocuments
            .filter { !storage.projectDocumentExists($0.fileName) }
            .map(\.fileName)
            .sorted()
        let missingQuickNoteAttachmentFileNames = allQuickNoteAttachments
            .filter { !storage.quickNoteAttachmentExists($0.fileName) }
            .map(\.fileName)
            .sorted()
        let orphanPhotoFileNames = storage.orphanPhotoFileNames(input.dailyLogs, input.siteTodos).sorted()
        let orphanDrawingFileNames = storage.orphanDrawingFileNames(input.projectDrawings).sorted()
        let orphanDocumentFileNames = storage.orphanProjectDocumentFileNames(input.projectDocuments).sorted()
        let orphanQuickNoteAttachmentFileNames = storage.orphanQuickNoteAttachmentFileNames(input.quickNotes, methodAttachments).sorted()
        let fileSnapshot = DataHealthScanFileSnapshot(
            missingPhotoFileNames: missingPhotoFileNames,
            missingDocumentFileNames: missingDocumentFileNames,
            missingQuickNoteAttachmentFileNames: missingQuickNoteAttachmentFileNames,
            orphanPhotoFileNames: orphanPhotoFileNames,
            orphanDrawingFileNames: orphanDrawingFileNames,
            orphanDocumentFileNames: orphanDocumentFileNames,
            orphanQuickNoteAttachmentFileNames: orphanQuickNoteAttachmentFileNames
        )

        let documentProjectIDs = Dictionary(uniqueKeysWithValues: input.projectDocuments.map { ($0.id, $0.projectId) })
        let financialRecordProjectIDs = Dictionary(uniqueKeysWithValues: input.projectFinancialRecords.map { ($0.id, $0.projectId) })
        let orphanAttachmentMappings = input.projectFinancialRecords.reduce(0) { count, record in
            count + record.linkedDocumentIds.filter { documentProjectIDs[$0] != record.projectId }.count
        }
        let orphanWarehouseAttachmentMappings = input.projectWarehouseMovements.reduce(0) { count, movement in
            count + movement.linkedDocumentIds.filter { documentProjectIDs[$0] != movement.projectId }.count
        }
        let danglingDocumentLinks = input.projectDocuments.filter { document in
            guard let linkedId = document.linkedFinancialRecordId else { return false }
            return financialRecordProjectIDs[linkedId] != document.projectId
        }.count
        let invalidProjectRefs = invalidProjectReferenceCount(input: input, projectIds: projectIds)
        let storageIssueEntries = input.storageIssues.sorted()

        let storageUsage: DataHealthStorageUsageSnapshot?
        let widgetHealth: WidgetDataHealthSnapshot?
        if includeSupplementalMetrics {
            storageUsage = buildStorageUsageSnapshot(
                input: input,
                referencedPhotoNames: referencedPhotoNames,
                allQuickNoteAttachments: allQuickNoteAttachments,
                storage: storage
            )
            widgetHealth = readWidgetHealthSnapshot()
        } else {
            storageUsage = nil
            widgetHealth = nil
        }

        return DataHealthScanSummary(
            scannedAt: scannedAt,
            reason: reason,
            missingPhotoFiles: missingPhotoFileNames.count,
            missingDocumentFiles: missingDocumentFileNames.count,
            missingQuickNoteAttachmentFiles: missingQuickNoteAttachmentFileNames.count,
            orphanPhotoFiles: orphanPhotoFileNames.count,
            orphanDrawingFiles: orphanDrawingFileNames.count,
            orphanDocumentFiles: orphanDocumentFileNames.count,
            orphanQuickNoteAttachmentFiles: orphanQuickNoteAttachmentFileNames.count,
            orphanAttachmentMappings: orphanAttachmentMappings,
            orphanWarehouseAttachmentMappings: orphanWarehouseAttachmentMappings,
            danglingDocumentLinks: danglingDocumentLinks,
            invalidProjectRefs: invalidProjectRefs,
            storageIssues: storageIssueEntries.count,
            fileSnapshot: fileSnapshot,
            storageIssueEntries: storageIssueEntries,
            widgetHealth: widgetHealth,
            storageUsage: storageUsage
        )
    }

    private static func invalidProjectReferenceCount(input: DataHealthScanInput, projectIds: Set<UUID>) -> Int {
        invalidOptionalProjectCount(input.materialItems.map(\.projectId), projectIds: projectIds)
            + invalidOptionalProjectCount(input.quoteItems.map(\.projectId), projectIds: projectIds)
            + invalidOptionalProjectCount(input.laborRecords.map(\.projectId), projectIds: projectIds)
            + invalidOptionalProjectCount(input.dailyLogs.map(\.projectId), projectIds: projectIds)
            + invalidOptionalProjectCount(input.siteTodos.map(\.projectId), projectIds: projectIds)
            + invalidOptionalProjectCount(input.quickNotes.map(\.projectId), projectIds: projectIds)
            + input.progressTasks.filter { !projectIds.contains($0.projectId) }.count
            + input.projectDrawings.filter { !projectIds.contains($0.projectId) }.count
            + input.projectContacts.filter { !projectIds.contains($0.projectId) }.count
            + input.projectFinancialRecords.filter { !projectIds.contains($0.projectId) }.count
            + input.projectDocuments.filter { !projectIds.contains($0.projectId) }.count
            + input.projectWarehouseMovements.filter { !projectIds.contains($0.projectId) }.count
    }

    private static func invalidOptionalProjectCount(_ ids: [UUID?], projectIds: Set<UUID>) -> Int {
        ids.compactMap { $0 }.filter { !projectIds.contains($0) }.count
    }

    private static func buildStorageUsageSnapshot(
        input: DataHealthScanInput,
        referencedPhotoNames: Set<String>,
        allQuickNoteAttachments: [QuickNoteAttachment],
        storage: DataHealthScanStorage
    ) -> DataHealthStorageUsageSnapshot {
        let photoStorageBytes = referencedPhotoNames.reduce(0) { total, fileName in
            total + storage.photoFileSize(fileName)
        }
        let projectDocumentBytes = Set(input.projectDocuments.map(\.fileName)).reduce(0) { total, fileName in
            total + storage.projectDocumentFileSize(fileName)
        }
        let projectDrawingBytes = Set(input.projectDrawings.map(\.fileName)).reduce(0) { total, fileName in
            total + storage.drawingFileSize(fileName)
        }
        let quickNoteAttachmentBytes = Set(allQuickNoteAttachments.map(\.fileName)).reduce(0) { total, fileName in
            total + storage.quickNoteAttachmentFileSize(fileName)
        }
        let historyRecordBytes = (try? JSONEncoder().encode(input.historyRecords).count) ?? 0

        return DataHealthStorageUsageSnapshot(
            photoStorageBytes: photoStorageBytes,
            projectDocumentBytes: projectDocumentBytes,
            projectDrawingBytes: projectDrawingBytes,
            quickNoteAttachmentBytes: quickNoteAttachmentBytes,
            photoThumbnailCacheBytes: storage.photoThumbnailCacheBytes(),
            quickNoteThumbnailCacheBytes: storage.quickNoteThumbnailCacheBytes(),
            cloudBackupBytes: storage.cloudBackupBytes(),
            historyRecordBytes: historyRecordBytes
        )
    }

    private static func readWidgetHealthSnapshot() -> WidgetDataHealthSnapshot {
        guard let defaults = UserDefaults(suiteName: WidgetSharedDefaults.suiteName) else {
            return WidgetDataHealthSnapshot(
                appGroupReadable: false,
                lastUpdatedAt: nil,
                projectCount: 0,
                pendingTodos: 0
            )
        }

        let data: WidgetExportData
        if let raw = defaults.data(forKey: WidgetSharedDefaults.dataKey),
           let decoded = try? JSONDecoder().decode(WidgetExportData.self, from: raw) {
            data = decoded
        } else {
            data = WidgetExportData(projects: [], pendingTodos: 0, materialStockCount: 0, lowStockCount: 0)
        }
        let timestamp = defaults.double(forKey: WidgetSharedDefaults.updatedAtKey)
        return WidgetDataHealthSnapshot(
            appGroupReadable: true,
            lastUpdatedAt: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil,
            projectCount: data.projects.count,
            pendingTodos: data.pendingTodos
        )
    }
}
