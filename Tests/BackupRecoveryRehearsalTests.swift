import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct BackupRecoveryRehearsalTests {
    @Test func backupExportClearRestoreRehearsalPersistsMetadataAndFiles() async throws {
        let fixture = try await makeFixture()
        var exportedFileURL: URL?
        defer { cleanup(fixture: fixture, exportedFileURL: exportedFileURL) }

        let exportOutcome = try await BackupExportCoordinator.exportBackup(
            snapshot: fixture.store.makeSnapshot(includePhotoFiles: true),
            suggestedFileName: "backup-recovery-rehearsal.zip",
            progress: { _ in },
            shouldCancel: { false }
        )
        exportedFileURL = exportOutcome.preparedFileURL

        let preview = try BackupArchiveService.previewBackup(from: exportOutcome.preparedFileURL)
        assertPreviewContainsEveryFileFamily(preview)
        try await clearMetadataAndFiles(fixture)

        let restoreTransaction = try BackupArchiveService.prepareEmbeddedFileRestore(
            from: exportOutcome.preparedFileURL
        )
        let restoredCounts = try await BackupImportCoordinator.commitAndPersistImport(
            restoreTransaction: restoreTransaction,
            importedSnapshot: preview.snapshot,
            previousSnapshot: fixture.store.makeSnapshot(includePhotoFiles: false),
            importMode: .overwrite,
            store: fixture.store,
            sourceFileName: exportOutcome.preparedFileURL.lastPathComponent
        )

        #expect(restoredCounts.totalCount == 4)
        assertRestoredStoreAndFiles(fixture)
        try await assertReloadedStore(fixture)
    }

    private struct Fixture {
        let storageDirectory: URL
        let store: DataStore
        let projectID: UUID
        let photoFileName: String
        let drawing: ProjectDrawing
        let documentFileName: String
        let quickNoteFileName: String
        let expectedPhotoData: Data
        let expectedDrawingData: Data
        let expectedDocumentData: Data
        let expectedQuickNoteData: Data
    }

    private func makeFixture() async throws -> Fixture {
        TransferLimitPolicy.setRuntimeProfileOverride(.development)
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-recovery-rehearsal-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)

        let projectID = UUID()
        let photoFileName = try PhotoStorage.saveOrThrow(
            original: BackupImportExportTestSupport.makeJPEGData(),
            fileName: "recovery-rehearsal-\(UUID().uuidString).jpg"
        )
        let drawing = try DrawingStorage.saveImportedDataOrThrow(
            data: Data([0x11, 0x22, 0x33, 0x44]),
            sourceFileName: "recovery-rehearsal.dwg",
            projectId: projectID
        )
        let documentFileName = try ProjectDocumentStorage.saveDataOrThrow(
            data: Data([0x51, 0x52, 0x53]),
            projectId: projectID,
            fileExtension: "pdf"
        )
        let quickNoteFileName = try QuickNoteAttachmentStorage.saveDataOrThrow(
            Data([0x61, 0x62, 0x63, 0x64]),
            fileName: "recovery-rehearsal-\(UUID().uuidString).bin"
        )

        let store = DataStore(storageDirectory: storageDirectory)
        await store.awaitInitialLoad()
        seedStore(
            store,
            projectID: projectID,
            photoFileName: photoFileName,
            drawing: drawing,
            documentFileName: documentFileName,
            quickNoteFileName: quickNoteFileName
        )
        try await store.flushSaveOrThrow()

        return try Fixture(
            storageDirectory: storageDirectory,
            store: store,
            projectID: projectID,
            photoFileName: photoFileName,
            drawing: drawing,
            documentFileName: documentFileName,
            quickNoteFileName: quickNoteFileName,
            expectedPhotoData: #require(PhotoStorage.data(for: photoFileName)),
            expectedDrawingData: #require(DrawingStorage.data(for: drawing.fileName)),
            expectedDocumentData: #require(ProjectDocumentStorage.data(for: documentFileName)),
            expectedQuickNoteData: #require(QuickNoteAttachmentStorage.data(for: quickNoteFileName))
        )
    }

    private func seedStore(
        _ store: DataStore,
        projectID: UUID,
        photoFileName: String,
        drawing: ProjectDrawing,
        documentFileName: String,
        quickNoteFileName: String
    ) {
        store.replaceProjects([
            Project(
                id: projectID,
                name: "恢复演练项目",
                location: "测试现场",
                status: .active,
                contractAmount: "880000"
            )
        ])
        store.replaceDailyLogs([
            DailyLog(
                date: "2026-07-13",
                weather: "晴",
                content: "恢复演练日志",
                workers: "8",
                photos: [LogPhoto(fileName: photoFileName)],
                projectId: projectID
            )
        ])
        store.replaceProjectDrawings([drawing])
        store.replaceProjectDocuments([
            ProjectDocument(projectId: projectID, title: "恢复演练资料", fileName: documentFileName)
        ])
        store.replaceQuickNotes([
            QuickNote(
                title: "恢复演练随手记",
                content: "导出、清空、恢复后仍应存在",
                projectId: projectID,
                attachments: [QuickNoteAttachment(kind: .file, fileName: quickNoteFileName)]
            )
        ])
    }

    private func clearMetadataAndFiles(_ fixture: Fixture) async throws {
        fixture.store.clearAllBusinessData(deleteStoredFiles: false)
        try await fixture.store.flushSaveOrThrow()
        PhotoStorage.delete(fileNames: [fixture.photoFileName])
        DrawingStorage.delete(fileName: fixture.drawing.fileName)
        ProjectDocumentStorage.delete(fileName: fixture.documentFileName)
        QuickNoteAttachmentStorage.delete(fileName: fixture.quickNoteFileName)

        #expect(fixture.store.projects.isEmpty)
        #expect(!PhotoStorage.exists(fileName: fixture.photoFileName))
        #expect(!DrawingStorage.exists(fileName: fixture.drawing.fileName))
        #expect(!ProjectDocumentStorage.exists(fileName: fixture.documentFileName))
        #expect(!QuickNoteAttachmentStorage.exists(fileName: fixture.quickNoteFileName))
    }

    private func assertPreviewContainsEveryFileFamily(_ preview: BackupImportPreview) {
        #expect(preview.photoFileCount == 1)
        #expect(preview.drawingFileCount == 1)
        #expect(preview.documentFileCount == 1)
        #expect(preview.quickNoteAttachmentFileCount == 1)
    }

    private func assertRestoredStoreAndFiles(_ fixture: Fixture) {
        #expect(fixture.store.projects.first?.id == fixture.projectID)
        #expect(fixture.store.dailyLogs.first?.content == "恢复演练日志")
        #expect(fixture.store.projectDrawings.first?.fileName == fixture.drawing.fileName)
        #expect(fixture.store.projectDocuments.first?.fileName == fixture.documentFileName)
        #expect(fixture.store.quickNotes.first?.attachments.first?.fileName == fixture.quickNoteFileName)
        #expect(PhotoStorage.data(for: fixture.photoFileName) == fixture.expectedPhotoData)
        #expect(DrawingStorage.data(for: fixture.drawing.fileName) == fixture.expectedDrawingData)
        #expect(ProjectDocumentStorage.data(for: fixture.documentFileName) == fixture.expectedDocumentData)
        #expect(QuickNoteAttachmentStorage.data(for: fixture.quickNoteFileName) == fixture.expectedQuickNoteData)
    }

    private func assertReloadedStore(_ fixture: Fixture) async throws {
        let reloadedStore = DataStore(storageDirectory: fixture.storageDirectory)
        await reloadedStore.awaitInitialLoad()
        #expect(reloadedStore.projects.first?.id == fixture.projectID)
        #expect(reloadedStore.dailyLogs.first?.photos.first?.fileName == fixture.photoFileName)
        #expect(reloadedStore.projectDrawings.first?.fileName == fixture.drawing.fileName)
        #expect(reloadedStore.projectDocuments.first?.fileName == fixture.documentFileName)
        #expect(reloadedStore.quickNotes.first?.content == "导出、清空、恢复后仍应存在")
    }

    private func cleanup(fixture: Fixture, exportedFileURL: URL?) {
        if let exportedFileURL {
            ExportFileURLPreparer.cleanup(fileURL: exportedFileURL)
        }
        PhotoStorage.delete(fileNames: [fixture.photoFileName])
        DrawingStorage.delete(fileName: fixture.drawing.fileName)
        ProjectDocumentStorage.delete(fileName: fixture.documentFileName)
        QuickNoteAttachmentStorage.delete(fileName: fixture.quickNoteFileName)
        try? FileManager.default.removeItem(at: fixture.storageDirectory)
    }
}
