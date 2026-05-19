import SwiftUI

struct StorageCleanupUndoSnapshot: Codable {
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

struct DeferredProjectFileCleanupPlan: Codable {
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

struct StorageCleanupTrashBatch: Identifiable, Codable {
    let id: UUID
    let summary: String
    let createdAt: Date
    let expiresAt: Date
    let snapshot: StorageCleanupUndoSnapshot
    let files: [StorageCleanupTrashFile]

    var fileCount: Int { files.count }
}

struct StorageCleanupTrashFile: Identifiable, Codable {
    let id: UUID
    let kind: StorageCleanupTrashFileKind
    let originalFileName: String
    let trashedFileName: String
}

enum StorageCleanupTrashFileKind: String, Codable {
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
            StorageIssueLog.record(
                String(format: String(localized: "清理回收站清单读取失败：%@"), error.localizedDescription)
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
            StorageIssueLog.record(
                String(format: String(localized: "清理回收站过期清单更新失败：%@"), error.localizedDescription)
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
        sources += plan.drawingFileNames.sorted().flatMap { fileName in
            ([fileName] + DrawingStorage.sidecarFileNames(for: fileName)).map {
                StorageCleanupTrashSource(kind: .drawing, fileName: $0)
            }
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
    case cad
    case ticket
    case backup
    case history

    var displayName: String {
        switch self {
        case .photo:
            return String(localized: "照片")
        case .video:
            return String(localized: "视频")
        case .cad:
            return String(localized: "CAD")
        case .ticket:
            return String(localized: "票据")
        case .backup:
            return String(localized: "备份")
        case .history:
            return String(localized: "历史计算")
        }
    }

    var icon: String {
        switch self {
        case .photo:
            return "photo.fill"
        case .video:
            return "video.fill"
        case .cad:
            return "compass.drawing"
        case .ticket:
            return "doc.text.fill"
        case .backup:
            return "externaldrive.fill"
        case .history:
            return "clock.arrow.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .photo:
            return .appWarning
        case .video:
            return .appPhoto
        case .cad:
            return .appDoc
        case .ticket:
            return .appRisk
        case .backup:
            return .appPrimaryAction
        case .history:
            return .appSuccess
        }
    }
}

struct ProjectStorageUsage: Identifiable {
    let projectId: UUID
    let projectName: String
    let photoBytes: Int
    let videoBytes: Int
    let cadBytes: Int
    let ticketBytes: Int
    let backupEstimatedBytes: Int?

    var id: UUID { projectId }
    var totalBytes: Int { photoBytes + videoBytes + cadBytes + ticketBytes }
    var formattedTotalBytes: String { QuickNoteAttachmentStorage.formattedFileSize(totalBytes) }
    var formattedBackupEstimatedBytes: String {
        guard let backupEstimatedBytes else { return String(localized: "计算中…") }
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
    case cad
    case tickets
    case all

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .photos:
            return String(localized: "照片")
        case .videos:
            return String(localized: "视频")
        case .cad:
            return String(localized: "CAD 图纸")
        case .tickets:
            return String(localized: "票据资料")
        case .all:
            return String(localized: "全部可清理文件")
        }
    }

    var resultTitle: String {
        switch self {
        case .photos:
            return String(localized: "照片")
        case .videos:
            return String(localized: "视频")
        case .cad:
            return String(localized: "CAD 图纸")
        case .tickets:
            return String(localized: "票据资料")
        case .all:
            return String(localized: "项目文件")
        }
    }

    var icon: String {
        switch self {
        case .photos:
            return "photo.fill"
        case .videos:
            return "video.fill"
        case .cad:
            return "compass.drawing"
        case .tickets:
            return "doc.text.fill"
        case .all:
            return "trash"
        }
    }

    var tint: Color {
        switch self {
        case .photos:
            return .appWarning
        case .videos:
            return .appPhoto
        case .cad:
            return .appDoc
        case .tickets:
            return .appRisk
        case .all:
            return .red
        }
    }

    var confirmationButtonTitle: String {
        switch self {
        case .all:
            return String(localized: "清理全部")
        default:
            return String(format: String(localized: "清理%@"), displayName)
        }
    }

    func confirmationMessage(projectName: String) -> String {
        switch self {
        case .photos:
            return String(format: String(localized: "将清理 %@ 日志和待办整改中的照片原文件，并断开照片关联。文本记录会保留。"), projectName)
        case .videos:
            return String(format: String(localized: "将清理 %@ 随手记视频和资料中的视频原文件，并断开视频关联。"), projectName)
        case .cad:
            return String(format: String(localized: "将清理 %@ 的 CAD 图纸原文件和图纸索引。"), projectName)
        case .tickets:
            return String(format: String(localized: "将清理 %@ 的发票、收据和付款申请资料原文件，并断开财务/仓库关联。"), projectName)
        case .all:
            return String(format: String(localized: "将清理 %@ 的照片、视频、CAD 图纸和票据资料原文件，保留其他文本记录。"), projectName)
        }
    }
}

struct ProjectStorageCleanupDetailView: View {
    let usage: ProjectStorageUsage
    let onCleanup: (ProjectStorageCleanupCategory) -> Void

    var body: some View {
        List {
            Section(String(localized: "占用汇总")) {
                usageRow(title: String(localized: "照片"), icon: "photo.fill", tint: .appWarning, bytes: usage.photoBytes)
                usageRow(title: String(localized: "视频"), icon: "video.fill", tint: .appPhoto, bytes: usage.videoBytes)
                usageRow(title: String(localized: "CAD 图纸"), icon: "compass.drawing", tint: .appDoc, bytes: usage.cadBytes)
                usageRow(title: String(localized: "票据资料"), icon: "doc.text.fill", tint: .appRisk, bytes: usage.ticketBytes)
                usageRow(title: String(localized: "备份估算"), icon: "externaldrive.fill", tint: .appPrimaryAction, bytesText: usage.formattedBackupEstimatedBytes)
            }

            Section {
                HStack {
                    Text(String(localized: "项目总占用"))
                    Spacer()
                    Text(usage.formattedTotalBytes)
                        .font(.subheadline.weight(.semibold))
                }
            }

            Section {
                cleanupButton(.photos, bytes: usage.photoBytes)
                cleanupButton(.videos, bytes: usage.videoBytes)
                cleanupButton(.cad, bytes: usage.cadBytes)
                cleanupButton(.tickets, bytes: usage.ticketBytes)
            } header: {
                Text(String(localized: "按类型清理"))
            } footer: {
                Text(String(localized: "分项清理只处理对应文件类型，项目文本、金额、日志正文不会删除。"))
            }

            Section {
                Button(role: .destructive) {
                    onCleanup(.all)
                } label: {
                    Label(String(localized: "清理该项目全部可清理文件"), systemImage: "trash")
                }
                .disabled(usage.totalBytes == 0)
            } footer: {
                Text(String(localized: "备份是全局快照，不会按单个项目直接删除；如需释放备份空间，请回到“数据管理 → 备份”处理。"))
            }
        }
        .navigationTitle(usage.projectName)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func cleanupButton(_ category: ProjectStorageCleanupCategory, bytes: Int) -> some View {
        Button(role: .destructive) {
            onCleanup(category)
        } label: {
            HStack(spacing: AppSpacing.tight) {
                Image(systemName: category.icon)
                    .foregroundStyle(category.tint)
                    .frame(width: 18, height: 18)
                Text(String(format: String(localized: "清理%@"), category.displayName))
                Spacer()
                Text(QuickNoteAttachmentStorage.formattedFileSize(bytes))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(bytes == 0)
    }

    @ViewBuilder
    private func usageRow(title: String, icon: String, tint: Color, bytes: Int) -> some View {
        usageRow(title: title, icon: icon, tint: tint, bytesText: QuickNoteAttachmentStorage.formattedFileSize(bytes))
    }

    @ViewBuilder
    private func usageRow(title: String, icon: String, tint: Color, bytesText: String) -> some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
            Text(title)
            Spacer()
            Text(bytesText)
                .font(.caption.weight(.semibold))
        }
    }
}

struct StorageOptionalInlineTitleModifier: ViewModifier {
    let isEnabled: Bool
    let title: String

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}
