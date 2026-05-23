import Foundation

struct StorageCleanupUndoSnapshot: Codable, Sendable {
    let dailyLogs: [DailyLog]
    let siteTodos: [SiteTodo]
    let quickNotes: [QuickNote]
    let projectDrawings: [ProjectDrawing]
    let projectDocuments: [ProjectDocument]
    let projectFinancialRecords: [ProjectFinancialRecord]
    let projectWarehouseMovements: [ProjectWarehouseMovement]

    @MainActor
    static func capture(from store: DataStore) -> StorageCleanupUndoSnapshot {
        StorageCleanupUndoSnapshot(
            dailyLogs: store.dailyLogs,
            siteTodos: store.siteTodos,
            quickNotes: store.quickNotes,
            projectDrawings: store.projectDrawings,
            projectDocuments: store.projectDocuments,
            projectFinancialRecords: store.projectFinancialRecords,
            projectWarehouseMovements: store.projectWarehouseMovements
        )
    }

    @MainActor
    func restore(into store: DataStore) {
        store.replaceDailyLogs(dailyLogs)
        store.replaceSiteTodos(siteTodos)
        store.replaceQuickNotes(quickNotes)
        store.replaceProjectDrawings(projectDrawings)
        store.replaceProjectDocuments(projectDocuments)
        store.replaceProjectFinancialRecords(projectFinancialRecords)
        store.replaceProjectWarehouseMovements(projectWarehouseMovements)
    }
}

struct DeferredProjectFileCleanupPlan: Codable, Sendable {
    var photoFileNames: Set<String> = []
    var quickNoteAttachmentFileNames: Set<String> = []
    var projectDocumentFileNames: Set<String> = []
    var drawingFileNames: Set<String> = []

    init(
        photoFileNames: Set<String> = [],
        quickNoteAttachmentFileNames: Set<String> = [],
        projectDocumentFileNames: Set<String> = [],
        drawingFileNames: Set<String> = []
    ) {
        self.photoFileNames = photoFileNames
        self.quickNoteAttachmentFileNames = quickNoteAttachmentFileNames
        self.projectDocumentFileNames = projectDocumentFileNames
        self.drawingFileNames = drawingFileNames
    }

    init(_ result: DataStoreProjectFileCleanupResult) {
        self.init(
            photoFileNames: result.photoFileNames,
            quickNoteAttachmentFileNames: result.quickNoteAttachmentFileNames,
            projectDocumentFileNames: result.projectDocumentFileNames,
            drawingFileNames: result.drawingFileNames
        )
    }

    var totalFileCount: Int {
        photoFileNames.count
            + quickNoteAttachmentFileNames.count
            + projectDocumentFileNames.count
            + drawingFileNames.count
    }

    mutating func merge(_ other: DeferredProjectFileCleanupPlan) {
        photoFileNames.formUnion(other.photoFileNames)
        quickNoteAttachmentFileNames.formUnion(other.quickNoteAttachmentFileNames)
        projectDocumentFileNames.formUnion(other.projectDocumentFileNames)
        drawingFileNames.formUnion(other.drawingFileNames)
    }
}

struct StorageCleanupTrashBatch: Identifiable, Codable, Sendable {
    let id: UUID
    let summary: String
    let createdAt: Date
    let expiresAt: Date
    let snapshot: StorageCleanupUndoSnapshot
    let files: [StorageCleanupTrashFile]

    var fileCount: Int { files.count }
}

struct StorageCleanupTrashFile: Identifiable, Codable, Sendable {
    let id: UUID
    let kind: StorageCleanupTrashFileKind
    let originalFileName: String
    let trashedFileName: String
}

enum StorageCleanupTrashFileKind: String, Codable, Sendable {
    case photoOriginal
    case photoThumbnail
    case drawing
    case quickNoteAttachment
    case projectDocument

