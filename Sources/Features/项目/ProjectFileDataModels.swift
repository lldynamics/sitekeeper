import SwiftUI
import UIKit

enum ProjectFileCategory: CaseIterable {
    case images
    case drawings
    case documents
    case quickNoteAttachments

    var title: String {
        switch self {
        case .images: return String(localized: "project.files.category.images.title")
        case .drawings: return String(localized: "project.files.category.drawings.title")
        case .documents: return String(localized: "project.files.category.documents.title")
        case .quickNoteAttachments: return String(localized: "project.files.category.quickNoteAttachments.title")
        }
    }

    var description: String {
        switch self {
        case .images: return String(localized: "project.files.category.images.description")
        case .drawings: return String(localized: "project.files.category.drawings.description")
        case .documents: return String(localized: "project.files.category.documents.description")
        case .quickNoteAttachments: return String(localized: "project.files.category.quickNoteAttachments.description")
        }
    }

    var systemImage: String {
        switch self {
        case .images: return "photo.on.rectangle"
        case .drawings: return "doc.viewfinder"
        case .documents: return "doc.richtext"
        case .quickNoteAttachments: return "paperclip"
        }
    }

    var tint: Color {
        switch self {
        case .images: return .appDoc
        case .drawings: return .appPrimaryAction
        case .documents: return .appPrimaryAction
        case .quickNoteAttachments: return .appPrimaryAction
        }
    }
}

enum ProjectFileHealthFilter: String, CaseIterable {
    case all
    case missing
    case actionDocuments
    case returnedDocuments
    case unarchivedDocuments
    case incompleteDocumentLedger
    case largeFiles

    var title: String {
        switch self {
        case .all: return String(localized: "project.files.healthFilter.all")
        case .missing: return String(localized: "project.files.healthFilter.missing")
        case .actionDocuments: return String(localized: "project.files.healthFilter.actionDocuments")
        case .returnedDocuments: return String(localized: "project.files.healthFilter.returnedDocuments")
        case .unarchivedDocuments: return String(localized: "project.files.healthFilter.unarchivedDocuments")
        case .incompleteDocumentLedger: return String(localized: "project.files.healthFilter.incompleteDocumentLedger")
        case .largeFiles: return String(localized: "project.files.healthFilter.largeFiles")
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .missing: return "exclamationmark.triangle.fill"
        case .actionDocuments: return "clock.badge.exclamationmark"
        case .returnedDocuments: return "arrow.uturn.backward.circle.fill"
        case .unarchivedDocuments: return "archivebox"
        case .incompleteDocumentLedger: return "list.clipboard"
        case .largeFiles: return "externaldrive.badge.exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .all: return .appPrimaryAction
        case .missing, .returnedDocuments, .largeFiles: return .appRisk
        case .actionDocuments, .unarchivedDocuments, .incompleteDocumentLedger: return .appWarning
        }
    }

    func matches(_ item: ProjectFileItem) -> Bool {
        switch self {
        case .all:
            return true
        case .missing:
            return !item.exists
        case .actionDocuments:
            return item.documentStatus?.requiresArchiveAttention == true
        case .returnedDocuments:
            return item.documentStatus == .returned
        case .unarchivedDocuments:
            guard let status = item.documentStatus else { return false }
            return status != .archived
        case .incompleteDocumentLedger:
            return item.documentLedgerIssueCount > 0
        case .largeFiles:
            return item.isLargeFile
        }
    }
}

@MainActor
struct ProjectFileSummary {
    let imageCount: Int
    let drawingCount: Int
    let documentCount: Int
    let quickNoteAttachmentCount: Int

    var totalCount: Int {
        imageCount + drawingCount + documentCount + quickNoteAttachmentCount
    }

