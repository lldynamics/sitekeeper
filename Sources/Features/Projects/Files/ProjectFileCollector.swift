import Foundation

enum ProjectFileCollector {
    @MainActor
    static func items(for projectId: UUID, category: ProjectFileCategory, projectStore: ProjectStore) -> [ProjectFileItem] {
        items(in: ProjectFileCollectionSnapshot(projectId: projectId, projectStore: projectStore), category: category)
    }

    static func items(in snapshot: ProjectFileCollectionSnapshot, category: ProjectFileCategory) -> [ProjectFileItem] {
        switch category {
        case .images:
            return imageItems(in: snapshot)
        case .drawings:
            return drawingItems(in: snapshot)
        case .documents:
            return documentItems(in: snapshot)
        case .quickNoteAttachments:
            return quickNoteAttachmentItems(in: snapshot)
        }
    }

    @MainActor
    static func items(for projectId: UUID, category: ProjectFileCategory, store: DataStore) -> [ProjectFileItem] {
        items(for: projectId, category: category, projectStore: store.projectStore)
    }

    @MainActor
    static func allItems(for projectId: UUID, projectStore: ProjectStore) -> [ProjectFileItem] {
        ProjectFileCategory.allCases.flatMap { category in
            items(for: projectId, category: category, projectStore: projectStore)
        }
    }

    @MainActor
    static func allItems(for projectId: UUID, store: DataStore) -> [ProjectFileItem] {
        allItems(for: projectId, projectStore: store.projectStore)
    }

    @MainActor
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

    @MainActor
    static func count(for projectId: UUID, category: ProjectFileCategory, store: DataStore) -> Int {
        count(for: projectId, category: category, projectStore: store.projectStore)
    }

    private static func imageItems(in snapshot: ProjectFileCollectionSnapshot) -> [ProjectFileItem] {
        var result: [ProjectFileItem] = []

        for log in snapshot.logs {
            for photo in log.photoAttachments {
                result.append(photoItem(
                    id: "log-\(log.id.uuidString)-\(photo.fileName)",
                    title: photo.note.isEmpty ? AppLocalization.string("施工日志照片") : photo.note,
                    subtitle: "\(log.date) · \(photo.tag.displayName)",
                    sortText: log.date,
                    fileName: photo.fileName
                ))
            }
        }

        for todo in snapshot.todos {
            if let fileName = todo.rectificationBeforePhotoFileName {
                result.append(photoItem(
                    id: "todo-before-\(todo.id.uuidString)",
                    title: String(format: AppLocalization.string("%@ · 整改前"), todo.title),
                    subtitle: todo.dueDate.storageText,
                    sortText: todo.dueDate,
                    fileName: fileName
                ))
            }
            if let fileName = todo.rectificationAfterPhotoFileName {
                result.append(photoItem(
                    id: "todo-after-\(todo.id.uuidString)",
                    title: String(format: AppLocalization.string("%@ · 整改后"), todo.title),
                    subtitle: Formatters.displayDateText(todo.completedAt ?? todo.dueDate),
                    sortText: todo.completedAt ?? todo.dueDate,
                    fileName: fileName
                ))
            }
        }

        for note in snapshot.quickNotes {
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

    private static func drawingItems(in snapshot: ProjectFileCollectionSnapshot) -> [ProjectFileItem] {
        snapshot.drawings
            .map { drawing in
                let url = DrawingStorage.fileURL(for: drawing.fileName)
                return ProjectFileItem(
                    id: "drawing-\(drawing.id.uuidString)",
                    title: drawing.name,
                    subtitle: "\(drawing.version) · \(Formatters.displayDateText(drawing.importedAt))",
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

    private static func documentItems(in snapshot: ProjectFileCollectionSnapshot) -> [ProjectFileItem] {
        snapshot.documents
            .map { document in
                let url = ProjectDocumentStorage.fileURL(for: document.fileName)
                return ProjectFileItem(
                    id: "document-\(document.id.uuidString)",
                    title: document.title,
                    subtitle: "\(document.category.displayName) · \(Formatters.displayDateText(document.createdAt))",
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
        let missingFormedDate = document.formedAt.isEmpty
        return (missingResponsible ? 1 : 0) + (missingFormedDate ? 1 : 0)
    }

    private static func quickNoteAttachmentItems(in snapshot: ProjectFileCollectionSnapshot) -> [ProjectFileItem] {
        snapshot.quickNotes
            .flatMap { note in
                note.attachments
                    .filter { ![QuickNoteAttachmentKind.photo, .drawing].contains($0.attachmentKind) }
                    .map { attachment in
                        quickNoteItem(note: note, attachment: attachment, category: .quickNoteAttachments)
                    }
            }
            .sorted { $0.sortDate > $1.sortDate }
    }

    private static func photoItem(id: String, title: String, subtitle: String, sortText: BusinessDateValue, fileName: String) -> ProjectFileItem {
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
            subtitle: "\(Formatters.displayDateText(note.createdAt)) · \(attachment.attachmentKind.title)",
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

    static func parsedDate(from raw: BusinessDateValue) -> Date {
        if let date = Formatters.parseDateOrDateTime(raw) {
            return date
        }
        if let date = Formatters.date.date(from: raw) {
            return date
        }
        return .distantPast
    }
}
