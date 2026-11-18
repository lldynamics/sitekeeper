import Foundation
import Testing
@testable import sitekeeper

@MainActor
@Suite(
    .serialized,
    .enabled(
        if: ProcessInfo.processInfo.environment["UITEST_VALIDATION_ISOLATED"] == "1"
            && Bundle.main.bundleIdentifier?.contains(".validation.followup.") == true,
        "Requires explicit opt-in and an independently prepared validation app"
    )
)
struct BackupWorkflowIntegrationTests {
    @Test func oldArchiveWithIdenticalCaseAliasesRestoresOneSharedAttachment() async throws {
        let fixture = try await BackupWorkflowIntegrationFixture.make()
        defer { fixture.cleanup() }
        let alias = fixture.sharedFileName.uppercased()
        let archiveURL = try fixture.makeArchive(
            attachmentNames: [alias, fixture.sharedFileName],
            archiveFileNames: [fixture.sharedFileName, alias]
        )
        let result = try await BackupImportWorkflow.run(
            sourceURL: archiveURL, preparedMetadata: nil,
            operations: LiveBackupImportWorkflowOperations(store: fixture.store, selectedImportMode: { .merge }),
            onEvent: { _ in }
        )
        let note = try #require(fixture.store.quickNotes.first { $0.id == fixture.incomingNoteID })
        let names = note.attachments.map(\.fileName)
        #expect(names.count == 2 && names[0] == names[1])
        #expect(QuickNoteAttachmentStorage.data(for: names[0]) == fixture.incomingData)
        #expect(QuickNoteAttachmentStorage.data(for: fixture.sharedFileName) == fixture.localData)
        #expect(result.restoredFileCount == 1)
        try await fixture.expectReloadMatchesCurrentMetadata()
    }