    func originalURL(for fileName: String) -> URL {
        switch self {
        case .photoOriginal:
            return PhotoStorage.fileURL(for: fileName)
        case .photoThumbnail:
            return PhotoStorage.thumbnailStorageURL(for: fileName)
        case .drawing:
            return DrawingStorage.fileURL(for: fileName)
        case .quickNoteAttachment:
            return QuickNoteAttachmentStorage.fileURL(for: fileName)
        case .projectDocument:
            return ProjectDocumentStorage.fileURL(for: fileName)
        }
    }

    func invalidateCache(for fileName: String) {
        switch self {
        case .photoOriginal, .photoThumbnail:
            PhotoCache.shared.invalidate(fileName: fileName)
        case .drawing, .quickNoteAttachment, .projectDocument:
            break
        }
    }
}

enum StorageCleanupTrashError: LocalizedError {
    case rootUnavailable
    case manifestWriteFailed
    case moveToTrashFailed(String)
    case restoreFailed(String)
    case permanentDeleteFailed(String)

    var errorDescription: String? {
        switch self {
        case .rootUnavailable:
            return String(localized: "无法访问清理回收站目录。")
        case .manifestWriteFailed:
            return String(localized: "无法保存清理回收站清单。")
        case let .moveToTrashFailed(fileName):
            return String(format: String(localized: "无法移入清理回收站：%@"), fileName)
        case let .restoreFailed(fileName):
            return String(format: String(localized: "无法恢复清理回收站文件：%@"), fileName)
        case let .permanentDeleteFailed(fileName):
            return String(format: String(localized: "无法永久删除清理回收站文件：%@"), fileName)
        }
    }
}

enum StorageCleanupTrashStore {
    private static let manifestFileName = "manifest.json"