    init(projectId: UUID, projectStore: ProjectStore) {
        imageCount = ProjectFileCollector.count(for: projectId, category: .images, projectStore: projectStore)
        drawingCount = ProjectFileCollector.count(for: projectId, category: .drawings, projectStore: projectStore)
        documentCount = ProjectFileCollector.count(for: projectId, category: .documents, projectStore: projectStore)
        quickNoteAttachmentCount = ProjectFileCollector.count(for: projectId, category: .quickNoteAttachments, projectStore: projectStore)
    }

    init(projectId: UUID, store: DataStore) {
        self.init(projectId: projectId, projectStore: store.projectStore)
    }

    func count(for category: ProjectFileCategory) -> Int {
        switch category {
        case .images: return imageCount
        case .drawings: return drawingCount
        case .documents: return documentCount
        case .quickNoteAttachments: return quickNoteAttachmentCount
        }
    }
}

struct ProjectFileItem: Identifiable {
    static let largeFileWarningBytes = 100 * 1024 * 1024

    let id: String
    let title: String
    let subtitle: String
    let fileType: String
    let url: URL
    let exists: Bool
    let size: Int
    let category: ProjectFileCategory
    let systemImage: String
    let thumbnailToken: ProjectFileThumbnailToken?
    let sortDate: Date
    let documentStatus: ProjectDocumentSubmissionStatus?
    var documentLedgerIssueCount = 0

    var formattedSize: String {
        size > 0 ? QuickNoteAttachmentStorage.formattedFileSize(size) : "-"
    }

    var isLargeFile: Bool {
        size >= Self.largeFileWarningBytes
    }

    var hasDocumentLedgerIssues: Bool {
        documentLedgerIssueCount > 0
    }
}

enum ProjectFileThumbnailToken: Hashable {
    case photo(fileName: String)
    case quickNote(kind: QuickNoteAttachmentKind, fileName: String)

    var cacheKey: String {
        switch self {
        case .photo(let fileName):
            return "photo:\(fileName)"
        case .quickNote(let kind, let fileName):
            return "quick:\(kind.rawValue):\(fileName)"
        }
    }

    func loadImageAsync() async -> UIImage? {
        switch self {
        case .photo(let fileName):
            return await PhotoStorage.thumbnailAsync(for: fileName)
        case .quickNote(let kind, let fileName):
            switch kind {
            case .photo, .drawing:
                guard let data = await QuickNoteAttachmentStorage.dataAsync(for: fileName) else { return nil }
                return await Task.detached(priority: .utility) {
                    ImageDownsampleService.downsampledImage(data, maxPixelSize: 256)
                }.value
            case .video:
                return await Task.detached(priority: .utility) {
                    QuickNoteAttachmentStorage.videoThumbnail(for: fileName)
                }.value
            case .audio, .file:
                return nil
            }
        }
    }
}

enum ProjectFileThumbnailCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

@MainActor
enum ProjectFileCollector {
    private struct RecentSeed {
        let id: String
        let title: String
        let subtitle: String
        let fileType: String
        let url: URL
        let category: ProjectFileCategory
        let systemImage: String
        let sortDate: Date
        let thumbnailToken: ProjectFileThumbnailToken?
        let existsProvider: () -> Bool
        let sizeProvider: () -> Int
    }

    static func items(for projectId: UUID, category: ProjectFileCategory, projectStore: ProjectStore) -> [ProjectFileItem] {
        switch category {
        case .images:
            return imageItems(for: projectId, projectStore: projectStore)
        case .drawings:
            return drawingItems(for: projectId, projectStore: projectStore)
        case .documents:
            return documentItems(for: projectId, projectStore: projectStore)
        case .quickNoteAttachments:
            return quickNoteAttachmentItems(for: projectId, projectStore: projectStore)
        }
    }

    static func items(for projectId: UUID, category: ProjectFileCategory, store: DataStore) -> [ProjectFileItem] {
        items(for: projectId, category: category, projectStore: store.projectStore)
    }

    static func allItems(for projectId: UUID, projectStore: ProjectStore) -> [ProjectFileItem] {
        ProjectFileCategory.allCases.flatMap { category in
            items(for: projectId, category: category, projectStore: projectStore)
        }
    }

