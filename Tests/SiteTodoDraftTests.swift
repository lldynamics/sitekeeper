import Foundation
import UIKit
import Testing
@testable import sitekeeper

@MainActor
struct SiteTodoDraftTests {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("todo-draft-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func rawFieldsDatePhotoBlobsAndAssociationsSurviveRestartWithoutBusinessWrites() throws {
        let root = try temporaryRoot()
        let drafts = BusinessDraftStore(root: root)
        defer { try? drafts.removeAll() }
        let projectID = UUID(), photoID = UUID()
        let key = BusinessDraftStore.Key.todo(projectID: projectID)
        let record = SiteTodo(title: "  unfinished\n", owner: "  Owner  ", dueDate: BusinessDateValue(legacyText: "2026-11-05"), priority: .high, issueType: .quality, drawingIssueLocation: "Floor 3", drawingIssueCloseEvidence: "awaiting", note: " line one\nline two ", linkedConstructionMethodIDs: [UUID()], projectId: projectID)
        let draft = SiteTodoFormDraft(record: record, beforePhotoID: photoID)
        let data = Data([7, 8, 9])
        try drafts.savePhoto(data, id: photoID, key: key)
        try drafts.save(draft, key: key)
        let restarted = BusinessDraftStore(root: root)
        let restored = try #require(try restarted.load(SiteTodoFormDraft.self, key: key))
        #expect(restored == draft)
        #expect(restored.record.title == "  unfinished\n")
        #expect(restored.record.owner == "  Owner  ")
        #expect(restored.record.dueDate.storageText == "2026-11-05")
        #expect(try restarted.photo(id: photoID, key: key) == data)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("sitekeeper.json").path))
    }

