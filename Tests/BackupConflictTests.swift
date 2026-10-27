import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct BackupConflictTests {
    @Test func backupMergeRenamesAcceptedAttachmentWhenLocalFileNameAlreadyExists() async throws {
        let projectID = UUID()
        let localNoteID = UUID()
        let importedNoteID = UUID()
        let sharedFileName = "backup-merge-collision-\(UUID().uuidString).bin"
        let localData = Data([0x41, 0x42])
        let incomingData = Data([0x91, 0x92])
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-merge-collision-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: storageDirectory)
        await store.awaitInitialLoad()
        var importedDestinationFileName: String?

        defer {
            QuickNoteAttachmentStorage.delete(fileName: sharedFileName)
            if let importedDestinationFileName {
                QuickNoteAttachmentStorage.delete(fileName: importedDestinationFileName)
            }
            try? FileManager.default.removeItem(at: storageDirectory)
        }

        let project = Project(id: projectID, name: "同名附件项目", location: "现场", status: .active)
        seedLocalNote(project: project, noteID: localNoteID, fileName: sharedFileName, store: store)
        let previousSnapshot = store.makeSnapshot(includePhotoFiles: false)

        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(incomingData, fileName: sharedFileName)
        let importedSnapshot = incomingNoteSnapshot(project: project, noteID: importedNoteID, fileName: sharedFileName)
        let archive = try BackupArchiveService.makeArchive(from: importedSnapshot)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(localData, fileName: sharedFileName)

        let restoreTransaction = try BackupArchiveService.prepareEmbeddedFileRestore(from: archive.fileURL)
        let counts = try await BackupImportCoordinator.commitAndPersistImport(
            restoreTransaction: restoreTransaction,
            importedSnapshot: importedSnapshot,
            previousSnapshot: previousSnapshot,
            importMode: .merge,
            store: store,
            sourceFileName: archive.fileURL.lastPathComponent
        )

        importedDestinationFileName = store.quickNotes
            .first(where: { $0.id == importedNoteID })?
            .attachments.first?.fileName
        #expect(counts.quickNoteAttachmentFileCount == 1)
        #expect(store.quickNotes.first(where: { $0.id == localNoteID })?.attachments.first?.fileName == sharedFileName)
        #expect(importedDestinationFileName != nil)
        #expect(importedDestinationFileName != sharedFileName)
        #expect(QuickNoteAttachmentStorage.data(for: sharedFileName) == localData)
        if let importedDestinationFileName {
            #expect(QuickNoteAttachmentStorage.data(for: importedDestinationFileName) == incomingData)
        }
    }

    @Test func backupMergeDoesNotOverwriteLocalAttachmentOrRestoreRejectedOrphan() async throws {
        let projectID = UUID()
        let noteID = UUID()
        let localFileName = "backup-merge-local-\(UUID().uuidString).bin"
        let incomingFileName = "backup-merge-incoming-\(UUID().uuidString).bin"
        let localData = Data([0x11, 0x12])
        let incomingData = Data([0x21, 0x22])
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-merge-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: storageDirectory)
        await store.awaitInitialLoad()

        defer {
            QuickNoteAttachmentStorage.delete(fileName: localFileName)
            QuickNoteAttachmentStorage.delete(fileName: incomingFileName)
            try? FileManager.default.removeItem(at: storageDirectory)
        }

        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(localData, fileName: localFileName)
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(incomingData, fileName: incomingFileName)

        let project = Project(id: projectID, name: "合并项目", location: "现场", status: .active)
        let localNote = QuickNote(
            id: noteID,
            projectId: projectID,
            attachments: [QuickNoteAttachment(kind: .file, fileName: localFileName)]
        )
        store.replaceProjects([project])
        store.replaceQuickNotes([localNote])
        let previousSnapshot = store.makeSnapshot(includePhotoFiles: false)

        let importedSnapshot = incomingNoteSnapshot(project: project, noteID: noteID, fileName: incomingFileName)
        let archive = try BackupArchiveService.makeArchive(from: importedSnapshot)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }
        QuickNoteAttachmentStorage.delete(fileName: incomingFileName)

        let restoreTransaction = try BackupArchiveService.prepareEmbeddedFileRestore(from: archive.fileURL)
        let counts = try await BackupImportCoordinator.commitAndPersistImport(
            restoreTransaction: restoreTransaction,
            importedSnapshot: importedSnapshot,
            previousSnapshot: previousSnapshot,
            importMode: .merge,
            store: store,
            sourceFileName: archive.fileURL.lastPathComponent
        )

        #expect(counts.quickNoteAttachmentFileCount == 0)
        #expect(store.quickNotes.first?.attachments.first?.fileName == localFileName)
        #expect(QuickNoteAttachmentStorage.data(for: localFileName) == localData)
        #expect(!QuickNoteAttachmentStorage.exists(fileName: incomingFileName))
    }

    @Test func backupOverwriteImpactListsOnlyExistingFilesRemovedByImportedSnapshot() throws {
        let projectId = UUID()
        let removedPhotoFile = try PhotoStorage.saveOrThrow(original: BackupImportExportTestSupport.makeJPEGData(), fileName: "backup-overwrite-photo-remove-\(UUID().uuidString).jpg")
        let retainedPhotoFile = try PhotoStorage.saveOrThrow(original: BackupImportExportTestSupport.makeJPEGData(), fileName: "backup-overwrite-photo-keep-\(UUID().uuidString).jpg")
        let removedDrawing = try DrawingStorage.saveImportedDataOrThrow(
            data: Data([0x10, 0x11]),
            sourceFileName: "overwrite-remove.dwg",
            projectId: projectId
        )
        let retainedDrawing = try DrawingStorage.saveImportedDataOrThrow(
            data: Data([0x12, 0x13]),
            sourceFileName: "overwrite-keep.dwg",
            projectId: projectId
        )
        let removedDocumentFile = try ProjectDocumentStorage.saveDataOrThrow(data: Data([0x20, 0x21]), projectId: projectId, fileExtension: "pdf")
        let retainedDocumentFile = try ProjectDocumentStorage.saveDataOrThrow(data: Data([0x22, 0x23]), projectId: projectId, fileExtension: "pdf")
        let removedAttachmentFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x30, 0x31]), fileName: "backup-overwrite-attachment-remove-\(UUID().uuidString).bin")
        let retainedAttachmentFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x32, 0x33]), fileName: "backup-overwrite-attachment-keep-\(UUID().uuidString).bin")
        let missingPhotoFile = "backup-overwrite-missing-\(UUID().uuidString).jpg"

        defer {
            PhotoStorage.delete(fileNames: [removedPhotoFile, retainedPhotoFile])
            DrawingStorage.delete(fileName: removedDrawing.fileName)
            DrawingStorage.delete(fileName: retainedDrawing.fileName)
            ProjectDocumentStorage.delete(fileName: removedDocumentFile)
            ProjectDocumentStorage.delete(fileName: retainedDocumentFile)
            QuickNoteAttachmentStorage.delete(fileName: removedAttachmentFile)
            QuickNoteAttachmentStorage.delete(fileName: retainedAttachmentFile)
        }

        let previous = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "覆盖前项目", location: "现场", status: .active)],
            dailyLogs: [
                DailyLog(
                    date: BusinessDateValue(legacyText: "2026-05-03"),
                    weather: "晴",
                    content: "覆盖前日志",
                    workers: NumericInputSupport.quantity("2"),
                    photos: [
                        LogPhoto(fileName: removedPhotoFile),
                        LogPhoto(fileName: retainedPhotoFile),
                        LogPhoto(fileName: missingPhotoFile)
                    ],
                    projectId: projectId
                )
            ],
            historyRecords: [],
            projectDrawings: [removedDrawing, retainedDrawing],
            projectDocuments: [
                ProjectDocument(projectId: projectId, title: "旧票据", fileName: removedDocumentFile),
                ProjectDocument(projectId: projectId, title: "保留票据", fileName: retainedDocumentFile)
            ],
            quickNotes: [
                QuickNote(
                    projectId: projectId,
                    attachments: [
                        QuickNoteAttachment(kind: .file, fileName: removedAttachmentFile),
                        QuickNoteAttachment(kind: .file, fileName: retainedAttachmentFile)
                    ]
                )
            ],
            templates: []
        )
        let imported = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "覆盖后项目", location: "现场", status: .active)],
            dailyLogs: [
                DailyLog(
                    date: BusinessDateValue(legacyText: "2026-05-03"),
                    weather: "晴",
                    content: "覆盖后日志",
                    workers: NumericInputSupport.quantity("2"),
                    photos: [LogPhoto(fileName: retainedPhotoFile)],
                    projectId: projectId
                )
            ],
            historyRecords: [],
            projectDrawings: [retainedDrawing],
            projectDocuments: [ProjectDocument(projectId: projectId, title: "保留票据", fileName: retainedDocumentFile)],
            quickNotes: [QuickNote(projectId: projectId, attachments: [QuickNoteAttachment(kind: .file, fileName: retainedAttachmentFile)])],
            templates: []
        )

        let impact = BackupImportCoordinator.overwrittenLocalFiles(previous: previous, imported: imported)

        #expect(impact.photoFileNames == [removedPhotoFile])
        #expect(impact.drawingFileNames == [removedDrawing.fileName])
        #expect(impact.documentFileNames == [removedDocumentFile])
        #expect(impact.quickNoteAttachmentFileNames == [removedAttachmentFile])
        #expect(!impact.photoFileNames.contains(missingPhotoFile))

        let cleaned = BackupImportCoordinator.cleanupOverwrittenFiles(previous: previous, imported: imported)
        #expect(cleaned == impact)
        #expect(!PhotoStorage.exists(fileName: removedPhotoFile))
        #expect(PhotoStorage.exists(fileName: retainedPhotoFile))
        #expect(!DrawingStorage.exists(fileName: removedDrawing.fileName))
        #expect(DrawingStorage.exists(fileName: retainedDrawing.fileName))
        #expect(!ProjectDocumentStorage.exists(fileName: removedDocumentFile))
        #expect(ProjectDocumentStorage.exists(fileName: retainedDocumentFile))
        #expect(!QuickNoteAttachmentStorage.exists(fileName: removedAttachmentFile))
        #expect(QuickNoteAttachmentStorage.exists(fileName: retainedAttachmentFile))
    }
}