    static func allItems(for projectId: UUID, store: DataStore) -> [ProjectFileItem] {
        allItems(for: projectId, projectStore: store.projectStore)
    }

    static func count(for projectId: UUID, category: ProjectFileCategory, projectStore: ProjectStore) -> Int {
        switch category {
        case .images:
            let logPhotoCount = projectStore.dailyLogs(for: projectId)
                .reduce(0) { $0 + $1.photoAttachments.count }
            let todoPhotoCount = projectStore.siteTodos(for: projectId)
                .reduce(0) { count, todo in
                    count
                        + (todo.rectificationBeforePhotoFileName == nil ? 0 : 1)
                        + (todo.rectificationAfterPhotoFileName == nil ? 0 : 1)
                }
            let quickNotePhotoCount = projectStore.quickNotes(for: projectId)
                .flatMap(\.attachments)
                .filter { [.photo, .drawing].contains($0.attachmentKind) }
                .count
            return logPhotoCount + todoPhotoCount + quickNotePhotoCount
        case .drawings:
            return projectStore.projectDrawings(for: projectId).count
        case .documents:
            return projectStore.projectDocuments(for: projectId).count
        case .quickNoteAttachments:
            return projectStore.quickNotes(for: projectId)
                .flatMap(\.attachments)
                .filter { ![QuickNoteAttachmentKind.photo, .drawing].contains($0.attachmentKind) }
                .count
        }
    }

    static func count(for projectId: UUID, category: ProjectFileCategory, store: DataStore) -> Int {
        count(for: projectId, category: category, projectStore: store.projectStore)
    }

    static func allRecent(for projectId: UUID, limit: Int, projectStore: ProjectStore) -> [ProjectFileItem] {
        recentSeeds(for: projectId, projectStore: projectStore)
            .sorted { $0.sortDate > $1.sortDate }
            .prefix(limit)
            .map { seed in
                ProjectFileItem(
                    id: seed.id,
                    title: seed.title,
                    subtitle: seed.subtitle,
                    fileType: seed.fileType,
                    url: seed.url,
                    exists: seed.existsProvider(),
                    size: seed.sizeProvider(),
                    category: seed.category,
                    systemImage: seed.systemImage,
                    thumbnailToken: seed.thumbnailToken,
                    sortDate: seed.sortDate,
                    documentStatus: nil
                )
            }
    }

    static func allRecent(for projectId: UUID, limit: Int, store: DataStore) -> [ProjectFileItem] {
        allRecent(for: projectId, limit: limit, projectStore: store.projectStore)
    }