    @Test func backupWithSharedCaseAliasesProducesARestorableArchive() async throws {
        let fixture = try await BackupWorkflowIntegrationFixture.make()
        defer { fixture.cleanup() }
        var snapshot = fixture.store.makeSnapshot(includePhotoFiles: false)
        snapshot.quickNotes[0].attachments.append(QuickNoteAttachment(kind: .file, fileName: fixture.sharedFileName.uppercased()))
        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }
        #expect(archive.missingFiles.isEmpty)
        let transaction = try BackupArchiveService.prepareEmbeddedFileRestore(from: archive.fileURL)
        transaction.cancel()
        #expect(QuickNoteAttachmentStorage.data(for: fixture.sharedFileName) == fixture.localData)
    }

    @Test func liveMergeKeepsCaseAliasesOfOneImportedAttachmentTogether() async throws {
        let fixture = try await BackupWorkflowIntegrationFixture.make()
        defer { fixture.cleanup() }
        let alias = fixture.sharedFileName.uppercased()
        let archiveURL = try fixture.makeArchive(attachmentNames: [alias, fixture.sharedFileName])
        _ = try await BackupImportWorkflow.run(
            sourceURL: archiveURL, preparedMetadata: nil,
            operations: LiveBackupImportWorkflowOperations(store: fixture.store, selectedImportMode: { .merge }),
            onEvent: { _ in }
        )
        let note = try #require(fixture.store.quickNotes.first { $0.id == fixture.incomingNoteID })
        let names = note.attachments.map(\.fileName)
        #expect(names.count == 2)
        #expect(names[0] == names[1])
        #expect(names[0] != fixture.sharedFileName)
        #expect(QuickNoteAttachmentStorage.data(for: names[0]) == fixture.incomingData)
        #expect(QuickNoteAttachmentStorage.data(for: fixture.sharedFileName) == fixture.localData)
        try await fixture.expectReloadMatchesCurrentMetadata()
    }

    @Test func liveOverwriteDoesNotCleanUpCaseAliasOfRestoredAttachment() async throws {
        let fixture = try await BackupWorkflowIntegrationFixture.make()
        defer { fixture.cleanup() }
        let alias = fixture.sharedFileName.uppercased()
        let archiveURL = try fixture.makeArchive(attachmentNames: [alias], archiveFileNames: [alias])
        _ = try await BackupImportWorkflow.run(
            sourceURL: archiveURL, preparedMetadata: nil,
            operations: LiveBackupImportWorkflowOperations(store: fixture.store, selectedImportMode: { .overwrite }),
            onEvent: { _ in }
        )
        #expect(fixture.importedAttachmentName == fixture.sharedFileName)
        #expect(QuickNoteAttachmentStorage.data(for: fixture.sharedFileName) == fixture.incomingData)
        #expect(!QuickNoteAttachmentStorage.exists(fileName: fixture.obsoleteFileName))
        #expect(QuickNoteAttachmentStorage.data(for: fixture.sentinelFileName) == fixture.sentinelData)
        try await fixture.expectReloadMatchesCurrentMetadata()
    }

    @Test func liveMergeRenamesCollidingAttachmentAndPersistsAcrossReload() async throws {
        let fixture = try await BackupWorkflowIntegrationFixture.make()
        defer { fixture.cleanup() }
        let archiveURL = try fixture.makeArchive()
        var phases: [BackupImportWorkflowPhase] = []
        let result = try await BackupImportWorkflow.run(
            sourceURL: archiveURL,
            preparedMetadata: nil,
            operations: LiveBackupImportWorkflowOperations(store: fixture.store, selectedImportMode: { .merge }),
            onEvent: { if case let .phase(phase) = $0 { phases.append(phase) } }
        )
        let importedName = try #require(fixture.importedAttachmentName)
        #expect(importedName != fixture.sharedFileName)
        #expect(QuickNoteAttachmentStorage.data(for: importedName) == fixture.incomingData)
        #expect(QuickNoteAttachmentStorage.data(for: fixture.sharedFileName) == fixture.localData)
        #expect(QuickNoteAttachmentStorage.exists(fileName: fixture.obsoleteFileName))
        #expect(QuickNoteAttachmentStorage.data(for: fixture.sentinelFileName) == fixture.sentinelData)
        #expect(result == BackupImportWorkflowResult(mode: .merge, restoredFileCount: 1, overwrittenFileCount: 0))
        #expect(Set(fixture.store.projects.map(\.id)) == [fixture.localProject.id, fixture.incomingProject.id])
        #expect(fixture.store.quickNotes.count == 2)
        #expect(phases == [.stagingFiles, .applyingMetadata, .committingFiles, .persistingMetadata, .cleaningOverwrittenFiles])
        try await fixture.expectReloadMatchesCurrentMetadata()
        try fixture.expectNoPendingTransaction()
    }

    @Test func liveOverwriteRestoresFilesCleansRemovedReferencesAndPersistsAcrossReload() async throws {
        let fixture = try await BackupWorkflowIntegrationFixture.make()
        defer { fixture.cleanup() }
        let archiveURL = try fixture.makeArchive()
        let preview = try BackupArchiveService.previewBackup(from: archiveURL)
        let result = try await BackupImportWorkflow.run(
            sourceURL: archiveURL,
            preparedMetadata: preview.snapshot,
            operations: LiveBackupImportWorkflowOperations(store: fixture.store, selectedImportMode: { .overwrite }),
            onEvent: { _ in }
        )
        #expect(result == BackupImportWorkflowResult(mode: .overwrite, restoredFileCount: 1, overwrittenFileCount: 1))
        #expect(fixture.store.projects.map(\.id) == [fixture.incomingProject.id])
        #expect(fixture.store.quickNotes.map(\.id) == [fixture.incomingNoteID])
        #expect(fixture.importedAttachmentName == fixture.sharedFileName)
        #expect(QuickNoteAttachmentStorage.data(for: fixture.sharedFileName) == fixture.incomingData)
        #expect(!QuickNoteAttachmentStorage.exists(fileName: fixture.obsoleteFileName))
        #expect(QuickNoteAttachmentStorage.data(for: fixture.sentinelFileName) == fixture.sentinelData)
        #expect(fixture.store.materialSheetDrafts.map(\.title) == ["Incoming workflow draft"])
        try await fixture.expectReloadMatchesCurrentMetadata()
        try fixture.expectNoPendingTransaction()
    }

    @Test func liveInvalidMetadataArchiveLeavesLocalFilesAndSavedMetadataUnchanged() async throws {
        let fixture = try await BackupWorkflowIntegrationFixture.make()
        defer { fixture.cleanup() }
        let original = try fixture.metadataData()
        let diskBefore = try Data(contentsOf: fixture.store.storeURL)
        let archiveURL = try fixture.makeArchive(corruptMetadata: true)
        do {
            _ = try await BackupImportWorkflow.run(
                sourceURL: archiveURL,
                preparedMetadata: nil,
                operations: LiveBackupImportWorkflowOperations(store: fixture.store, selectedImportMode: { .overwrite }),
                onEvent: { _ in }
            )
            Issue.record("Invalid archive metadata must fail before staging or applying records")
        } catch let failure as BackupImportWorkflowFailure {
            #expect(failure.phase == .readingMetadata)
            #expect(!failure.cancelledBeforeCommit)
        }
        #expect(try fixture.metadataData() == original)
        #expect(try Data(contentsOf: fixture.store.storeURL) == diskBefore)
        fixture.expectLocalFilesUnchanged()
        try await fixture.expectReloadMatchesCurrentMetadata()
        try fixture.expectNoPendingTransaction()
    }

    @Test func livePersistenceCancellationRollsBackCommittedFilesAndMetadataAndReloads() async throws {
        let fixture = try await BackupWorkflowIntegrationFixture.make()
        defer { fixture.cleanup() }
        let original = try fixture.metadataData()
        let diskBefore = try Data(contentsOf: fixture.store.storeURL)
        let archiveURL = try fixture.makeArchive()
        var observedCommittedFiles = false
        let task = Task { @MainActor in
            try await BackupImportWorkflow.run(
                sourceURL: archiveURL,
                preparedMetadata: nil,
                operations: LiveBackupImportWorkflowOperations(store: fixture.store, selectedImportMode: { .overwrite }),
                onEvent: { event in
                    if event == .phase(.persistingMetadata) {
                        observedCommittedFiles = QuickNoteAttachmentStorage.data(for: fixture.sharedFileName) == fixture.incomingData
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
            )
        }
        do {
            _ = try await task.value
            Issue.record("Cancelling persistence must surface the real transaction failure")
        } catch let failure as BackupImportWorkflowFailure {
            #expect(failure.phase == .persistingMetadata)
            #expect(failure.underlyingError is CancellationError)
            #expect(!failure.cancelledBeforeCommit)
        }
        #expect(observedCommittedFiles)
        #expect(!fixture.store.isApplyingBackup)
        #expect(fixture.store.loadState == .ready)
        #expect(try fixture.metadataData() == original)
        #expect(try Data(contentsOf: fixture.store.storeURL) == diskBefore)
        fixture.expectLocalFilesUnchanged()
        try await fixture.expectReloadMatchesCurrentMetadata()
        try fixture.expectNoPendingTransaction()
    }
}
