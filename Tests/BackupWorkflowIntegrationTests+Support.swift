import Foundation
import Testing
@testable import sitekeeper

/// Every metadata directory, archive, and attachment belongs to this fixture. The
/// test runner supplies an independent app bundle; no installed app is inspected.
@MainActor
final class BackupWorkflowIntegrationFixture {
    let root: URL
    let store: DataStore
    let localProject = Project(name: "Local workflow project", location: "Synthetic fixture")
    let incomingProject = Project(name: "Incoming workflow project", location: "Synthetic fixture")
    let localNoteID = UUID()
    let incomingNoteID = UUID()
    let sharedFileName = "workflow-shared-\(UUID().uuidString).bin"
    let obsoleteFileName = "workflow-obsolete-\(UUID().uuidString).bin"
    let sentinelFileName = "workflow-unreferenced-\(UUID().uuidString).bin"
    let localData = Data("local workflow attachment".utf8)
    let incomingData = Data("incoming workflow attachment".utf8)
    let sentinelData = Data("unrelated fixture file must survive".utf8)
    private var loadedStores: [DataStore] = []
    private var ownedFileNames: Set<String> = []

    var importedAttachmentName: String? {
        store.quickNotes.first(where: { $0.id == incomingNoteID })?.attachments.first?.fileName
    }

    private init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("backup-workflow-integration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        store = DataStore(storageDirectory: root)
    }

    static func make() async throws -> BackupWorkflowIntegrationFixture {
        try #require(ProcessInfo.processInfo.environment["UITEST_VALIDATION_ISOLATED"] == "1")
        try #require(Bundle.main.bundleIdentifier?.contains(".validation.followup.") == true)
        let fixture = try BackupWorkflowIntegrationFixture()
        do {
            await fixture.store.awaitInitialLoad()
            try fixture.seedLocalFiles()
            fixture.seedLocalMetadata()
            try await fixture.store.flushSaveOrThrow()
            return fixture
        } catch {
            fixture.cleanup()
            throw error
        }
    }

    private func seedLocalFiles() throws {
        for name in [sharedFileName, obsoleteFileName, sentinelFileName] {
            try #require(!QuickNoteAttachmentStorage.exists(fileName: name))
        }
        try saveOwnedFile(localData, name: sharedFileName)
        try saveOwnedFile(localData, name: obsoleteFileName)
        try saveOwnedFile(sentinelData, name: sentinelFileName)
    }

    private func saveOwnedFile(_ data: Data, name: String) throws {
        let savedName = try QuickNoteAttachmentStorage.saveDataOrThrow(data, fileName: name)
        ownedFileNames.insert(savedName)
    }

    private func seedLocalMetadata() {
        store.replaceProjects([localProject])
        store.replaceQuickNotes([QuickNote(
            id: localNoteID,
            title: "Local workflow note",
            projectId: localProject.id,
            attachments: [
                QuickNoteAttachment(kind: .file, fileName: sharedFileName),
                QuickNoteAttachment(kind: .file, fileName: obsoleteFileName)
            ]
        )])
        store.replaceMaterialSheetDrafts([MaterialSheetDraft(title: "Local workflow draft", projectId: localProject.id)])
    }

    private func incomingSnapshot() -> BackupSnapshot {
        BackupSnapshot(
            materialItems: [], quoteItems: [], laborRecords: [], projects: [incomingProject],
            dailyLogs: [], historyRecords: [],
            quickNotes: [QuickNote(
                id: incomingNoteID,
                title: "Incoming workflow note",
                projectId: incomingProject.id,
                attachments: [QuickNoteAttachment(kind: .file, fileName: sharedFileName)]
            )],
            templates: [],
            materialSheetDrafts: [MaterialSheetDraft(title: "Incoming workflow draft", projectId: incomingProject.id)]
        )
    }

    /// The ZIP is synthesized directly, so preparing incoming bytes never replaces
    /// an existing attachment before the import transaction takes ownership.
    func makeArchive(corruptMetadata: Bool = false) throws -> URL {
        let snapshot = incomingSnapshot()
        let manifest = BackupArchiveManifest(schemaVersion: snapshot.schemaVersion, metadataPath: BackupArchiveService.metadataPath)
        let metadata: Data
        if corruptMetadata {
            metadata = Data("invalid synthetic metadata".utf8)
        } else {
            metadata = try JSONEncoder().encode(snapshot)
        }
        var zip = SimpleZipArchiveBuilder()
        zip.addFile(path: BackupArchiveService.manifestPath, data: try JSONEncoder().encode(manifest))
        zip.addFile(path: BackupArchiveService.metadataPath, data: metadata)
        zip.addFile(path: BackupArchiveService.quickNotePrefix + sharedFileName, data: incomingData)
        let url = root.appendingPathComponent("workflow-\(UUID().uuidString).zip")
        try zip.build().write(to: url, options: .atomic)
        return url
    }

    func metadataData() throws -> Data {
        try Self.comparableMetadata(store.makeSnapshot(includePhotoFiles: false))
    }

    private static func comparableMetadata(_ snapshot: BackupSnapshot) throws -> Data {
        var normalized = snapshot
        normalized.backupCreatedAt = ""
        return try BackupArchiveRestoreJournal.encodeMetadata(normalized)
    }

    func expectReloadMatchesCurrentMetadata() async throws {
        let expected = try metadataData()
        let reloaded = DataStore(storageDirectory: root)
        loadedStores.append(reloaded)
        await reloaded.awaitInitialLoad()
        #expect(reloaded.loadState == .ready)
        #expect(try Self.comparableMetadata(reloaded.makeSnapshot(includePhotoFiles: false)) == expected)
    }

    func expectLocalFilesUnchanged() {
        #expect(QuickNoteAttachmentStorage.data(for: sharedFileName) == localData)
        #expect(QuickNoteAttachmentStorage.data(for: obsoleteFileName) == localData)
        #expect(QuickNoteAttachmentStorage.data(for: sentinelFileName) == sentinelData)
    }

    func expectNoPendingTransaction() throws {
        let transactions = BackupArchiveRestoreJournal.transactionsRoot(for: store.storeURL)
        if FileManager.default.fileExists(atPath: transactions.path) {
            #expect(try FileManager.default.contentsOfDirectory(at: transactions, includingPropertiesForKeys: nil).isEmpty)
        }
    }

    func cleanup() {
        var fileNames = ownedFileNames
        if let importedAttachmentName { fileNames.insert(importedAttachmentName) }
        for dataStore in [store] + loadedStores {
            dataStore.cancelScheduledSave()
            dataStore.persistTask?.cancel()
            dataStore.initialLoadTask?.cancel()
            dataStore.dataHealthScanTask?.cancel()
        }
        FileQuarantineStore.withRootURLForTesting(root.appendingPathComponent("quarantine")) {
            for name in fileNames { QuickNoteAttachmentStorage.delete(fileName: name) }
        }
        try? FileManager.default.removeItem(at: root)
    }
}
