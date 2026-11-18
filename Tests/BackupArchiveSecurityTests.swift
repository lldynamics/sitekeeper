import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct BackupArchiveSecurityTests {
    @Test func longVideoFilenameDoesNotRequireAnUnusedLegacyThumbnailPath() throws {
        let name = String(repeating: "v", count: 205) + "-\(UUID().uuidString).mov"
        #expect(name.utf8.count < 255)
        let bytes = Data("preserve video bytes".utf8)
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(bytes, fileName: name)
        defer { QuickNoteAttachmentStorage.delete(fileName: name) }
        var snapshot = BackupSnapshot(materialItems: [], quoteItems: [], laborRecords: [], projects: [], dailyLogs: [], historyRecords: [], templates: [])
        snapshot.quickNotes = [QuickNote(attachments: [QuickNoteAttachment(kind: .video, fileName: name)])]
        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }
        #expect(archive.missingFiles.isEmpty)
        let preview = try BackupArchiveService.previewBackup(from: archive.fileURL)
        #expect(preview.snapshot.quickNotes.first?.attachments.first?.fileName == name)
        let staged = try BackupArchiveService.prepareEmbeddedFileRestore(from: archive.fileURL)
        staged.cancel()
        #expect(QuickNoteAttachmentStorage.data(for: name) == bytes)
    }

    @Test func archiveWriterRejectsDistinctFilesWithAliasingNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("backup-distinct-alias-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.bin")
        let second = root.appendingPathComponent("second.bin")
        try Data("first original".utf8).write(to: first)
        try Data("second original".utf8).write(to: second)
        let url = root.appendingPathComponent("out.zip")
        var writer = try StreamingZipArchiveWriter(fileURL: url)
        defer { try? writer.close() }
        var count = 0
        var missing: [String] = []
        var bytes = 0
        #expect(throws: FileStorageError.self) {
            try BackupArchiveService.addFiles(
                paths: ["same.bin", "SAME.bin"], prefix: BackupArchiveService.quickNotePrefix,
                displayName: "Attachment", typeKey: "attachment",
                fileURLProvider: { $0 == "same.bin" ? first : second }, sizeProvider: { _ in 1 },
                zip: &writer, includedFileCount: &count, missingFiles: &missing, rawFilesBytes: &bytes,
                shouldCancel: {}, onStep: { _ in }
            )
        }
        #expect(try Data(contentsOf: first) == Data("first original".utf8))
        #expect(try Data(contentsOf: second) == Data("second original".utf8))
    }

    @Test func overwriteCleanupPreservesDistinctUnpaddedAttachment() throws {
        let plain = "cleanup-\(UUID().uuidString).bin"
        let padded = " \(plain) "
        let original = Data("old attachment".utf8)
        let restored = Data("restored attachment".utf8)
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(original, fileName: padded)
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(restored, fileName: plain)
        let plainURL = QuickNoteAttachmentStorage.fileURL(for: plain)
        let paddedURL = QuickNoteAttachmentStorage.fileURL(for: padded)
        let trash = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-padded-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: plainURL)
            try? FileManager.default.removeItem(at: paddedURL)
            try? FileManager.default.removeItem(at: trash)
        }
        var before = BackupSnapshot(materialItems: [], quoteItems: [], laborRecords: [], projects: [], dailyLogs: [], historyRecords: [], templates: [])
        before.quickNotes = [QuickNote(attachments: [QuickNoteAttachment(kind: .file, fileName: padded)])]
        var after = before
        after.quickNotes = [QuickNote(attachments: [QuickNoteAttachment(kind: .file, fileName: plain)])]
        FileQuarantineStore.withRootURLForTesting(trash) {
            let removed = BackupImportCoordinator.cleanupOverwrittenFiles(previous: before, imported: after)
            #expect(removed.quickNoteAttachmentFileNames == [padded])
            #expect(QuickNoteAttachmentStorage.data(for: plain) == restored)
            #expect(!QuickNoteAttachmentStorage.exists(fileName: padded))
        }
    }

    @Test func restoreRejectsArchiveEntriesThatAliasOnTheStagingFilesystem() throws {
        let name = "backup-alias-\(UUID().uuidString).pdf"
        let alias = name.uppercased()
        let original = Data("existing attachment".utf8)
        let savedName = try QuickNoteAttachmentStorage.saveDataOrThrow(original, fileName: name)
        defer { QuickNoteAttachmentStorage.delete(fileName: savedName) }
        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "backup-case-alias")
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        let metadata = try BackupArchiveValidationTestSupport.makeValidBackupMetadataData()
        var zip = SimpleZipArchiveBuilder()
        zip.addFile(path: BackupArchiveService.manifestPath, data: try BackupImportExportTestSupport.manifestData())
        zip.addFile(path: BackupArchiveService.metadataPath, data: metadata)
        zip.addFile(path: BackupArchiveService.quickNotePrefix + name, data: Data("first".utf8))
        zip.addFile(path: BackupArchiveService.quickNotePrefix + alias, data: Data("second".utf8))
        try zip.build().write(to: archiveURL, options: .atomic)
        #expect(throws: SimpleZipArchiveReader.ZipReadError.self) {
            _ = try BackupArchiveService.prepareEmbeddedFileRestore(from: archiveURL)
        }
        #expect(QuickNoteAttachmentStorage.data(for: name) == original)
        #expect(BackupImportExportTestSupport.temporaryFiles(named: name, containingPathFragment: "backup-restore-").isEmpty)
    }

    @Test(arguments: Array(0..<13))
    func metadataAndEmbeddedReferencesRejectUnsafePaths(family: Int) throws {
        for name in ["../outside.bin", "/absolute.bin", "nested/file.bin", "nested\\file.bin", ".", "..", "bad\0name.bin"] {
            let snapshot = attachmentSnapshot(family: family, name: name)
            let data = try JSONEncoder().encode(snapshot)
            // Local historical data stays decodable and unchanged for manual recovery.
            let local = try JSONDecoder().decode(BackupSnapshot.self, from: data)
            #expect(try JSONEncoder().encode(local).count > 0)
            #expect(throws: FileStorageError.self) { try BackupArchiveService.decodeJSONSnapshot(from: data) }
            #expect(throws: FileStorageError.self) { try BackupArchiveService.makeArchive(from: snapshot) }
        }
    }

    @Test(arguments: Array(0..<13))
    func attachmentValidationPreservesHistoricalUnicodeAndCloudEmptyReferences(family: Int) throws {
        let historical = attachmentSnapshot(family: family, name: "旧工程 附件-非UUID-é-\(UUID().uuidString).pdf")
        try historical.validateAttachmentReferences()
        _ = try BackupArchiveService.decodeJSONSnapshot(from: JSONEncoder().encode(historical))
        let redacted = attachmentSnapshot(family: family, name: "")
        if family < 9 {
            try redacted.validateAttachmentReferences()
            _ = try BackupArchiveService.decodeJSONSnapshot(from: JSONEncoder().encode(redacted))
        } else {
            #expect(throws: FileStorageError.self) { try redacted.validateAttachmentReferences() }
        }
    }

    @Test func unsafeStorageURLsHaveNoFilesystemOrNetworkResource() throws {
        for name in ["", "../other", "/tmp/other", "a\\b", "bad\0name"] {
            let urls = [PhotoStorage.fileURL(for: name), PhotoStorage.thumbnailStorageURL(for: name),
                        DrawingStorage.fileURL(for: name), ProjectDocumentStorage.fileURL(for: name),
                        QuickNoteAttachmentStorage.fileURL(for: name)]
            for url in urls {
                #expect(!url.isFileURL)
                #expect(url.host == nil)
                #expect(url.path.isEmpty)
                #expect(!FileManager.default.fileExists(atPath: url.path))
                #expect(throws: (any Error).self) { _ = try Data(contentsOf: url) }
            }
            #expect(PhotoStorage.data(for: name) == nil)
            #expect(DrawingStorage.data(for: name) == nil)
            #expect(ProjectDocumentStorage.data(for: name) == nil)
            #expect(QuickNoteAttachmentStorage.data(for: name) == nil)
        }
    }

    @Test func storageFamiliesRejectExistingLinksAndDirectoriesAndPreserveTargets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("attachment-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside.bin")
        let bytes = Data("outside must survive".utf8)
        try bytes.write(to: outside)
        let families: [(String) throws -> URL] = [PhotoStorage.validatedFileURL(for:),
            PhotoStorage.validatedThumbnailFileURL(for:), DrawingStorage.validatedFileURL(for:),
            ProjectDocumentStorage.validatedFileURL(for:), QuickNoteAttachmentStorage.validatedFileURL(for:)]
        for target in families {
            let name = "unsafe-existing-\(UUID().uuidString).bin"
            let url = try target(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: url) }
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: outside)
            #expect(throws: FileStorageError.self) { _ = try target(name) }
            #expect(try Data(contentsOf: outside) == bytes)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            #expect(throws: FileStorageError.self) { _ = try target(name) }
            try FileManager.default.removeItem(at: url)
        }
    }

    @Test func documentRestorePreflightsWholeBatchAndRefusesSymlinkedRoot() throws {
        let family = DocumentStorageFileFamily(directoryName: "attachment-family-\(UUID().uuidString)", eventPrefix: "test")
        let root = family.directoryURL
        defer { try? FileManager.default.removeItem(at: root) }
        let safe = "历史 资料.txt"
        let original = Data("original".utf8)
        try family.writeDataOrThrow(original, fileName: safe)
        #expect(throws: FileStorageError.self) {
            try family.restoreOrThrow([(safe, Data("changed".utf8)), ("../outside.txt", Data([1]))])
        }
        #expect(family.data(for: safe, failureEvent: "test") == original)
        let external = FileManager.default.temporaryDirectory.appendingPathComponent("attachment-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: external) }
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: external)
        #expect(throws: FileStorageError.self) { try family.writeDataOrThrow(Data([1]), fileName: "blocked.txt") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: external.path).isEmpty)
    }

    private func attachmentSnapshot(family: Int, name: String) -> BackupSnapshot {
        var snapshot = BackupSnapshot(materialItems: [], quoteItems: [], laborRecords: [], projects: [], dailyLogs: [], historyRecords: [], templates: [])
        let log = DailyLog(date: .empty, weather: "", content: "", workers: .empty)
        let attachment = QuickNoteAttachment(kind: .video, fileName: name)
        switch family {
        case 0:
            var value = log
            value.photos = [LogPhoto(fileName: name)]
            snapshot.dailyLogs = [value]
        case 1:
            var value = log
            value.photoFileName = name
            snapshot.dailyLogs = [value]
        case 2: snapshot.siteTodos = [SiteTodo(title: "before", rectificationBeforePhotoFileName: name)]
        case 3: snapshot.siteTodos = [SiteTodo(title: "after", rectificationAfterPhotoFileName: name)]
        case 4: snapshot.projectDrawings = [ProjectDrawing(projectId: UUID(), name: "Drawing", fileName: name, fileType: "pdf")]
        case 5: snapshot.projectDocuments = [ProjectDocument(projectId: UUID(), title: "Document", fileName: name)]
        case 6: snapshot.quickNotes = [QuickNote(attachments: [attachment])]
        case 7: snapshot.constructionMethods = [ConstructionMethod(attachments: [attachment])]
        case 8: snapshot.constructionMethods = [ConstructionMethod(tutorialAttachments: [attachment])]
        case 9: snapshot.photoFiles = [PhotoBackupFile(fileName: name, data: Data([1]))]
        case 10: snapshot.drawingFiles = [DrawingBackupFile(fileName: name, data: Data([1]))]
        case 11: snapshot.documentFiles = [ProjectDocumentBackupFile(fileName: name, data: Data([1]))]
        default: snapshot.quickNoteAttachmentFiles = [QuickNoteAttachmentBackupFile(fileName: name, data: Data([1]))]
        }
        return snapshot
    }

    @Test func streamingSHA256MatchesKnownVector() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-sha256-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url, options: .atomic)

        #expect(
            try BackupArchiveSecurity.sha256Hex(of: url)
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test func remoteRestoreValidationAcceptsUntouchedArchiveAndRejectsChangedCopy() throws {
        let snapshot = BackupSnapshot(
            materialItems: [], quoteItems: [], laborRecords: [],
            projects: [Project(name: "远端校验", location: "现场", status: .active)],
            dailyLogs: [], historyRecords: [], templates: []
        )
        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }
        let digest = try BackupArchiveSecurity.sha256Hex(of: archive.fileURL)

        try BackupArchiveSecurity.validateRemoteCopy(at: archive.fileURL, expectedSHA256: digest)

        var changed = try Data(contentsOf: archive.fileURL)
        changed[changed.startIndex] ^= 0x01
        try changed.write(to: archive.fileURL, options: .atomic)
        do {
            try BackupArchiveSecurity.validateRemoteCopy(at: archive.fileURL, expectedSHA256: digest)
            Issue.record("预期应拒绝 SHA-256 不匹配的远端副本")
        } catch BackupArchiveSecurityError.digestMismatch {
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }
    }

    @Test func fullArchiveValidationReadsManifestAndMetadata() throws {
        let snapshot = BackupSnapshot(
            materialItems: [], quoteItems: [], laborRecords: [], projects: [],
            dailyLogs: [], historyRecords: [], templates: []
        )
        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        let manifest = try BackupArchiveService.validateArchive(at: archive.fileURL)
        #expect(manifest.schemaVersion == BackupSnapshot.currentSchemaVersion)
        #expect(manifest.metadataPath == BackupArchiveService.metadataPath)
    }

    @Test func storageValidationStopsAtSandboxContainerBoundaryWithoutTouchingAncestors() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox-boundary-\(UUID().uuidString)")
        let realHost = workspace.appendingPathComponent("real-host", isDirectory: true)
        let aliasedParent = workspace.appendingPathComponent("aliased-mobile", isDirectory: true)
        try FileManager.default.createDirectory(at: realHost, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createSymbolicLink(at: aliasedParent, withDestinationURL: realHost)

        let containerRoot = aliasedParent.appendingPathComponent("ContainerUUID", isDirectory: true)
        let photosDir = containerRoot.appendingPathComponent("Documents/Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        let targetFile = photosDir.appendingPathComponent("photo.jpg")
        try Data("ok".utf8).write(to: targetFile)

        let boundaryPaths: Set<String> = [containerRoot.standardizedFileURL.path]
        try AttachmentStoragePath.validateDirectory(photosDir, boundaryPaths: boundaryPaths)
        try AttachmentStoragePath.validateFile(targetFile, boundaryPaths: boundaryPaths)

        let symlinkInsideContainer = containerRoot.appendingPathComponent("Documents/LinkedPhotos", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: symlinkInsideContainer, withDestinationURL: photosDir)
        #expect(throws: FileStorageError.self) {
            try AttachmentStoragePath.validateDirectory(symlinkInsideContainer, boundaryPaths: boundaryPaths)
        }
    }
}
