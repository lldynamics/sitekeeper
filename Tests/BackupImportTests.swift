import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct BackupImportTests {
    @Test func cloudBackupOptionsNormalizationDisablesDependentScopes() {
        let options = CloudBackupContentOptions(
            includeBusinessRecords: true,
            includeProjectRecords: false,
            includeProjectFilesAndNotes: true,
            includeKnowledgeBase: true,
            includeAttachments: true
        ).normalized()

        #expect(options.includeProjectFilesAndNotes == false)
        #expect(options.includeAttachments == false)
    }

    @Test func cloudBackupWithoutAttachmentsRemovesAttachmentReferences() {
        let projectId = UUID()
        let snapshot = BackupSnapshot(
            materialItems: [MaterialItem(name: "线管", quantity: "1", unit: "根", projectId: nil)],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "测试项目", location: "A区", status: .active)],
            dailyLogs: [
                DailyLog(
                    date: "2026-05-01",
                    weather: "晴",
                    content: "施工记录",
                    workers: "2",
                    photos: [LogPhoto(fileName: "log-photo.jpg")],
                    projectId: projectId
                )
            ],
            historyRecords: [],
            siteTodos: [
                SiteTodo(
                    title: "整改",
                    rectificationBeforePhotoFileName: "todo-before.jpg",
                    rectificationAfterPhotoFileName: "todo-after.jpg",
                    projectId: projectId
                )
            ],
            projectDrawings: [
                ProjectDrawing(projectId: projectId, name: "图纸", fileName: "drawing.pdf", fileType: "pdf")
            ],
            projectDocuments: [
                ProjectDocument(projectId: projectId, title: "票据", fileName: "document.pdf")
            ],
            quickNotes: [
                QuickNote(
                    projectId: projectId,
                    attachments: [QuickNoteAttachment(kind: .file, fileName: "note.bin")]
                )
            ],
            templates: [ProjectTemplate(name: "模板", category: .quotation, content: "内容")],
            photoFiles: [
                PhotoBackupFile(fileName: "log-photo.jpg", data: Data([0x01])),
                PhotoBackupFile(fileName: "todo-before.jpg", data: Data([0x02]))
            ],
            drawingFiles: [DrawingBackupFile(fileName: "drawing.pdf", data: Data([0x03]))],
            documentFiles: [ProjectDocumentBackupFile(fileName: "document.pdf", data: Data([0x04]))],
            quickNoteAttachmentFiles: [QuickNoteAttachmentBackupFile(fileName: "note.bin", data: Data([0x05]))]
        )

        let filtered = snapshot.applyingCloudBackupContentOptions(
            CloudBackupContentOptions(
                includeBusinessRecords: true,
                includeProjectRecords: true,
                includeProjectFilesAndNotes: true,
                includeKnowledgeBase: true,
                includeAttachments: false
            )
        )

        #expect(filtered.dailyLogs.first?.allPhotoFileNames.isEmpty == true)
        #expect(filtered.siteTodos.first?.rectificationBeforePhotoFileName == nil)
        #expect(filtered.siteTodos.first?.rectificationAfterPhotoFileName == nil)
        #expect(filtered.quickNotes.first?.attachments.isEmpty == true)
        #expect(filtered.projectDrawings.first?.fileName.isEmpty == true)
        #expect(filtered.projectDocuments.first?.fileName.isEmpty == true)
        #expect(filtered.photoFiles.isEmpty)
        #expect(filtered.drawingFiles.isEmpty)
        #expect(filtered.documentFiles.isEmpty)
        #expect(filtered.quickNoteAttachmentFiles.isEmpty)
    }

    @Test func cloudBackupWithoutAttachmentsWritesNoEmbeddedFilesToArchive() throws {
        let projectID = UUID()
        let photoFileName = try PhotoStorage.saveOrThrow(
            original: BackupImportExportTestSupport.makeJPEGData(),
            fileName: "cloud-no-attachment-\(UUID().uuidString).jpg"
        )
        let drawing = try DrawingStorage.saveImportedDataOrThrow(
            data: Data([0x21, 0x22]),
            sourceFileName: "cloud-no-attachment.dwg",
            projectId: projectID
        )
        let documentFileName = try ProjectDocumentStorage.saveDataOrThrow(
            data: Data([0x31, 0x32]),
            projectId: projectID,
            fileExtension: "pdf"
        )
        let attachmentFileName = try QuickNoteAttachmentStorage.saveDataOrThrow(
            Data([0x41, 0x42]),
            fileName: "cloud-no-attachment-\(UUID().uuidString).bin"
        )

        defer {
            PhotoStorage.delete(fileNames: [photoFileName])
            DrawingStorage.delete(fileName: drawing.fileName)
            ProjectDocumentStorage.delete(fileName: documentFileName)
            QuickNoteAttachmentStorage.delete(fileName: attachmentFileName)
        }

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectID, name: "云备份附件边界", location: "现场", status: .active)],
            dailyLogs: [
                DailyLog(
                    date: "2026-07-11",
                    weather: "晴",
                    content: "附件边界",
                    workers: "1",
                    photos: [LogPhoto(fileName: photoFileName)],
                    projectId: projectID
                )
            ],
            historyRecords: [],
            projectDrawings: [drawing],
            projectDocuments: [
                ProjectDocument(projectId: projectID, title: "附件票据", fileName: documentFileName)
            ],
            quickNotes: [
                QuickNote(
                    projectId: projectID,
                    attachments: [QuickNoteAttachment(kind: .file, fileName: attachmentFileName)]
                )
            ],
            templates: []
        )
        let filtered = snapshot.applyingCloudBackupContentOptions(
            CloudBackupContentOptions(
                includeBusinessRecords: true,
                includeProjectRecords: true,
                includeProjectFilesAndNotes: true,
                includeKnowledgeBase: true,
                includeAttachments: false
            )
        )
        let archive = try BackupArchiveService.makeArchive(from: filtered)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        let preview = try BackupArchiveService.previewBackup(from: archive.fileURL)
        #expect(preview.photoFileCount == 0)
        #expect(preview.drawingFileCount == 0)
        #expect(preview.documentFileCount == 0)
        #expect(preview.quickNoteAttachmentFileCount == 0)
        #expect(preview.snapshot.dailyLogs.first?.allPhotoFileNames.isEmpty == true)
        #expect(preview.snapshot.projectDrawings.first?.fileName.isEmpty == true)
        #expect(preview.snapshot.projectDocuments.first?.fileName.isEmpty == true)
        #expect(preview.snapshot.quickNotes.first?.attachments.isEmpty == true)
    }

    @Test func cloudBackupStripsLinksToExcludedProjectsDocumentsAndMethods() {
        let projectID = UUID()
        let documentID = UUID()
        let financialRecordID = UUID()
        let methodID = UUID()
        let snapshot = BackupSnapshot(
            materialItems: [MaterialItem(name: "材料", quantity: "1", unit: "项", projectId: projectID)],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectID, name: "项目", location: "现场", status: .active)],
            dailyLogs: [DailyLog(date: "2026-01-01", weather: "晴", content: "记录", workers: "1", linkedConstructionMethodIDs: [methodID], projectId: projectID)],
            historyRecords: [HistoryRecord(tool: "工具", input: "输入", result: "结果", date: "2026-01-01 09:00", projectId: projectID)],
            siteTodos: [SiteTodo(title: "待办", linkedConstructionMethodIDs: [methodID], projectId: projectID)],
            projectFinancialRecords: [
                ProjectFinancialRecord(id: financialRecordID, projectId: projectID, linkedDocumentIds: [documentID])
            ],
            projectDocuments: [
                ProjectDocument(
                    id: documentID,
                    projectId: projectID,
                    title: "票据",
                    fileName: "document.pdf",
                    linkedFinancialRecordId: financialRecordID,
                    linkedConstructionMethodIDs: [methodID]
                )
            ],
            projectWarehouseMovements: [
                ProjectWarehouseMovement(projectId: projectID, linkedDocumentIds: [documentID])
            ],
            templates: [],
            constructionMethods: [ConstructionMethod(id: methodID, title: "工艺")]
        )

        let withoutFilesAndKnowledge = snapshot.applyingCloudBackupContentOptions(
            CloudBackupContentOptions(
                includeBusinessRecords: true,
                includeProjectRecords: true,
                includeProjectFilesAndNotes: false,
                includeKnowledgeBase: false,
                includeAttachments: false
            )
        )
        #expect(withoutFilesAndKnowledge.projectDocuments.isEmpty)
        #expect(withoutFilesAndKnowledge.projectFinancialRecords.first?.linkedDocumentIds.isEmpty == true)
        #expect(withoutFilesAndKnowledge.projectWarehouseMovements.first?.linkedDocumentIds.isEmpty == true)
        #expect(withoutFilesAndKnowledge.dailyLogs.first?.linkedConstructionMethodIDs.isEmpty == true)
        #expect(withoutFilesAndKnowledge.siteTodos.first?.linkedConstructionMethodIDs.isEmpty == true)

        let withoutProjects = snapshot.applyingCloudBackupContentOptions(
            CloudBackupContentOptions(
                includeBusinessRecords: true,
                includeProjectRecords: false,
                includeProjectFilesAndNotes: false,
                includeKnowledgeBase: true,
                includeAttachments: false
            )
        )
        #expect(withoutProjects.projects.isEmpty)
        #expect(withoutProjects.materialItems.first?.projectId == nil)
        #expect(withoutProjects.historyRecords.first?.projectId == nil)
    }

    @Test func backupPreviewFromFileURLLoadsMetadataOnly() throws {
        let projectId = UUID()
        let quickNoteFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x0A, 0x0B]), fileName: "backup-preview-\(UUID().uuidString).bin")
        defer { QuickNoteAttachmentStorage.delete(fileName: quickNoteFile) }

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "预览项目", location: "现场", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            quickNotes: [QuickNote(projectId: projectId, attachments: [QuickNoteAttachment(kind: .file, fileName: quickNoteFile)])],
            templates: []
        )

        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        let preview = try BackupArchiveService.previewBackup(from: archive.fileURL)
        #expect(preview.snapshot.projects.count == 1)
        #expect(preview.quickNoteAttachmentFileCount == 1)
        #expect(preview.snapshot.quickNoteAttachmentFiles.isEmpty)
    }

    @Test func backupDecodeFromFileURLRestoresEmbeddedFiles() throws {
        let projectId = UUID()
        let quickNoteFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x1A, 0x1B, 0x1C]), fileName: "backup-decode-\(UUID().uuidString).bin")
        defer { QuickNoteAttachmentStorage.delete(fileName: quickNoteFile) }

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "解包项目", location: "现场", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            quickNotes: [QuickNote(projectId: projectId, attachments: [QuickNoteAttachment(kind: .file, fileName: quickNoteFile)])],
            templates: []
        )

        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        let restored = try BackupArchiveService.decodeBackup(from: archive.fileURL)
        #expect(restored.projects.count == 1)
        #expect(restored.quickNoteAttachmentFiles.map(\.fileName).contains(quickNoteFile))
    }

    @Test func fixedLegacyBackupZipFixtureStillImports() throws {
        let fixtureURL = try BackupImportExportTestSupport.writeFixedLegacyBackupZipFixture()
        let attachmentFileName = BackupImportExportTestSupport.fixedLegacyBackupZipAttachmentFileName
        let attachmentData = BackupImportExportTestSupport.fixedLegacyBackupZipAttachmentData
        defer {
            try? FileManager.default.removeItem(at: fixtureURL)
            QuickNoteAttachmentStorage.delete(fileName: attachmentFileName)
        }

        QuickNoteAttachmentStorage.delete(fileName: attachmentFileName)

        let preview = try BackupArchiveService.previewBackup(from: fixtureURL)
        #expect(preview.snapshot.projects.first?.name == "旧ZIP样本项目")
        #expect(preview.snapshot.quickNotes.first?.attachments.first?.fileName == attachmentFileName)
        #expect(preview.snapshot.quickNoteAttachmentFiles.isEmpty)
        #expect(preview.quickNoteAttachmentFileCount == 1)

        let decoded = try BackupArchiveService.decodeBackup(from: fixtureURL)
        #expect(decoded.schemaVersion == BackupSnapshot.currentSchemaVersion)
        #expect(decoded.projects.first?.location == "一号楼")
        #expect(decoded.quickNoteAttachmentFiles.first?.fileName == attachmentFileName)
        #expect(decoded.quickNoteAttachmentFiles.first?.data == attachmentData)

        #expect(!QuickNoteAttachmentStorage.exists(fileName: attachmentFileName))
        let restored = try BackupArchiveService.restoreEmbeddedFiles(from: fixtureURL)
        #expect(restored.quickNoteAttachmentFileCount == 1)
        #expect(QuickNoteAttachmentStorage.data(for: attachmentFileName) == attachmentData)
    }

    @Test func backupRestoreEmbeddedFilesStreamsFromZip() throws {
        let projectId = UUID()
        let quickNoteFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x2A, 0x2B, 0x2C]), fileName: "backup-stream-\(UUID().uuidString).bin")

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "流式恢复项目", location: "现场", status: .active)],
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

        QuickNoteAttachmentStorage.delete(fileName: quickNoteFile)
        #expect(QuickNoteAttachmentStorage.exists(fileName: quickNoteFile) == false)

        let restored = try BackupArchiveService.restoreEmbeddedFiles(from: archive.fileURL)
        #expect(restored.quickNoteAttachmentFileCount == 1)
        #expect(QuickNoteAttachmentStorage.exists(fileName: quickNoteFile))
    }

    @Test func backupPrepareEmbeddedFileRestoreDoesNotCommitBeforeTransactionCommit() throws {
        let projectId = UUID()
        let quickNoteFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x6A, 0x6B]), fileName: "backup-transaction-\(UUID().uuidString).bin")

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "事务恢复项目", location: "现场", status: .active)],
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

        QuickNoteAttachmentStorage.delete(fileName: quickNoteFile)
        #expect(QuickNoteAttachmentStorage.exists(fileName: quickNoteFile) == false)

        let transaction = try BackupArchiveService.prepareEmbeddedFileRestore(from: archive.fileURL)
        #expect(transaction.counts.quickNoteAttachmentFileCount == 1)
        #expect(QuickNoteAttachmentStorage.exists(fileName: quickNoteFile) == false)

        let restored = try transaction.commit()
        #expect(restored.quickNoteAttachmentFileCount == 1)
        #expect(QuickNoteAttachmentStorage.exists(fileName: quickNoteFile))
    }

    @Test func backupRestoreEmbeddedFilesHandlesSampleZipEntry() throws {
        try BackupImportExportTestSupport.assertEmbeddedRestoreRoundtrip(
            targetSize: 2 * 1024 * 1024,
            filePrefix: "backup-stream-sample"
        )
    }

    @Test func backupRestoreEmbeddedFilesHandlesLargeZipEntry() throws {
        guard BackupImportExportTestSupport.shouldRunLargeBackupStressTests else { return }
        try BackupImportExportTestSupport.assertEmbeddedRestoreRoundtrip(
            targetSize: 32 * 1024 * 1024,
            filePrefix: "backup-large-stream"
        )
    }
}
