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
        #expect(restored.schemaVersion == BackupSnapshot.currentSchemaVersion)
        #expect(!restored.appVersion.isEmpty)
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
        #expect(restored.schemaVersion == BackupSnapshot.currentSchemaVersion)
        #expect(restored.photoFiles.map(\.fileName).contains(photoFile))
        #expect(restored.documentFiles.map(\.fileName).contains(documentFile))
        #expect(restored.drawingFiles.map(\.fileName).contains(drawing.fileName))
        #expect(restored.quickNoteAttachmentFiles.map(\.fileName).contains(quickNoteFile))
    }

    @Test func backupOverwriteImpactListsOnlyExistingFilesRemovedByImportedSnapshot() throws {
        let projectId = UUID()
        let removedPhotoFile = try PhotoStorage.saveOrThrow(original: Self.makeJPEGData(), fileName: "backup-overwrite-photo-remove-\(UUID().uuidString).jpg")
        let retainedPhotoFile = try PhotoStorage.saveOrThrow(original: Self.makeJPEGData(), fileName: "backup-overwrite-photo-keep-\(UUID().uuidString).jpg")
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
                    date: "2026-05-03",
                    weather: "晴",
                    content: "覆盖前日志",
                    workers: "2",
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
                    date: "2026-05-03",
                    weather: "晴",
                    content: "覆盖后日志",
                    workers: "2",
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

    @Test func backupArchiveWritesManifestAndVersionedMetadata() throws {
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: "版本备份", location: "现场", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )

        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        let entries = try SimpleZipArchiveReader.read(Data(contentsOf: archive.fileURL))
        let manifestData = try #require(entries.first { $0.path == BackupArchiveService.manifestPath }?.data)
        let metadataData = try #require(entries.first { $0.path == BackupArchiveService.metadataPath }?.data)
        let manifest = try JSONDecoder().decode(BackupArchiveManifest.self, from: manifestData)
        let metadata = try JSONDecoder().decode(BackupSnapshot.self, from: metadataData)

        #expect(manifest.schemaVersion == BackupSnapshot.currentSchemaVersion)
        #expect(manifest.metadataPath == BackupArchiveService.metadataPath)
        #expect(metadata.schemaVersion == BackupSnapshot.currentSchemaVersion)
        #expect(metadata.projects.first?.name == "版本备份")
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

    @Test func backupPreparedEmbeddedFileRestoreCancelKeepsStorageUnchanged() throws {
        let projectId = UUID()
        let quickNoteFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x7A, 0x7B]), fileName: "backup-transaction-cancel-\(UUID().uuidString).bin")

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "事务取消恢复项目", location: "现场", status: .active)],
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
        transaction.cancel()

        #expect(QuickNoteAttachmentStorage.exists(fileName: quickNoteFile) == false)
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
            #expect(Bool(true))
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
        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-legacy-\(UUID().uuidString).json")
        try data.write(to: jsonURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let restored = try BackupArchiveService.decodeBackup(from: jsonURL)
        #expect(restored.projects.first?.name == "旧备份")
    }

    @Test func backupArchiveDecoderKeepsLegacyJSONWithoutVersionCompatibility() throws {
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: "无版本旧备份", location: "", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )
        let legacyData = try Self.legacyMetadataData(from: snapshot)
        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-legacy-no-version-\(UUID().uuidString).json")
        try legacyData.write(to: jsonURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let restored = try BackupArchiveService.decodeBackup(from: jsonURL)

        #expect(restored.schemaVersion == BackupSnapshot.legacySchemaVersion)
        #expect(restored.appVersion.isEmpty)
        #expect(restored.projects.first?.name == "无版本旧备份")
    }

    @Test func backupArchiveDecoderKeepsLegacyZipWithoutManifestCompatibility() throws {
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: "旧ZIP备份", location: "", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )
        let legacyData = try Self.legacyMetadataData(from: snapshot)
        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "legacy-backup")
        var zip = try StreamingZipArchiveWriter(fileURL: archiveURL)
        try zip.addFile(path: BackupArchiveService.metadataPath, data: legacyData)
        let finishedURL = try zip.finish()
        defer { try? FileManager.default.removeItem(at: finishedURL) }

        let preview = try BackupArchiveService.previewBackup(from: finishedURL)
        let restored = try BackupArchiveService.decodeBackup(from: finishedURL)

        #expect(preview.manifest.schemaVersion == BackupSnapshot.legacySchemaVersion)
        #expect(restored.schemaVersion == BackupSnapshot.legacySchemaVersion)
        #expect(restored.projects.first?.name == "旧ZIP备份")
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

    private static func legacyMetadataData(from snapshot: BackupSnapshot) throws -> Data {
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "schemaVersion")
        object.removeValue(forKey: "appVersion")
        object.removeValue(forKey: "appBuild")
        object.removeValue(forKey: "backupCreatedAt")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
