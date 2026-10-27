import Testing
import Foundation
@testable import sitekeeper

extension BackupImportTests {
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
        let snapshot = snapshotWithAttachmentReferences()

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

        let snapshot = snapshotWithStoredFiles(
            projectID: projectID, photoFileName: photoFileName, drawing: drawing,
            documentFileName: documentFileName, attachmentFileName: attachmentFileName
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
        let snapshot = snapshotWithLinkedRecords()

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
}

private extension BackupImportTests {
    private func snapshotWithAttachmentReferences() -> BackupSnapshot {
        let projectId = UUID()
        return BackupSnapshot(
            materialItems: [MaterialItem(name: "线管", quantity: NumericInputSupport.quantity("1"), unit: "根", projectId: nil)],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "测试项目", location: "A区", status: .active)],
            dailyLogs: [
                DailyLog(
                    date: BusinessDateValue(legacyText: "2026-05-01"),
                    weather: "晴",
                    content: "施工记录",
                    workers: NumericInputSupport.quantity("2"),
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
    }

    private func snapshotWithLinkedRecords() -> BackupSnapshot {
        let projectID = UUID()
        let documentID = UUID()
        let financialRecordID = UUID()
        let methodID = UUID()
        return BackupSnapshot(
            materialItems: [MaterialItem(name: "材料", quantity: NumericInputSupport.quantity("1"), unit: "项", projectId: projectID)],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectID, name: "项目", location: "现场", status: .active)],
            dailyLogs: [DailyLog(date: BusinessDateValue(legacyText: "2026-01-01"), weather: "晴", content: "记录", workers: NumericInputSupport.quantity("1"), linkedConstructionMethodIDs: [methodID], projectId: projectID)],
            historyRecords: [HistoryRecord(tool: "工具", input: "输入", result: "结果", date: BusinessDateValue(legacyText: "2026-01-01 09:00"), projectId: projectID)],
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
    }

    private func snapshotWithStoredFiles(
        projectID: UUID, photoFileName: String, drawing: ProjectDrawing,
        documentFileName: String, attachmentFileName: String
    ) -> BackupSnapshot {
        BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectID, name: "云备份附件边界", location: "现场", status: .active)],
            dailyLogs: [
                DailyLog(
                    date: BusinessDateValue(legacyText: "2026-07-11"),
                    weather: "晴",
                    content: "附件边界",
                    workers: NumericInputSupport.quantity("1"),
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
    }
}