    private static var rootURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("StorageCleanupTrash", isDirectory: true)
    }

    private static var manifestURL: URL? {
        rootURL?.appendingPathComponent(manifestFileName)
    }

    static func loadBatches() -> [StorageCleanupTrashBatch] {
        guard let manifestURL else { return [] }
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: manifestURL)
            return try JSONDecoder().decode([StorageCleanupTrashBatch].self, from: data)
                .sorted { lhs, rhs in lhs.createdAt > rhs.createdAt }
        } catch {
            StorageIssueLog.recordEvent(
                "storage_cleanup.trash_manifest_read_failed",
                category: .dataStore,
                details: [
                    "source": "StorageCleanupTrashStore.loadBatches",
                    "manifest_file": manifestURL.lastPathComponent
                ],
                error: error
            )
            return []
        }
    }

    static func quarantine(
        plan: DeferredProjectFileCleanupPlan,
        snapshot: StorageCleanupUndoSnapshot,
        summary: String,
        retentionDays: Int
    ) throws -> StorageCleanupTrashBatch {
        guard let rootURL else { throw StorageCleanupTrashError.rootUnavailable }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let batchID = UUID()
        let createdAt = Date()
        let expiresAt = Calendar.current.date(
            byAdding: .day,
            value: max(retentionDays, 1),
            to: createdAt
        ) ?? createdAt.addingTimeInterval(TimeInterval(max(retentionDays, 1) * 24 * 60 * 60))

        var movedFiles: [StorageCleanupTrashFile] = []
        do {
            for source in trashSources(for: plan) {
                if let file = try moveToTrash(source, batchID: batchID) {
                    movedFiles.append(file)
                }
            }

            let batch = StorageCleanupTrashBatch(
                id: batchID,
                summary: summary,
                createdAt: createdAt,
                expiresAt: expiresAt,
                snapshot: snapshot,
                files: movedFiles
            )
            var batches = loadBatches()
            batches.removeAll { $0.id == batch.id }
            batches.append(batch)
            try saveBatches(batches)
            return batch
        } catch {
            rollback(files: movedFiles, batchID: batchID)
            throw error
        }
    }

    static func restore(_ batch: StorageCleanupTrashBatch) throws {
        for file in batch.files {
            try restore(file: file, batchID: batch.id)
        }
        try removeBatchDirectory(batch.id)
        var batches = loadBatches()
        batches.removeAll { $0.id == batch.id }
        try saveBatches(batches)
    }

    static func permanentlyDelete(_ batch: StorageCleanupTrashBatch) throws {
        do {
            try removeBatchDirectory(batch.id)
            var batches = loadBatches()
            batches.removeAll { $0.id == batch.id }
            try saveBatches(batches)
        } catch {
            throw StorageCleanupTrashError.permanentDeleteFailed(batch.summary)
        }
    }

    static func purgeExpiredBatches(now: Date) -> Int {
        let batches = loadBatches()
        let expired = batches.filter { $0.expiresAt <= now }
        guard !expired.isEmpty else { return 0 }

        for batch in expired {
            try? removeBatchDirectory(batch.id)
        }
        let active = batches.filter { $0.expiresAt > now }
        do {
            try saveBatches(active)
        } catch {
            StorageIssueLog.recordEvent(
                "storage_cleanup.trash_manifest_update_failed",
                category: .dataStore,
                details: [
                    "source": "StorageCleanupTrashStore.purgeExpiredBatches",
                    "expired_count": "\(expired.count)"
                ],
                error: error
            )
        }
        return expired.count
    }

    private static func saveBatches(_ batches: [StorageCleanupTrashBatch]) throws {
        guard let rootURL, let manifestURL else { throw StorageCleanupTrashError.rootUnavailable }
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(batches.sorted { lhs, rhs in lhs.createdAt > rhs.createdAt })
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            throw StorageCleanupTrashError.manifestWriteFailed
        }
    }

    private static func trashSources(for plan: DeferredProjectFileCleanupPlan) -> [StorageCleanupTrashSource] {
        var sources: [StorageCleanupTrashSource] = []
        sources += plan.photoFileNames.sorted().flatMap { fileName in
            [
                StorageCleanupTrashSource(kind: .photoOriginal, fileName: fileName),
                StorageCleanupTrashSource(kind: .photoThumbnail, fileName: fileName)
            ]
        }
        sources += plan.quickNoteAttachmentFileNames.sorted().map {
            StorageCleanupTrashSource(kind: .quickNoteAttachment, fileName: $0)
        }
        sources += plan.projectDocumentFileNames.sorted().map {
            StorageCleanupTrashSource(kind: .projectDocument, fileName: $0)
        }
        sources += plan.drawingFileNames.sorted().map { fileName in
            StorageCleanupTrashSource(kind: .drawing, fileName: fileName)
        }
        return sources
    }

    private static func moveToTrash(
        _ source: StorageCleanupTrashSource,
        batchID: UUID
    ) throws -> StorageCleanupTrashFile? {
        let sourceURL = source.kind.originalURL(for: source.fileName)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }

        guard let destinationURL = trashURL(
            batchID: batchID,
            kind: source.kind,
            trashedFileName: "\(UUID().uuidString)-\(source.fileName)"
        ) else {
            throw StorageCleanupTrashError.rootUnavailable
        }

        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            source.kind.invalidateCache(for: source.fileName)
            return StorageCleanupTrashFile(
                id: UUID(),
                kind: source.kind,
                originalFileName: source.fileName,
                trashedFileName: destinationURL.lastPathComponent
            )
        } catch {
            throw StorageCleanupTrashError.moveToTrashFailed(source.fileName)
        }
    }

    private static func restore(file: StorageCleanupTrashFile, batchID: UUID) throws {
        guard let trashedURL = trashURL(
            batchID: batchID,
            kind: file.kind,
            trashedFileName: file.trashedFileName
        ) else {
            throw StorageCleanupTrashError.rootUnavailable
        }

        let originalURL = file.kind.originalURL(for: file.originalFileName)
        let manager = FileManager.default
        guard manager.fileExists(atPath: trashedURL.path) else {
            if manager.fileExists(atPath: originalURL.path) {
                file.kind.invalidateCache(for: file.originalFileName)
                return
            }
            throw StorageCleanupTrashError.restoreFailed(file.originalFileName)
        }

        do {
            try manager.createDirectory(
                at: originalURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if manager.fileExists(atPath: originalURL.path) {
                _ = try FileOps.removeIfExists(
                    at: trashedURL,
                    context: .init(
                        event: "storage_cleanup.trash_restore_cleanup",
                        category: .fileStorage,
                        source: "StorageCleanupTrashStore.restore"
                    )
                )
            } else {
                try manager.moveItem(at: trashedURL, to: originalURL)
            }
            file.kind.invalidateCache(for: file.originalFileName)
        } catch {
            throw StorageCleanupTrashError.restoreFailed(file.originalFileName)
        }
    }

    private static func rollback(files: [StorageCleanupTrashFile], batchID: UUID) {
        for file in files.reversed() {
            try? restore(file: file, batchID: batchID)
        }
        try? removeBatchDirectory(batchID)
    }

    private static func trashURL(
        batchID: UUID,
        kind: StorageCleanupTrashFileKind,
        trashedFileName: String
    ) -> URL? {
        rootURL?
            .appendingPathComponent(batchID.uuidString, isDirectory: true)
            .appendingPathComponent(kind.rawValue, isDirectory: true)
            .appendingPathComponent(trashedFileName)
    }

    private static func removeBatchDirectory(_ batchID: UUID) throws {
        guard let batchURL = rootURL?.appendingPathComponent(batchID.uuidString, isDirectory: true) else {
            throw StorageCleanupTrashError.rootUnavailable
        }
        guard FileManager.default.fileExists(atPath: batchURL.path) else { return }
        do {
            _ = try FileOps.removeIfExists(
                at: batchURL,
                context: .init(
                    event: "storage_cleanup.trash_batch_remove",
                    category: .fileStorage,
                    source: "StorageCleanupTrashStore.removeBatchDirectory"
                )
            )
        } catch {
            throw StorageCleanupTrashError.permanentDeleteFailed(batchID.uuidString)
        }
    }
}