    @Test func newEditorProjectAndUnassignedKeysDoNotCollideAndDiscardIsScoped() throws {
        let drafts = BusinessDraftStore(root: try temporaryRoot())
        defer { try? drafts.removeAll() }
        let id = UUID(), other = UUID()
        let keys: [BusinessDraftStore.Key] = [.todo(projectID: id), .todo(projectID: other), .todo(projectID: nil), .todoEdit(id), .daily(projectID: id), .finance(projectID: id)]
        for (index, key) in keys.enumerated() { try drafts.save(index, key: key) }
        try drafts.discard(key: .todo(projectID: id))
        #expect(try drafts.load(Int.self, key: keys[0]) == nil)
        for index in 1..<keys.count { #expect(try drafts.load(Int.self, key: keys[index]) == index) }
    }

    @Test func failedSaveRollsBackOnlyItsRecordRetainsDraftThenRetryCommitsExactlyOnce() async throws {
        enum Failure: Error { case injected }
        let root = try temporaryRoot()
        let store = DataStore(storageDirectory: root)
        await store.awaitInitialLoad()
        let drafts = BusinessDraftStore.scoped(to: store.storeURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = SiteTodo(title: "Unrelated original")
        store.appendSiteTodo(existing)
        try await store.flushSaveOrThrow()
        let draft = SiteTodoFormDraft(record: SiteTodo(title: "  New record  ", owner: " Owner "))
        let key = BusinessDraftStore.Key.todo(projectID: nil)
        try drafts.save(draft, key: key)
        do {
            _ = try await drafts.commitTodo(draft, key: key, editing: false, in: store, persist: { throw Failure.injected })
            Issue.record("Expected persistence failure")
        } catch Failure.injected {}
        #expect(store.siteTodos.map(\.id) == [existing.id])
        #expect(try drafts.load(SiteTodoFormDraft.self, key: key) == draft)
        let saved = try await drafts.commitTodo(draft, key: key, editing: false, in: store)
        #expect(saved.title == "New record")
        #expect(saved.owner == "Owner")
        #expect(store.siteTodos.count == 2)
        #expect(try drafts.load(SiteTodoFormDraft.self, key: key) == nil)
        let restarted = DataStore(storageDirectory: root)
        await restarted.awaitInitialLoad()
        #expect(Set(restarted.siteTodos.map(\.id)) == [existing.id, saved.id])
        try drafts.save(draft, key: key)
        await #expect(throws: (any Error).self) { _ = try await drafts.commitTodo(draft, key: key, editing: false, in: restarted) }
        #expect(restarted.siteTodos.count == 2)
        #expect(try drafts.load(SiteTodoFormDraft.self, key: key) == draft)
    }

    @Test func editingConflictAndDeletionCannotOverwriteOrRecreateOriginal() async throws {
        let root = try temporaryRoot()
        let store = DataStore(storageDirectory: root)
        await store.awaitInitialLoad()
        let drafts = BusinessDraftStore.scoped(to: store.storeURL)
        defer { try? FileManager.default.removeItem(at: root) }
        var original = SiteTodo(title: "Original", note: "original")
        store.appendSiteTodo(original)
        var draft = SiteTodoFormDraft(record: original, baseRecord: BusinessDraftStore.fingerprint(original))
        draft.record.note = "unsaved editor"
        let key = BusinessDraftStore.Key.todoEdit(original.id)
        try drafts.save(draft, key: key)
        original.note = "newer window"
        store.updateSiteTodo(original)
        await #expect(throws: (any Error).self) { _ = try await drafts.commitTodo(draft, key: key, editing: true, in: store) }
        #expect(store.siteTodos.first?.note == "newer window")
        #expect(try drafts.load(SiteTodoFormDraft.self, key: key) == draft)
        store.removeSiteTodos(ids: [original.id])
        await #expect(throws: (any Error).self) { _ = try await drafts.commitTodo(draft, key: key, editing: true, in: store) }
        #expect(store.siteTodos.isEmpty)
    }

    @Test func successfulEditPreservesOtherRecordsAndClearsOnlyItsOwnDraft() async throws {
        let root = try temporaryRoot()
        let store = DataStore(storageDirectory: root)
        await store.awaitInitialLoad()
        let drafts = BusinessDraftStore.scoped(to: store.storeURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = SiteTodo(title: "Original"), other = SiteTodo(title: "Other", note: "keep")
        store.replaceSiteTodos([original, other])
        let key = BusinessDraftStore.Key.todoEdit(original.id)
        var draft = SiteTodoFormDraft(record: original, baseRecord: BusinessDraftStore.fingerprint(original))
        draft.record.title = "Updated"
        draft.record.isDone = true
        try drafts.save(draft, key: key)
        try drafts.save("other form", key: .todo(projectID: nil))
        let updated = try await drafts.commitTodo(draft, key: key, editing: true, in: store)
        #expect(updated.id == original.id)
        #expect(updated.title == "Updated")
        #expect(updated.completedAt != nil)
        #expect(store.siteTodos.first { $0.id == other.id }?.note == "keep")
        #expect(try drafts.load(SiteTodoFormDraft.self, key: key) == nil)
        #expect(try drafts.load(String.self, key: .todo(projectID: nil)) == "other form")
    }

    @Test func bothPhotosRemainDraftOnlyUntilSaveAndSurviveFailedSave() async throws {
        enum Failure: Error { case injected }
        let root = try temporaryRoot()
        let store = DataStore(storageDirectory: root)
        await store.awaitInitialLoad()
        let drafts = BusinessDraftStore.scoped(to: store.storeURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = BusinessDraftStore.Key.todo(projectID: nil)
        let first = UUID(), second = UUID()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let draft = SiteTodoFormDraft(record: SiteTodo(title: "Photo evidence"), beforePhotoID: first, afterPhotoID: second)
        try drafts.savePhoto(image, id: first, key: key)
        try drafts.savePhoto(image, id: second, key: key)
        try drafts.save(draft, key: key)
        do {
            _ = try await drafts.commitTodo(draft, key: key, editing: false, in: store, persist: { throw Failure.injected })
            Issue.record("Expected save failure")
        } catch Failure.injected {}
        #expect(store.siteTodos.isEmpty)
        #expect(try drafts.photo(id: first, key: key) == image)
        #expect(try drafts.photo(id: second, key: key) == image)
        let saved = try await drafts.commitTodo(draft, key: key, editing: false, in: store)
        let before = try #require(saved.rectificationBeforePhotoFileName)
        let after = try #require(saved.rectificationAfterPhotoFileName)
        defer { PhotoStorage.delete(fileNames: [before, after]) }
        #expect(before != after)
        #expect(try Data(contentsOf: PhotoStorage.fileURL(for: before)) == image)
        #expect(try Data(contentsOf: PhotoStorage.fileURL(for: after)) == image)
        #expect(try drafts.load(SiteTodoFormDraft.self, key: key) == nil)
    }

    @Test func replacingPhotoKeepsOriginalOnFailureAndPreservesSharedSourceAfterSuccess() async throws {
        enum Failure: Error { case injected }
        let root = try temporaryRoot()
        let store = DataStore(storageDirectory: root)
        await store.awaitInitialLoad()
        let drafts = BusinessDraftStore.scoped(to: store.storeURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let originalName = try PhotoStorage.saveOrThrow(original: image, logId: UUID())
        let original = SiteTodo(title: "Original evidence", rectificationBeforePhotoFileName: originalName)
        store.appendSiteTodo(original)
        store.insertDailyLogAtTop(DailyLog(date: .today(), weather: "", content: "Shared evidence", workers: .zero, photoFileName: originalName))
        let key = BusinessDraftStore.Key.todoEdit(original.id)
        let photoID = UUID()
        let draft = SiteTodoFormDraft(record: original, baseRecord: BusinessDraftStore.fingerprint(original), beforePhotoID: photoID)
        try drafts.savePhoto(image, id: photoID, key: key)
        try drafts.save(draft, key: key)
        do {
            _ = try await drafts.commitTodo(draft, key: key, editing: true, in: store, persist: { throw Failure.injected })
            Issue.record("Expected persistence failure")
        } catch Failure.injected {}
        #expect(store.siteTodos.first?.rectificationBeforePhotoFileName == originalName)
        #expect(try Data(contentsOf: PhotoStorage.fileURL(for: originalName)) == image)
        let saved = try await drafts.commitTodo(draft, key: key, editing: true, in: store)
        let replacement = try #require(saved.rectificationBeforePhotoFileName)
        defer { PhotoStorage.delete(fileNames: [originalName, replacement]) }
        #expect(replacement != originalName)
        #expect(try Data(contentsOf: PhotoStorage.fileURL(for: originalName)) == image)
        #expect(store.dailyLogs.first?.photoFileName == originalName)
    }

    @Test func missingPhotoOrRemovedProjectRetainsOriginalDraftAndBusinessData() async throws {
        let root = try temporaryRoot()
        let store = DataStore(storageDirectory: root)
        await store.awaitInitialLoad()
        let drafts = BusinessDraftStore.scoped(to: store.storeURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = BusinessDraftStore.Key.todo(projectID: nil)
        var draft = SiteTodoFormDraft(record: SiteTodo(title: "Missing photo"), beforePhotoID: UUID())
        try drafts.save(draft, key: key)
        await #expect(throws: (any Error).self) { _ = try await drafts.commitTodo(draft, key: key, editing: false, in: store) }
        #expect(store.siteTodos.isEmpty)
        #expect(try drafts.load(SiteTodoFormDraft.self, key: key) == draft)
        draft.beforePhotoID = nil
        draft.record.projectId = UUID()
        try drafts.save(draft, key: key)
        await #expect(throws: (any Error).self) { _ = try await drafts.commitTodo(draft, key: key, editing: false, in: store) }
        #expect(store.siteTodos.isEmpty)
        #expect(try drafts.load(SiteTodoFormDraft.self, key: key) == draft)
        try drafts.discardTodo(key: key, in: store)
        #expect(try drafts.load(SiteTodoFormDraft.self, key: key) == nil)
    }
}
