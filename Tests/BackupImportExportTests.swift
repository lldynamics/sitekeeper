import Testing
import Foundation
import UIKit
@testable import sitekeeper

@MainActor
struct BackupImportExportTests {
    // 备份快照编解码往返
    @Test func snapshotRoundtrip() throws {
        let original = BackupSnapshot(
            materialItems: [MaterialItem(name: "电线", quantity: "3", unit: "卷", projectId: nil)],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: "测试项目", location: "测试地点", status: .active)],
            dailyLogs: [],
            historyRecords: [HistoryRecord(tool: "电流计算", input: "10kW", result: "45A", date: "2026-05-01 10:00")],
            lightingCircuitPlans: [
                LightingCircuitPlan(
                    name: "测试照明方案",
                    projectId: nil,
                    supplyType: .singlePhase,
                    voltage: "220",
                    powerFactor: "0.9",
                    demandFactor: "0.9",
                    breakerFactor: "1.25",
                    wireFactor: "1.15",
                    isCopper: true,
                    loads: [LightingCircuitLoad(name: "回路1", powerKW: "3")],
                    updatedAt: "2026-05-01 10:00"
                )
            ],
            templates: [],
            favoriteMaterialKeys: ["key1"],
            recentMaterialKeys: ["key2"]
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(BackupSnapshot.self, from: data)
        #expect(restored.materialItems.count == 1)
        #expect(restored.projects.count == 1)
        #expect(restored.historyRecords.count == 1)
        #expect(restored.lightingCircuitPlans.count == 1)
        #expect(restored.favoriteMaterialKeys == ["key1"])
    }

    // 空快照可用
    @Test func emptySnapshot() throws {
        let snapshot = BackupSnapshot(materialItems: [], quoteItems: [], laborRecords: [], projects: [], dailyLogs: [], historyRecords: [], templates: [])
        let data = try JSONEncoder().encode(snapshot)
        #expect(data.count > 0)
    }

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
        #expect(filtered.photoFiles.isEmpty)
        #expect(filtered.drawingFiles.isEmpty)
        #expect(filtered.documentFiles.isEmpty)
        #expect(filtered.quickNoteAttachmentFiles.isEmpty)
    }

    @Test func backupArchiveRoundtripIncludesOriginalFiles() throws {
        let projectId = UUID()
        let photoFile = try PhotoStorage.saveOrThrow(original: Self.makeJPEGData(), fileName: "backup-photo-\(UUID().uuidString).jpg")
        let documentFile = try ProjectDocumentStorage.savePDFOrThrow(data: Data([0x01, 0x02, 0x03]), projectId: projectId)
        let quickNoteFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x04, 0x05]), fileName: "backup-note-\(UUID().uuidString).bin")
        let drawingSource = FileManager.default.temporaryDirectory.appendingPathComponent("backup-drawing-\(UUID().uuidString).dwg")
        try Data([0x06, 0x07, 0x08, 0x09]).write(to: drawingSource, options: .atomic)
        let drawing = try DrawingStorage.saveImportedFileOrThrow(from: drawingSource, projectId: projectId)

        defer {
            PhotoStorage.delete(fileName: photoFile)
            ProjectDocumentStorage.delete(fileName: documentFile)
            QuickNoteAttachmentStorage.delete(fileName: quickNoteFile)
            DrawingStorage.delete(fileName: drawing.fileName)
            try? FileManager.default.removeItem(at: drawingSource)
        }

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "备份项目", location: "现场", status: .active)],
            dailyLogs: [DailyLog(date: "2026-05-03", weather: "晴", content: "完成", workers: "2", photos: [LogPhoto(fileName: photoFile)], projectId: projectId)],
            historyRecords: [],
            projectDrawings: [drawing],
            projectDocuments: [ProjectDocument(projectId: projectId, title: "票据", fileName: documentFile)],
            quickNotes: [QuickNote(projectId: projectId, attachments: [QuickNoteAttachment(kind: .file, fileName: quickNoteFile)])],
            templates: []
        )

        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        #expect(archive.includedFileCount == 4)
        #expect(archive.missingFiles.isEmpty)
        let archiveData = try Data(contentsOf: archive.fileURL, options: [.mappedIfSafe])
        #expect(archiveData.starts(with: Data([0x50, 0x4B, 0x03, 0x04])))

        let restored = try BackupArchiveService.decodeBackup(from: archive.fileURL)
        #expect(restored.projects.first?.name == "备份项目")
        #expect(restored.photoFiles.map(\.fileName).contains(photoFile))
        #expect(restored.documentFiles.map(\.fileName).contains(documentFile))
        #expect(restored.drawingFiles.map(\.fileName).contains(drawing.fileName))
        #expect(restored.quickNoteAttachmentFiles.map(\.fileName).contains(quickNoteFile))
    }

    @Test func backupArchiveIncludesConstructionMethodAttachments() throws {
        let projectId = UUID()
        let methodAttachment = try QuickNoteAttachmentStorage.saveDataOrThrow(
            Data([0x11, 0x12]),
            fileName: "method-attachment-\(UUID().uuidString).bin"
        )
        let tutorialAttachment = try QuickNoteAttachmentStorage.saveDataOrThrow(
            Data([0x13, 0x14]),
            fileName: "tutorial-attachment-\(UUID().uuidString).bin"
        )
        defer {
            QuickNoteAttachmentStorage.delete(fileName: methodAttachment)
            QuickNoteAttachmentStorage.delete(fileName: tutorialAttachment)
        }

        let method = ConstructionMethod(
            title: "砌墙",
            trade: "泥工",
            tutorialAttachments: [QuickNoteAttachment(kind: .file, fileName: tutorialAttachment)],
            attachments: [QuickNoteAttachment(kind: .file, fileName: methodAttachment)]
        )
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "工艺项目", location: "现场", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: [],
            constructionMethods: [method]
        )

        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        #expect(archive.includedFileCount == 2)
        let restored = try BackupArchiveService.decodeBackup(from: archive.fileURL)
        let attachmentNames = Set(restored.quickNoteAttachmentFiles.map { $0.fileName })
        #expect(attachmentNames.contains(methodAttachment))
        #expect(attachmentNames.contains(tutorialAttachment))
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

    @Test func backupRestoreEmbeddedFilesHandlesLargeZipEntry() throws {
        let projectId = UUID()
        let quickNoteFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x5A]), fileName: "backup-large-stream-\(UUID().uuidString).bin")
        let targetSize = 32 * 1024 * 1024
        let sourceURL = QuickNoteAttachmentStorage.fileURL(for: quickNoteFile)
        let handle = try FileHandle(forWritingTo: sourceURL)
        try handle.truncate(atOffset: UInt64(targetSize))
        try handle.close()

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "大附件流式恢复", location: "现场", status: .active)],
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
        #expect(QuickNoteAttachmentStorage.fileSize(for: quickNoteFile) == targetSize)
    }

    @Test func backupRestoreEmbeddedFilesCancelKeepsStorageUnchanged() throws {
        let projectId = UUID()
        let quickNoteFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x3A, 0x3B, 0x3C]), fileName: "backup-cancel-\(UUID().uuidString).bin")

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "取消恢复项目", location: "现场", status: .active)],
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

        do {
            _ = try BackupArchiveService.restoreEmbeddedFiles(
                from: archive.fileURL,
                shouldCancel: { true }
            )
            Issue.record("预期应抛出取消错误")
        } catch BackupArchiveError.cancelled {
            #expect(true)
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }

        #expect(QuickNoteAttachmentStorage.exists(fileName: quickNoteFile) == false)
    }

    @Test func backupRestoreEmbeddedFilesFromJSON() throws {
        let projectId = UUID()
        let fileName = "backup-json-\(UUID().uuidString).bin"
        let jsonURL = FileManager.default.temporaryDirectory.appendingPathComponent("backup-json-\(UUID().uuidString).json")

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "JSON恢复项目", location: "现场", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: [],
            quickNoteAttachmentFiles: [QuickNoteAttachmentBackupFile(fileName: fileName, data: Data([0x4A, 0x4B, 0x4C]))]
        )

        let jsonData = try JSONEncoder().encode(snapshot)
        try jsonData.write(to: jsonURL, options: .atomic)

        defer {
            QuickNoteAttachmentStorage.delete(fileName: fileName)
            try? FileManager.default.removeItem(at: jsonURL)
        }

        QuickNoteAttachmentStorage.delete(fileName: fileName)
        #expect(QuickNoteAttachmentStorage.exists(fileName: fileName) == false)

        let restored = try BackupArchiveService.restoreEmbeddedFiles(from: jsonURL)
        #expect(restored.quickNoteAttachmentFileCount == 1)
        #expect(QuickNoteAttachmentStorage.exists(fileName: fileName))
    }

    @Test func backupArchiveDecoderKeepsLegacyJSONCompatibility() throws {
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: "旧备份", location: "", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )
        let data = try JSONEncoder().encode(snapshot)
        let restored = try BackupArchiveService.decodeBackup(from: data)
        #expect(restored.projects.first?.name == "旧备份")
    }

    @Test func backupArchiveEstimateAllowsLargeRawFiles() throws {
        let fileName = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x01]), fileName: "backup-oversize-\(UUID().uuidString).bin")
        defer { QuickNoteAttachmentStorage.delete(fileName: fileName) }

        let url = QuickNoteAttachmentStorage.fileURL(for: fileName)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(10 * 1024 * 1024 * 1024))
        try handle.close()

        let projectId = UUID()
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "大包项目", location: "现场", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            quickNotes: [QuickNote(projectId: projectId, attachments: [QuickNoteAttachment(kind: .file, fileName: fileName)])],
            templates: []
        )

        let estimate = BackupArchiveService.estimateArchive(from: snapshot)
        #expect(estimate.estimatedBytes > BackupArchiveService.largeArchiveWarningBytes)
        #expect(StreamingZipArchiveWriter.requiresZip64ForTesting(
            entrySize: UInt64(estimate.rawFilesBytes),
            entryOffset: 0,
            entryCount: 1,
            centralSize: 128,
            centralOffset: UInt64(estimate.rawFilesBytes)
        ))
    }

    private static func makeJPEGData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let image = renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw FileStorageError.imageEncodingFailed
        }
        return data
    }
}