    private static func recentSeeds(for projectId: UUID, projectStore: ProjectStore) -> [RecentSeed] {
        var seeds: [RecentSeed] = []

        for log in projectStore.dailyLogs(for: projectId) {
            for photo in log.photoAttachments {
                let fileName = photo.fileName
                let url = PhotoStorage.fileURL(for: fileName)
                seeds.append(
                    RecentSeed(
                        id: "log-\(log.id.uuidString)-\(fileName)",
                        title: photo.note.isEmpty ? String(localized: "施工日志照片") : photo.note,
                        subtitle: "\(log.date) · \(photo.tag.displayName)",
                        fileType: url.pathExtension.isEmpty ? "jpg" : url.pathExtension,
                        url: url,
                        category: .images,
                        systemImage: "photo",
                        sortDate: parsedDate(from: log.date),
                        thumbnailToken: .photo(fileName: fileName),
                        existsProvider: { PhotoStorage.exists(fileName: fileName) },
                        sizeProvider: { PhotoStorage.fileSize(for: fileName) }
                    )
                )
            }
        }

        for todo in projectStore.siteTodos(for: projectId) {
            if let fileName = todo.rectificationBeforePhotoFileName {
                let url = PhotoStorage.fileURL(for: fileName)
                let sortText = todo.dueDate
                seeds.append(
                    RecentSeed(
                        id: "todo-before-\(todo.id.uuidString)",
                        title: String(format: String(localized: "%@ · 整改前"), todo.title),
                        subtitle: sortText,
                        fileType: url.pathExtension.isEmpty ? "jpg" : url.pathExtension,
                        url: url,
                        category: .images,
                        systemImage: "photo",
                        sortDate: parsedDate(from: sortText),
                        thumbnailToken: .photo(fileName: fileName),
                        existsProvider: { PhotoStorage.exists(fileName: fileName) },
                        sizeProvider: { PhotoStorage.fileSize(for: fileName) }
                    )
                )
            }
            if let fileName = todo.rectificationAfterPhotoFileName {
                let url = PhotoStorage.fileURL(for: fileName)
                let sortText = todo.completedAt ?? todo.dueDate
                seeds.append(
                    RecentSeed(
                        id: "todo-after-\(todo.id.uuidString)",
                        title: String(format: String(localized: "%@ · 整改后"), todo.title),
                        subtitle: sortText,
                        fileType: url.pathExtension.isEmpty ? "jpg" : url.pathExtension,
                        url: url,
                        category: .images,
                        systemImage: "photo",
                        sortDate: parsedDate(from: sortText),
                        thumbnailToken: .photo(fileName: fileName),
                        existsProvider: { PhotoStorage.exists(fileName: fileName) },
                        sizeProvider: { PhotoStorage.fileSize(for: fileName) }
                    )
                )
            }
        }

        for note in projectStore.quickNotes(for: projectId) {
            for attachment in note.attachments {
                let url = QuickNoteAttachmentStorage.fileURL(for: attachment.fileName)
                let displayName = attachment.displayName == attachment.fileName ? attachment.attachmentKind.title : attachment.displayName
                let sortDate = parsedDate(from: note.createdAt)
                switch attachment.attachmentKind {
                case .photo, .drawing:
                    seeds.append(
                        RecentSeed(
                            id: "quicknote-\(note.id.uuidString)-\(attachment.id.uuidString)",
                            title: displayName,
                            subtitle: "\(note.createdAt) · \(attachment.attachmentKind.title)",
                            fileType: url.pathExtension.isEmpty ? attachment.attachmentKind.title : url.pathExtension,
                            url: url,
                            category: .images,
                            systemImage: attachment.attachmentKind.systemImage,
                            sortDate: sortDate,
                            thumbnailToken: .quickNote(kind: attachment.attachmentKind, fileName: attachment.fileName),
                            existsProvider: { QuickNoteAttachmentStorage.exists(fileName: attachment.fileName) },
                            sizeProvider: { QuickNoteAttachmentStorage.fileSize(for: attachment.fileName) }
                        )
                    )
                case .video, .audio, .file:
                    seeds.append(
                        RecentSeed(
                            id: "quicknote-\(note.id.uuidString)-\(attachment.id.uuidString)",
                            title: displayName,
                            subtitle: "\(note.createdAt) · \(attachment.attachmentKind.title)",
                            fileType: url.pathExtension.isEmpty ? attachment.attachmentKind.title : url.pathExtension,
                            url: url,
                            category: .quickNoteAttachments,
                            systemImage: attachment.attachmentKind.systemImage,
                            sortDate: sortDate,
                            thumbnailToken: .quickNote(kind: attachment.attachmentKind, fileName: attachment.fileName),
                            existsProvider: { QuickNoteAttachmentStorage.exists(fileName: attachment.fileName) },
                            sizeProvider: { QuickNoteAttachmentStorage.fileSize(for: attachment.fileName) }
                        )
                    )
                }
            }
        }

        for drawing in projectStore.projectDrawings(for: projectId) {
            let fileName = drawing.fileName
            let url = DrawingStorage.fileURL(for: fileName)
            seeds.append(
                RecentSeed(
                    id: "drawing-\(drawing.id.uuidString)",
                    title: drawing.name,
                    subtitle: "\(drawing.version) · \(drawing.importedAt)",
                    fileType: drawing.fileType,
                    url: url,
                    category: .drawings,
                    systemImage: ProjectDetailDrawingHelper.drawingIcon(drawing.fileType),
                    sortDate: parsedDate(from: drawing.importedAt),
                    thumbnailToken: nil,
                    existsProvider: { DrawingStorage.exists(fileName: fileName) },
                    sizeProvider: { DrawingStorage.fileSize(for: fileName) }
                )
            )
        }

        for document in projectStore.projectDocuments(for: projectId) {
            let fileName = document.fileName
            let url = ProjectDocumentStorage.fileURL(for: fileName)
            seeds.append(
                RecentSeed(
                    id: "document-\(document.id.uuidString)",
                    title: document.title,
                    subtitle: "\(document.category.displayName) · \(document.createdAt)",
                    fileType: document.fileType,
                    url: url,
                    category: .documents,
                    systemImage: ProjectDetailFinanceDocumentHelper.documentIcon(document.category),
                    sortDate: parsedDate(from: document.createdAt),
                    thumbnailToken: nil,
                    existsProvider: { ProjectDocumentStorage.exists(fileName: fileName) },
                    sizeProvider: { ProjectDocumentStorage.fileSize(for: fileName) }
                )
            )
        }

        return seeds
    }