// MARK: - Transaction rollback
extension BackupConflictTests {
    @Test func backupPreparedEmbeddedFileRestoreRollbackRestoresExistingFile() throws {
        let projectId = UUID()
        let quickNoteFile = "backup-transaction-rollback-\(UUID().uuidString).bin"
        let oldData = Data([0x11, 0x22, 0x33])
        let newData = Data([0xAA, 0xBB, 0xCC])
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(newData, fileName: quickNoteFile)

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "事务回滚恢复项目", location: "现场", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            quickNotes: [QuickNote(projectId: projectId, attachments: [QuickNoteAttachment(kind: .file, fileName: quickNoteFile)])],
            templates: []
        )

        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer {
            QuickNoteAttachmentStorage.delete(fileName: quickNoteFile)
            try? FileManager.default.removeItem(at: archive.fileURL)
        }

        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(oldData, fileName: quickNoteFile)
        #expect(QuickNoteAttachmentStorage.data(for: quickNoteFile) == oldData)

        let transaction = try BackupArchiveService.prepareEmbeddedFileRestore(from: archive.fileURL)
        _ = try transaction.commit()
        #expect(QuickNoteAttachmentStorage.data(for: quickNoteFile) == newData)

        transaction.rollback()
        #expect(QuickNoteAttachmentStorage.data(for: quickNoteFile) == oldData)
    }

    @Test func backupPreparedEmbeddedFileRestoreDeinitRollsBackWhenNotFinalized() throws {
        let projectId = UUID()
        let quickNoteFile = "backup-transaction-deinit-\(UUID().uuidString).bin"
        let oldData = Data([0x31, 0x32, 0x33])
        let newData = Data([0xC1, 0xC2, 0xC3])
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(newData, fileName: quickNoteFile)

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "事务释放回滚项目", location: "现场", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            quickNotes: [QuickNote(projectId: projectId, attachments: [QuickNoteAttachment(kind: .file, fileName: quickNoteFile)])],
            templates: []
        )

        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer {
            QuickNoteAttachmentStorage.delete(fileName: quickNoteFile)
            try? FileManager.default.removeItem(at: archive.fileURL)
        }

        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(oldData, fileName: quickNoteFile)
        #expect(QuickNoteAttachmentStorage.data(for: quickNoteFile) == oldData)

        var transaction: BackupArchiveService.EmbeddedFileRestoreTransaction? = try BackupArchiveService.prepareEmbeddedFileRestore(from: archive.fileURL)
        _ = try transaction?.commit()
        #expect(QuickNoteAttachmentStorage.data(for: quickNoteFile) == newData)
        transaction = nil

        #expect(QuickNoteAttachmentStorage.data(for: quickNoteFile) == oldData)
    }
}

private extension BackupConflictTests {
    func seedLocalNote(project: Project, noteID: UUID, fileName: String, store: DataStore) {
        store.replaceProjects([project])
        store.replaceQuickNotes([
            QuickNote(
                id: noteID,
                projectId: project.id,
                attachments: [QuickNoteAttachment(kind: .file, fileName: fileName)]
            )
        ])
    }

    func incomingNoteSnapshot(project: Project, noteID: UUID, fileName: String) -> BackupSnapshot {
        BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [project],
            dailyLogs: [],
            historyRecords: [],
            quickNotes: [
                QuickNote(
                    id: noteID,
                    projectId: project.id,
                    attachments: [QuickNoteAttachment(kind: .file, fileName: fileName)]
                )
            ],
            templates: []
        )
    }
}
