import Foundation

extension ProjectFileCollector {
    struct RecentSeed {
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

    @MainActor
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

    @MainActor
    static func allRecent(for projectId: UUID, limit: Int, store: DataStore) -> [ProjectFileItem] {
        allRecent(for: projectId, limit: limit, projectStore: store.projectStore)
    }

    @MainActor
    private static func recentSeeds(for projectId: UUID, projectStore: ProjectStore) -> [RecentSeed] {
        var seeds: [RecentSeed] = []
        appendLogSeeds(projectStore.dailyLogs(for: projectId), to: &seeds)
        appendTodoSeeds(projectStore.siteTodos(for: projectId), to: &seeds)
        appendQuickNoteSeeds(projectStore.quickNotes(for: projectId), to: &seeds)
        appendDrawingSeeds(projectStore.projectDrawings(for: projectId), to: &seeds)
        appendDocumentSeeds(projectStore.projectDocuments(for: projectId), to: &seeds)
        return seeds
    }

    private static func appendLogSeeds(_ logs: [DailyLog], to seeds: inout [RecentSeed]) {
        for log in logs {
            for photo in log.photoAttachments {
                let fileName = photo.fileName
                let url = PhotoStorage.fileURL(for: fileName)
                seeds.append(
                    RecentSeed(
                        id: "log-\(log.id.uuidString)-\(fileName)",
                        title: photo.note.isEmpty ? AppLocalization.string("施工日志照片") : photo.note,
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
    }

    private static func appendTodoSeeds(_ todos: [SiteTodo], to seeds: inout [RecentSeed]) {
        for todo in todos {
            if let fileName = todo.rectificationBeforePhotoFileName {
                let url = PhotoStorage.fileURL(for: fileName)
                let sortText = todo.dueDate
                seeds.append(
                    RecentSeed(
                        id: "todo-before-\(todo.id.uuidString)",
                        title: String(format: AppLocalization.string("%@ · 整改前"), todo.title),
                        subtitle: Formatters.displayDateText(sortText),
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
                        title: String(format: AppLocalization.string("%@ · 整改后"), todo.title),
                        subtitle: Formatters.displayDateText(sortText),
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
    }

    private static func appendQuickNoteSeeds(_ notes: [QuickNote], to seeds: inout [RecentSeed]) {
        for note in notes {
            for attachment in note.attachments {
                let url = QuickNoteAttachmentStorage.fileURL(for: attachment.fileName)
                let displayName = attachment.displayName == attachment.fileName ? attachment.attachmentKind.title : attachment.displayName
                let sortDate = parsedDate(from: note.createdAt)
                let category: ProjectFileCategory
                switch attachment.attachmentKind {
                case .photo, .drawing: category = .images
                case .video, .audio, .file: category = .quickNoteAttachments
                }
                seeds.append(
                    RecentSeed(
                        id: "quicknote-\(note.id.uuidString)-\(attachment.id.uuidString)",
                        title: displayName,
                        subtitle: "\(Formatters.displayDateText(note.createdAt)) · \(attachment.attachmentKind.title)",
                        fileType: url.pathExtension.isEmpty ? attachment.attachmentKind.title : url.pathExtension,
                        url: url,
                        category: category,
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

    private static func appendDrawingSeeds(_ drawings: [ProjectDrawing], to seeds: inout [RecentSeed]) {
        for drawing in drawings {
            let fileName = drawing.fileName
            let url = DrawingStorage.fileURL(for: fileName)
            seeds.append(
                RecentSeed(
                    id: "drawing-\(drawing.id.uuidString)",
                    title: drawing.name,
                    subtitle: "\(drawing.version) · \(Formatters.displayDateText(drawing.importedAt))",
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
    }

    private static func appendDocumentSeeds(_ documents: [ProjectDocument], to seeds: inout [RecentSeed]) {
        for document in documents {
            let fileName = document.fileName
            let url = ProjectDocumentStorage.fileURL(for: fileName)
            seeds.append(
                RecentSeed(
                    id: "document-\(document.id.uuidString)",
                    title: document.title,
                    subtitle: "\(document.category.displayName) · \(Formatters.displayDateText(document.createdAt))",
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
    }
}