private struct StorageCleanupTrashSource {
    let kind: StorageCleanupTrashFileKind
    let fileName: String
}

enum StorageCleanupTrashRetentionOption: Int, CaseIterable, Identifiable {
    case days3 = 3
    case days7 = 7
    case days14 = 14
    case days30 = 30

    static let defaultDays = Self.days7.rawValue

    var id: Int { rawValue }
    var days: Int { rawValue }
    var displayName: String {
        String(format: String(localized: "%lld 天"), Int64(rawValue))
    }

    static func normalizedDays(_ days: Int) -> Int {
        allCases.min { lhs, rhs in
            abs(lhs.rawValue - days) < abs(rhs.rawValue - days)
        }?.rawValue ?? defaultDays
    }
}

enum StorageCleanupLargeFileThresholdOption: Int, CaseIterable, Identifiable {
    case mb5 = 5
    case mb20 = 20
    case mb50 = 50
    case mb100 = 100

    static let defaultMegabytes = Self.mb5.rawValue

    var id: Int { rawValue }
    var megabytes: Int { rawValue }
    var bytes: Int { rawValue * 1024 * 1024 }
    var displayName: String { QuickNoteAttachmentStorage.formattedFileSize(bytes) }

    static func bytes(for megabytes: Int) -> Int {
        normalizedMegabytes(megabytes) * 1024 * 1024
    }

    static func normalizedMegabytes(_ megabytes: Int) -> Int {
        allCases.min { lhs, rhs in
            abs(lhs.rawValue - megabytes) < abs(rhs.rawValue - megabytes)
        }?.rawValue ?? defaultMegabytes
    }
}

enum StorageCleanupLargeFileRuleSuggestion {
    case photo
    case video
    case ticket

    var bytes: Int {
        switch self {
        case .photo:
            return 5 * 1024 * 1024
        case .video:
            return 50 * 1024 * 1024
        case .ticket:
            return 20 * 1024 * 1024
        }
    }
}