    private static func imageItems(for projectId: UUID, projectStore: ProjectStore) -> [ProjectFileItem] {
        var result: [ProjectFileItem] = []

        for log in projectStore.dailyLogs(for: projectId) {
            for photo in log.photoAttachments {
                result.append(photoItem(
                    id: "log-\(log.id.uuidString)-\(photo.fileName)",
                    title: photo.note.isEmpty ? String(localized: "施工日志照片") : photo.note,
                    subtitle: "\(log.date) · \(photo.tag.displayName)",
                    sortText: log.date,
                    fileName: photo.fileName
                ))
            }
        }

        for todo in projectStore.siteTodos(for: projectId) {
            if let fileName = todo.rectificationBeforePhotoFileName {
                result.append(photoItem(
                    id: "todo-before-\(todo.id.uuidString)",
                    title: String(format: String(localized: "%@ · 整改前"), todo.title),
                    subtitle: todo.dueDate,
                    sortText: todo.dueDate,
                    fileName: fileName
                ))
            }
            if let fileName = todo.rectificationAfterPhotoFileName {
                result.append(photoItem(
                    id: "todo-after-\(todo.id.uuidString)",
                    title: String(format: String(localized: "%@ · 整改后"), todo.title),
                    subtitle: todo.completedAt ?? todo.dueDate,
                    sortText: todo.completedAt ?? todo.dueDate,
                    fileName: fileName
                ))
            }
        }

        for note in projectStore.quickNotes(for: projectId) {
            for attachment in note.attachments where [.photo, .drawing].contains(attachment.attachmentKind) {
                result.append(quickNoteItem(
                    note: note,
                    attachment: attachment,
                    category: .images,
                    title: attachment.displayName == attachment.fileName ? attachment.attachmentKind.title : attachment.displayName
                ))
            }
        }

        return result.sorted { $0.sortDate > $1.sortDate }
    }

    private static func drawingItems(for projectId: UUID, projectStore: ProjectStore) -> [ProjectFileItem] {
        projectStore.projectDrawings(for: projectId)
            .map { drawing in
                let url = DrawingStorage.fileURL(for: drawing.fileName)
                return ProjectFileItem(
                    id: "drawing-\(drawing.id.uuidString)",
                    title: drawing.name,
                    subtitle: "\(drawing.version) · \(drawing.importedAt)",
                    fileType: drawing.fileType,
                    url: url,
                    exists: DrawingStorage.exists(fileName: drawing.fileName),
                    size: DrawingStorage.fileSize(for: drawing.fileName),
                    category: .drawings,
                    systemImage: ProjectDetailDrawingHelper.drawingIcon(drawing.fileType),
                    thumbnailToken: nil,
                    sortDate: parsedDate(from: drawing.importedAt),
                    documentStatus: nil
                )
            }
            .sorted { $0.sortDate > $1.sortDate }
    }

