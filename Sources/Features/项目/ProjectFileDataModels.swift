import SwiftUI
import UIKit
import ImageIO

enum ProjectFileCategory: CaseIterable {
    case images
    case drawings
    case documents
    case quickNoteAttachments

    var title: String {
        switch self {
        case .images: return "图片"
        case .drawings: return "CAD与图纸"
        case .documents: return "票据资料"
        case .quickNoteAttachments: return "随手记附件"
        }
    }

    var description: String {
        switch self {
        case .images: return "施工日志、待办整改、随手记图片"
        case .drawings: return "DWG、DXF、PDF 图纸"
        case .documents: return "发票、收据、合同、施工资料"
        case .quickNoteAttachments: return "视频、语音、文档、表格等附件"
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
        case .images: return .blue
        case .drawings: return .indigo
        case .documents: return .brown
        case .quickNoteAttachments: return .orange
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

    init(projectId: UUID, store: DataStore) {
        imageCount = ProjectFileCollector.count(for: projectId, category: .images, store: store)
        drawingCount = ProjectFileCollector.count(for: projectId, category: .drawings, store: store)
        documentCount = ProjectFileCollector.count(for: projectId, category: .documents, store: store)
        quickNoteAttachmentCount = ProjectFileCollector.count(for: projectId, category: .quickNoteAttachments, store: store)
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

    var formattedSize: String {
        size > 0 ? QuickNoteAttachmentStorage.formattedFileSize(size) : "-"
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

    func loadImage() -> UIImage? {
        switch self {
        case .photo(let fileName):
            return PhotoStorage.thumbnail(for: fileName)
        case .quickNote(let kind, let fileName):
            switch kind {
            case .photo, .drawing:
                guard let data = QuickNoteAttachmentStorage.data(for: fileName) else { return nil }
                return downsampleImage(data, maxPixelSize: 256)
            case .video:
                return QuickNoteAttachmentStorage.videoThumbnail(for: fileName)
            case .audio, .file:
                return nil
            }
        }
    }

    private func downsampleImage(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbnailOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
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

    static func items(for projectId: UUID, category: ProjectFileCategory, store: DataStore) -> [ProjectFileItem] {
        switch category {
        case .images:
            return imageItems(for: projectId, store: store)
        case .drawings:
            return drawingItems(for: projectId, store: store)
        case .documents:
            return documentItems(for: projectId, store: store)
        case .quickNoteAttachments:
            return quickNoteAttachmentItems(for: projectId, store: store)
        }
    }

    static func count(for projectId: UUID, category: ProjectFileCategory, store: DataStore) -> Int {
        switch category {
        case .images:
            let logPhotoCount = store.dailyLogs
                .filter { $0.projectId == projectId }
                .reduce(0) { $0 + $1.photoAttachments.count }
            let todoPhotoCount = store.siteTodos
                .filter { $0.projectId == projectId }
                .reduce(0) { count, todo in
                    count
                        + (todo.rectificationBeforePhotoFileName == nil ? 0 : 1)
                        + (todo.rectificationAfterPhotoFileName == nil ? 0 : 1)
                }
            let quickNotePhotoCount = store.quickNotes
                .filter { $0.projectId == projectId }
                .flatMap(\.attachments)
                .filter { [.photo, .drawing].contains($0.attachmentKind) }
                .count
            return logPhotoCount + todoPhotoCount + quickNotePhotoCount
        case .drawings:
            return store.projectDrawings.filter { $0.projectId == projectId }.count
        case .documents:
            return store.projectDocuments.filter { $0.projectId == projectId }.count
        case .quickNoteAttachments:
            return store.quickNotes
                .filter { $0.projectId == projectId }
                .flatMap(\.attachments)
                .filter { ![QuickNoteAttachmentKind.photo, .drawing].contains($0.attachmentKind) }
                .count
        }
    }

    static func allRecent(for projectId: UUID, limit: Int, store: DataStore) -> [ProjectFileItem] {
        recentSeeds(for: projectId, store: store)
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
                    sortDate: seed.sortDate
                )
            }
    }

    private static func recentSeeds(for projectId: UUID, store: DataStore) -> [RecentSeed] {
        var seeds: [RecentSeed] = []

        for log in store.dailyLogs where log.projectId == projectId {
            for photo in log.photoAttachments {
                let fileName = photo.fileName
                let url = PhotoStorage.fileURL(for: fileName)
                seeds.append(
                    RecentSeed(
                        id: "log-\(log.id.uuidString)-\(fileName)",
                        title: photo.note.isEmpty ? "施工日志照片" : photo.note,
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

        for todo in store.siteTodos where todo.projectId == projectId {
            if let fileName = todo.rectificationBeforePhotoFileName {
                let url = PhotoStorage.fileURL(for: fileName)
                let sortText = todo.dueDate
                seeds.append(
                    RecentSeed(
                        id: "todo-before-\(todo.id.uuidString)",
                        title: "\(todo.title) · 整改前",
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
                        title: "\(todo.title) · 整改后",
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

        for note in store.quickNotes where note.projectId == projectId {
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

        for drawing in store.projectDrawings where drawing.projectId == projectId {
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

        for document in store.projectDocuments where document.projectId == projectId {
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

    private static func imageItems(for projectId: UUID, store: DataStore) -> [ProjectFileItem] {
        var result: [ProjectFileItem] = []

        for log in store.dailyLogs where log.projectId == projectId {
            for photo in log.photoAttachments {
                result.append(photoItem(
                    id: "log-\(log.id.uuidString)-\(photo.fileName)",
                    title: photo.note.isEmpty ? "施工日志照片" : photo.note,
                    subtitle: "\(log.date) · \(photo.tag.displayName)",
                    sortText: log.date,
                    fileName: photo.fileName
                ))
            }
        }

        for todo in store.siteTodos where todo.projectId == projectId {
            if let fileName = todo.rectificationBeforePhotoFileName {
                result.append(photoItem(
                    id: "todo-before-\(todo.id.uuidString)",
                    title: "\(todo.title) · 整改前",
                    subtitle: todo.dueDate,
                    sortText: todo.dueDate,
                    fileName: fileName
                ))
            }
            if let fileName = todo.rectificationAfterPhotoFileName {
                result.append(photoItem(
                    id: "todo-after-\(todo.id.uuidString)",
                    title: "\(todo.title) · 整改后",
                    subtitle: todo.completedAt ?? todo.dueDate,
                    sortText: todo.completedAt ?? todo.dueDate,
                    fileName: fileName
                ))
            }
        }

        for note in store.quickNotes where note.projectId == projectId {
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

    private static func drawingItems(for projectId: UUID, store: DataStore) -> [ProjectFileItem] {
        store.projectDrawings
            .filter { $0.projectId == projectId }
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
                    sortDate: parsedDate(from: drawing.importedAt)
                )
            }
            .sorted { $0.sortDate > $1.sortDate }
    }

    private static func documentItems(for projectId: UUID, store: DataStore) -> [ProjectFileItem] {
        store.projectDocuments
            .filter { $0.projectId == projectId }
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
                    sortDate: parsedDate(from: document.createdAt)
                )
            }
            .sorted { $0.sortDate > $1.sortDate }
    }

    private static func quickNoteAttachmentItems(for projectId: UUID, store: DataStore) -> [ProjectFileItem] {
        store.quickNotes
            .filter { $0.projectId == projectId }
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
            sortDate: parsedDate(from: sortText)
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
            sortDate: parsedDate(from: note.createdAt)
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
