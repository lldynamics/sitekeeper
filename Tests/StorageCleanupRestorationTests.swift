import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct StorageCleanupRestorationTests {
    @Test func restoredDrawingFiltersStaleLinksAndPreservesLaterCurrentVersion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-drawing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        defer {
            store.cancelScheduledSave()
            try? FileManager.default.removeItem(at: directory)
        }
        let project = Project(name: "Drawings", location: "", status: .active)
        let otherProject = Project(name: "Other", location: "", status: .active)
        store.replaceProjects([project, otherProject])
        let keptTodo = SiteTodo(title: "keep", projectId: project.id)
        let deletedTodo = SiteTodo(title: "delete later", projectId: project.id)
        let otherTodo = SiteTodo(title: "other project", projectId: otherProject.id)
        let keptLog = DailyLog(date: BusinessDateValue(legacyText: "2026-10-15"), weather: "", content: "keep", workers: NumericInputSupport.quantity("1"), projectId: project.id)
        let deletedLog = DailyLog(date: BusinessDateValue(legacyText: "2026-10-15"), weather: "", content: "delete later", workers: NumericInputSupport.quantity("1"), projectId: project.id)
        let otherLog = DailyLog(date: BusinessDateValue(legacyText: "2026-10-15"), weather: "", content: "other project", workers: NumericInputSupport.quantity("1"), projectId: otherProject.id)
        let keptDocument = ProjectDocument(projectId: project.id, title: "keep", fileName: "keep.pdf")
        let deletedDocument = ProjectDocument(projectId: project.id, title: "delete later", fileName: "delete.pdf")
        let otherDocument = ProjectDocument(projectId: otherProject.id, title: "other project", fileName: "other.pdf")
        store.replaceSiteTodos([keptTodo, deletedTodo, otherTodo])
        store.replaceDailyLogs([keptLog, deletedLog, otherLog])
        store.replaceProjectDocuments([keptDocument, deletedDocument, otherDocument])
        let old = ProjectDrawing(
            projectId: project.id, name: "Plan", fileName: "v1.pdf", fileType: "pdf", version: "V1",
            linkedTodoIDs: [keptTodo.id, deletedTodo.id, otherTodo.id],
            linkedLogIDs: [keptLog.id, deletedLog.id, otherLog.id],
            linkedDocumentIDs: [keptDocument.id, deletedDocument.id, otherDocument.id]
        )
        store.replaceProjectDrawings([old])
        let before = StorageCleanupUndoSnapshot.capture(from: store)
        store.clearProjectDrawingSourceReferences(projectId: project.id, drawingFileExtensions: ["pdf"])
        let delta = try before.scopedForRestoration(after: store)
        store.replaceSiteTodos([keptTodo, otherTodo])
        store.replaceDailyLogs([keptLog, otherLog])
        store.replaceProjectDocuments([keptDocument, otherDocument])
        let current = ProjectDrawing(projectId: project.id, name: "Plan", fileName: "v2.pdf", fileType: "pdf", version: "V2", note: "later current state")
        let untouched = ProjectDrawing(projectId: project.id, name: "Other plan", fileName: "other.pdf", fileType: "pdf", linkedTodoIDs: [deletedTodo.id])
        store.replaceProjectDrawings([current, untouched])
        try delta.restore(into: store)
        let restored = try #require(store.projectDrawings.first { $0.id == old.id })
        #expect(restored.linkedTodoIDs == [keptTodo.id])
        #expect(restored.linkedLogIDs == [keptLog.id])
        #expect(restored.linkedDocumentIDs == [keptDocument.id])
        #expect(!restored.isCurrentVersion)
        #expect(store.projectDrawings.first { $0.id == current.id }?.isCurrentVersion == true)
        #expect(store.projectDrawings.first { $0.id == current.id }?.note == "later current state")
        #expect(store.projectDrawings.first { $0.id == untouched.id }?.linkedTodoIDs == [deletedTodo.id])
    }

    @Test func restoringCleanupMergesReferencesAndPreservesLaterRecordChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-delta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        defer { store.cancelScheduledSave()
        try? FileManager.default.removeItem(at: directory) }
        let project = Project(name: "Clean", location: "", status: .active)
        let other = Project(name: "Other", location: "", status: .active)
        store.replaceProjects([project, other])
        let name = "cleanup-delta-\(UUID().uuidString).mov"
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([1, 2, 3]), fileName: name)
        defer { StorageCleanupTrashTestSupport.removeFileIfExists(QuickNoteAttachmentStorage.fileURL(for: name)) }
        let attachment = QuickNoteAttachment(kind: .video, fileName: name)
        let original = QuickNote(content: "before", projectId: project.id, attachments: [attachment])
        let deletedLater = QuickNote(content: "delete later", projectId: other.id)
        store.replaceQuickNotes([original, deletedLater])
        try StorageCleanupTrashStore.withRootURLForTesting(directory.appendingPathComponent("trash")) {
            let batch = try StorageCleanupExecutionService.cleanupProjectFiles(
                store: store, projectId: project.id, category: .videos, retentionDays: 7,
                summary: "videos", videoFileExtensions: ["mov"], drawingSourceFileExtensions: ["pdf"]
            )
            #expect(batch.snapshot.quickNotes.isEmpty)
            #expect(batch.snapshot.delta?.quickNotes.count == 1)
            let retainedAttachment = QuickNoteAttachment(kind: .file, fileName: "later.txt")
            var edited = try #require(store.quickNotes.first { $0.id == original.id })
            edited.content = "edited after cleanup"
            edited.attachments.append(retainedAttachment)
            let newNote = QuickNote(content: "added later", projectId: other.id)
            store.replaceQuickNotes([edited, newNote])
            // Decode the on-disk batch to prove the delta survives relaunch.
            let persisted = try #require(StorageCleanupTrashStore.loadBatches().first)
            try StorageCleanupExecutionService.restoreCleanupTrash(persisted, store: store)
            let restored = try #require(store.quickNotes.first { $0.id == original.id })
            #expect(restored.content == "edited after cleanup")
            #expect(Set(restored.attachments.map(\.id)) == [attachment.id, retainedAttachment.id])
            #expect(store.quickNotes.contains { $0.id == newNote.id })
            #expect(!store.quickNotes.contains { $0.id == deletedLater.id })
            #expect(QuickNoteAttachmentStorage.data(for: name) == Data([1, 2, 3]))
            #expect(StorageCleanupTrashStore.loadBatches().isEmpty)
        }
    }

    @Test func cleanupDeltaDoesNotResurrectLaterDeletedRowsOrProjects() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-deleted-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        defer { store.cancelScheduledSave()
        try? FileManager.default.removeItem(at: directory) }
        let project = Project(name: "Removed later", location: "", status: .active)
        store.replaceProjects([project])
        let note = QuickNote(projectId: project.id, attachments: [QuickNoteAttachment(kind: .video, fileName: "video.mov")])
        let document = ProjectDocument(projectId: project.id, title: "Receipt", category: .receipt, fileName: "receipt.pdf")
        store.replaceQuickNotes([note])
        store.replaceProjectDocuments([document])
        let before = StorageCleanupUndoSnapshot.capture(from: store)
        store.clearProjectVideoReferences(projectId: project.id, videoFileExtensions: ["mov"])
        store.clearProjectTicketDocumentReferences(projectId: project.id)
        let delta = try before.scopedForRestoration(after: store)
        store.replaceQuickNotes([])
        store.replaceProjects([])
        try delta.restore(into: store)
        #expect(store.quickNotes.isEmpty)
        #expect(store.projectDocuments.isEmpty)
    }

    @Test func ticketRestorationPreservesNewFinancialValuesAndDocumentLinks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-ticket-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        defer { store.cancelScheduledSave()
        try? FileManager.default.removeItem(at: directory) }
        let project = Project(name: "Tickets", location: "", status: .active)
        store.replaceProjects([project])
        let ticket = ProjectDocument(projectId: project.id, title: "Receipt", category: .receipt, fileName: "receipt.pdf")
        let later = ProjectDocument(projectId: project.id, title: "Later", fileName: "later.pdf")
        let record = ProjectFinancialRecord(projectId: project.id, amount: NumericInputSupport.money("10"), linkedDocumentIds: [ticket.id])
        store.replaceProjectDocuments([ticket])
        store.replaceProjectFinancialRecords([record])
        let before = StorageCleanupUndoSnapshot.capture(from: store)
        store.clearProjectTicketDocumentReferences(projectId: project.id)
        let delta = try before.scopedForRestoration(after: store)
        store.replaceProjectDocuments([later])
        var edited = try #require(store.projectFinancialRecords.first)
        edited.amount = NumericInputSupport.money("50")
        edited.linkedDocumentIds = [later.id]
        store.replaceProjectFinancialRecords([edited])
        try delta.restore(into: store)
        #expect(store.projectFinancialRecords.first?.amount.wireText == "50")
        #expect(Set(store.projectFinancialRecords.first?.linkedDocumentIds ?? []) == [ticket.id, later.id])
        #expect(Set(store.projectDocuments.map(\.id)) == [ticket.id, later.id])
    }

    @Test func legacyBatchIsRejectedBeforeMovingFilesOrRemovingBatch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        defer { store.cancelScheduledSave()
        try? FileManager.default.removeItem(at: directory) }
        let name = "legacy-cleanup-\(UUID().uuidString).bin"
        let bytes = Data([8, 9])
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(bytes, fileName: name)
        defer { StorageCleanupTrashTestSupport.removeFileIfExists(QuickNoteAttachmentStorage.fileURL(for: name)) }
        try StorageCleanupTrashStore.withRootURLForTesting(directory.appendingPathComponent("trash")) {
            // A legacy JSON object has no delta key, just the seven original collections.
            let legacyData = Data(#"{"dailyLogs":[],"siteTodos":[],"quickNotes":[],"projectDrawings":[],"projectDocuments":[],"projectFinancialRecords":[],"projectWarehouseMovements":[]}"#.utf8)
            let snapshot = try JSONDecoder().decode(StorageCleanupUndoSnapshot.self, from: legacyData)
            let batch = try StorageCleanupTrashStore.quarantine(plan: .init(quickNoteAttachmentFileNames: [name]), snapshot: snapshot, summary: "legacy", retentionDays: 7)
            let current = QuickNote(content: "keep current")
            store.replaceQuickNotes([current])
            #expect(throws: StorageCleanupRestoreError.self) { try StorageCleanupExecutionService.restoreCleanupTrash(batch, store: store) }
            #expect(store.quickNotes.map(\.id) == [current.id])
            #expect(StorageCleanupTrashStore.loadBatches().map(\.id) == [batch.id])
            #expect(!QuickNoteAttachmentStorage.exists(fileName: name))
            let file = try #require(batch.files.first)
            let trashed = try StorageCleanupTrashStore.rootURLForTesting().appendingPathComponent(batch.id.uuidString).appendingPathComponent(file.kind.rawValue).appendingPathComponent(file.trashedFileName)
            #expect(try Data(contentsOf: trashed) == bytes)
        }
    }
}
