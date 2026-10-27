import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct BackupExportTests {
    @Test func snapshotRoundtrip() throws {
        let original = BackupSnapshot(
            materialItems: [MaterialItem(name: "电线", quantity: NumericInputSupport.quantity("3"), unit: "卷", projectId: nil)],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: "测试项目", location: "测试地点", status: .active)],
            dailyLogs: [],
            historyRecords: [HistoryRecord(tool: "电流计算", input: "10kW", result: "45A", date: BusinessDateValue(legacyText: "2026-05-01 10:00"))],
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
        #expect(restored.favoriteMaterialKeys == ["key1"])
    }

    @Test func emptySnapshot() throws {
        let snapshot = BackupSnapshot(materialItems: [], quoteItems: [], laborRecords: [], projects: [], dailyLogs: [], historyRecords: [], templates: [])
        let data = try JSONEncoder().encode(snapshot)
        #expect(data.count > 0)
    }

    @Test func backupArchiveRoundtripIncludesOriginalFiles() throws {
        let projectId = UUID()
        let photoFile = try PhotoStorage.saveOrThrow(original: BackupImportExportTestSupport.makeJPEGData(), fileName: "backup-photo-\(UUID().uuidString).jpg")
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
            dailyLogs: [DailyLog(date: BusinessDateValue(legacyText: "2026-05-03"), weather: "晴", content: "完成", workers: NumericInputSupport.quantity("2"), photos: [LogPhoto(fileName: photoFile)], projectId: projectId)],
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

    @Test func backupArchiveCancelCleansPartialTemporaryZip() throws {
        let archivePrefix = "backup-archive-cancel-\(UUID().uuidString)"
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: "取消导出测试项目", location: "现场", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )
        var shouldCancel = false

        do {
            _ = try BackupArchiveService.makeArchive(
                from: snapshot,
                progress: { progress in
                    if progress.completedSteps >= 1 {
                        shouldCancel = true
                    }
                },
                shouldCancel: { shouldCancel },
                temporaryFilePrefix: archivePrefix
            )
            Issue.record("预期应抛出取消错误")
        } catch BackupArchiveError.cancelled {
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }

        #expect(BackupImportExportTestSupport.temporaryFiles(withPrefix: archivePrefix).isEmpty)
    }

    @Test func backupExportCancelAfterPrepareCleansTemporaryExportFile() async throws {
        let suggestedFileName = "backup-export-cancel-\(UUID().uuidString).zip"
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: "导出取消清理项目", location: "现场", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )

        do {
            let outcome = try await BackupExportCoordinator.exportBackup(
                snapshot: snapshot,
                suggestedFileName: suggestedFileName,
                progress: { _ in },
                shouldCancel: {
                    !BackupImportExportTestSupport.temporaryFiles(
                        named: suggestedFileName,
                        containingPathFragment: "sitekeeper-export-"
                    ).isEmpty
                }
            )
            ExportFileURLPreparer.cleanup(fileURL: outcome.preparedFileURL)
            Issue.record("预期应抛出取消错误")
        } catch BackupArchiveError.cancelled {
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }

        #expect(
            BackupImportExportTestSupport.temporaryFiles(
                named: suggestedFileName,
                containingPathFragment: "sitekeeper-export-"
            ).isEmpty
        )
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
    }

    @Test func streamingZipWriterRejectsDuplicatePath() throws {
        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "zip-duplicate-path")
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        var zip = try StreamingZipArchiveWriter(fileURL: archiveURL)
        try zip.addFile(path: "metadata.json", data: Data([0x01]))

        do {
            try zip.addFile(path: "metadata.json", data: Data([0x02]))
            Issue.record("预期应拒绝重复 ZIP 路径")
        } catch StreamingZipArchiveWriterError.duplicatePath(let path) {
            #expect(path == "metadata.json")
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }
        try zip.close()
    }

    @Test func streamingZipWriterRejectsUnsafePath() throws {
        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "zip-unsafe-path")
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        var zip = try StreamingZipArchiveWriter(fileURL: archiveURL)
        do {
            try zip.addFile(path: "../escape.txt", data: Data([0x01]))
            Issue.record("预期应拒绝不安全 ZIP 路径")
        } catch StreamingZipArchiveWriterError.invalidPath(let path) {
            #expect(path == "../escape.txt")
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }
        try zip.close()
    }
}
