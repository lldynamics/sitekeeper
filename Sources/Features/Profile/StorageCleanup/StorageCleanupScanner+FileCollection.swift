import Foundation

@MainActor
extension StorageCleanupScanner {
    static func scanPhotoEntries(store: DataStore) -> [StorageLargeFileItem] {
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
                        detail: log.date.storageText,
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
                (todo.rectificationBeforePhotoFileName, AppLocalization.string("整改前")),
                (todo.rectificationAfterPhotoFileName, AppLocalization.string("整改后"))
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

    static func scanVideoEntries(
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
                        detail: note.title.isEmpty ? note.createdAt.storageText : note.title,
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

    static func scanDrawingSourceEntries(
        store: DataStore,
        drawingFileExtensions: Set<String>
    ) -> [StorageLargeFileItem] {
        store.projectDrawings.compactMap { drawing in
            let ext = drawing.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard drawingFileExtensions.contains(ext) else { return nil }
            let bytes = DrawingStorage.fileSize(for: drawing.fileName)
            guard bytes > 0 else { return nil }
            return StorageLargeFileItem(
                id: "drawing-\(drawing.fileName)",
                category: .drawing,
                title: drawing.name.isEmpty ? drawing.fileName : drawing.name,
                detail: "\(drawing.version) · \(drawing.fileName)",
                projectId: drawing.projectId,
                projectName: projectName(for: drawing.projectId, projects: store.projects),
                bytes: bytes
            )
        }
    }

    static func scanTicketEntries(store: DataStore) -> [StorageLargeFileItem] {
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

    static func scanBackupEntries(cloudBackups: [CloudBackupFile]) -> [StorageLargeFileItem] {
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
}