    private static func documentItems(for projectId: UUID, projectStore: ProjectStore) -> [ProjectFileItem] {
        projectStore.projectDocuments(for: projectId)
            .map { document in
                let url = ProjectDocumentStorage.fileURL(for: document.fileName)
                return ProjectFileItem(
                    id: "document-\(document.id.uuidString)",
                    title: document.title,
                    subtitle: "\(document.category.displayName) · \(document.createdAt)",
                    fileType: document.fileType,
                    url: url,
                    exists: ProjectDocumentStorage.exists(fileName: document.fileName),
                    size: ProjectDocumentStorage.fileSize(for: document.fileName),
                    category: .documents,
                    systemImage: ProjectDetailFinanceDocumentHelper.documentIcon(document.category),
                    thumbnailToken: nil,
                    sortDate: parsedDate(from: document.createdAt),
                    documentStatus: document.submissionStatus,
                    documentLedgerIssueCount: documentLedgerIssueCount(document)
                )
            }
            .sorted { $0.sortDate > $1.sortDate }
    }

    private static func documentLedgerIssueCount(_ document: ProjectDocument) -> Int {
        let missingResponsible = document.responsiblePerson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let missingFormedDate = document.formedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (missingResponsible ? 1 : 0) + (missingFormedDate ? 1 : 0)
    }

    private static func quickNoteAttachmentItems(for projectId: UUID, projectStore: ProjectStore) -> [ProjectFileItem] {
        projectStore.quickNotes(for: projectId)
            .flatMap { note in
                note.attachments
                    .filter { ![QuickNoteAttachmentKind.photo, .drawing].contains($0.attachmentKind) }
                    .map { attachment in
                        quickNoteItem(note: note, attachment: attachment, category: .quickNoteAttachments)
                    }
            }
            .sorted { $0.sortDate > $1.sortDate }
    }

    private static func photoItem(id: String, title: String, subtitle: String, sortText: String, fileName: String) -> ProjectFileItem {
        let url = PhotoStorage.fileURL(for: fileName)
        return ProjectFileItem(
            id: id,
            title: title,
            subtitle: subtitle,
            fileType: url.pathExtension.isEmpty ? "jpg" : url.pathExtension,
            url: url,
            exists: PhotoStorage.exists(fileName: fileName),
            size: PhotoStorage.fileSize(for: fileName),
            category: .images,
            systemImage: "photo",
            thumbnailToken: .photo(fileName: fileName),
            sortDate: parsedDate(from: sortText),
            documentStatus: nil
        )
    }

    private static func quickNoteItem(
        note: QuickNote,
        attachment: QuickNoteAttachment,
        category: ProjectFileCategory,
        title: String? = nil
    ) -> ProjectFileItem {
        let url = QuickNoteAttachmentStorage.fileURL(for: attachment.fileName)
        return ProjectFileItem(
            id: "quicknote-\(note.id.uuidString)-\(attachment.id.uuidString)",
            title: title ?? attachment.displayName,
            subtitle: "\(note.createdAt) · \(attachment.attachmentKind.title)",
            fileType: url.pathExtension.isEmpty ? attachment.attachmentKind.title : url.pathExtension,
            url: url,
            exists: QuickNoteAttachmentStorage.exists(fileName: attachment.fileName),
            size: QuickNoteAttachmentStorage.fileSize(for: attachment.fileName),
            category: category,
            systemImage: attachment.attachmentKind.systemImage,
            thumbnailToken: .quickNote(kind: attachment.attachmentKind, fileName: attachment.fileName),
            sortDate: parsedDate(from: note.createdAt),
            documentStatus: nil
        )
    }

    private static func parsedDate(from raw: String) -> Date {
        if let date = Formatters.dateTime.date(from: raw) {
            return date
        }
        if let date = Formatters.date.date(from: raw) {
            return date
        }
        return .distantPast
    }
}
