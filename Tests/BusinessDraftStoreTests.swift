import Foundation
import UIKit
import Testing
@testable import sitekeeper

struct BusinessDraftStoreTests {
    private func temporaryStore() -> BusinessDraftStore {
        BusinessDraftStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("business-draft-test-\(UUID().uuidString)"))
    }

    @Test func financeRoundTripPreservesIncompleteAndHiddenValuesAcrossRestart() throws {
        let store = temporaryStore()
        defer { try? store.removeAll() }
        let key = BusinessDraftStore.Key.finance(projectID: UUID())
        var draft = FinancialFormDraft(recordID: UUID(), date: .instant(Date(timeIntervalSince1970: 100)), direction: .expense,
            category: .material, amount: "12.", counterparty: "  ", invoiceNumber: "", status: .active,
            hasDueDate: false, dueDateText: "2026-10-22", reminderStatus: .pending,
            note: "第一行\n未完成", scanAfterSave: true)
        try store.save(draft, key: key)
        let restarted = BusinessDraftStore(root: store.root)
        #expect(try restarted.load(FinancialFormDraft.self, key: key) == draft)
        draft.amount = ""
        draft.note = ""
        try restarted.save(draft, key: key)
        #expect(try store.load(FinancialFormDraft.self, key: key) == draft)
    }

    @Test func projectAndEditorDraftsAreIsolated() throws {
        let store = temporaryStore()
        defer { try? store.removeAll() }
        let first = UUID(), second = UUID()
        try store.save("project one", key: .daily(projectID: first))
        try store.save("project two", key: .daily(projectID: second))
        try store.save("unassigned", key: .daily(projectID: nil))
        try store.save("editing", key: .dailyEdit(first))
        try store.discard(key: .daily(projectID: first))
        #expect(try store.load(String.self, key: .daily(projectID: first)) == nil)
        #expect(try store.load(String.self, key: .daily(projectID: second)) == "project two")
        #expect(try store.load(String.self, key: .daily(projectID: nil)) == "unassigned")
        #expect(try store.load(String.self, key: .dailyEdit(first)) == "editing")
    }

    @Test func dailyPhotoBytesNotesTagsOrderAndRawFieldsSurviveRestart() throws {
        let store = temporaryStore()
        defer { try? store.removeAll() }
        let project = UUID()
        let key = BusinessDraftStore.Key.daily(projectID: project)
        var composer = DailyLogComposerState(initialProjectId: project)
        composer.workers = "2."
        composer.content = ""
        composer.safety = " 尚未写完 "
        composer.linkedMethodIDs = [UUID()]
        composer.photoDrafts = [PhotoDraft(data: Data([0, 1, 2]), note: "第一张", tag: .general), PhotoDraft(data: Data([3, 4, 5]), note: "", tag: .general)]
        let draft = DailyLogFormDraft(composer: composer, recordID: UUID())
        for photo in composer.photoDrafts { try store.savePhoto(photo.data, id: photo.id, key: key) }
        try store.save(draft, key: key)
        let restarted = BusinessDraftStore(root: store.root)
        let loaded = try restarted.load(DailyLogFormDraft.self, key: key)
        let restored = try #require(loaded)
        let restoredComposer = try restored.composer(store: restarted, key: key)
        #expect(restored == draft)
        #expect(restoredComposer.photoDrafts.map(\.data) == composer.photoDrafts.map(\.data))
        #expect(restoredComposer.photoDrafts.map(\.note) == ["第一张", ""])
        #expect(restoredComposer.workers == "2.")
        #expect(restoredComposer.content.isEmpty)
        // Metadata edits never rewrite or remove imported bytes.
        var edited = restored
        edited.photos[0].note = "补充说明"
        edited.photos.removeLast()
        try restarted.save(edited, key: key)
        #expect(try restarted.photo(id: composer.photoDrafts[1].id, key: key) == Data([3, 4, 5]))
        try restarted.discard(key: key)
        #expect(!FileManager.default.fileExists(atPath: store.root.appendingPathComponent(key.fileName).path))
    }

    @MainActor @Test func failedBusinessSaveRetainsDraftAndPhotoThenRetryClearsExactlyOnce() async throws {
        enum Failure: Error { case injected }
        let store = temporaryStore()
        defer { try? store.removeAll() }
        let key = BusinessDraftStore.Key.daily(projectID: UUID())
        let stableID = UUID(), photoID = UUID()
        try store.save(stableID, key: key)
        try store.savePhoto(Data([7, 8]), id: photoID, key: key)
        do {
            try await store.complete(key: key) { throw Failure.injected }
            Issue.record("Expected injected persistence failure")
        } catch Failure.injected {}
        #expect(try store.load(UUID.self, key: key) == stableID)
        #expect(try store.photo(id: photoID, key: key) == Data([7, 8]))
        var didPersist = false
        try await store.complete(key: key) { didPersist = true }
        #expect(didPersist)
        #expect(try store.load(UUID.self, key: key) == nil)
    }

    @Test func corruptMetadataIsReportedWithoutOverwritingExistingBytes() throws {
        let store = temporaryStore()
        defer { try? store.removeAll() }
        let key = BusinessDraftStore.Key.finance(projectID: UUID())
        try store.save("original", key: key)
        let url = store.root.appendingPathComponent(key.fileName).appendingPathComponent("draft.json")
        let invalid = Data("{broken".utf8)
        try invalid.write(to: url)
        #expect(throws: (any Error).self) { try store.load(String.self, key: key) }
        #expect(try Data(contentsOf: url) == invalid)
    }

    @Test func failedWriteDoesNotDeleteOtherDraftOrPhoto() throws {
        let store = temporaryStore()
        defer { try? store.removeAll() }
        let goodKey = BusinessDraftStore.Key.daily(projectID: UUID())
        let blockedKey = BusinessDraftStore.Key.finance(projectID: UUID())
        let photoID = UUID()
        try store.save("kept", key: goodKey)
        try store.savePhoto(Data([9]), id: photoID, key: goodKey)
        // A regular file where a directory is needed deterministically fails the write.
        try Data([0]).write(to: store.root.appendingPathComponent(blockedKey.fileName))
        #expect(throws: (any Error).self) { try store.save("new", key: blockedKey) }
        #expect(try store.load(String.self, key: goodKey) == "kept")
        #expect(try store.photo(id: photoID, key: goodKey) == Data([9]))
    }

    @Test func storeScopesAreIndependentAndFingerprintsDetectEdits() throws {
        let first = BusinessDraftStore.scoped(to: URL(fileURLWithPath: "/tmp/first/sitekeeper.json"))
        let second = BusinessDraftStore.scoped(to: URL(fileURLWithPath: "/tmp/second/sitekeeper.json"))
        #expect(first.root != second.root)
        var record = ProjectFinancialRecord(projectId: UUID(), amount: NumericInputSupport.money("12"))
        let baseline = BusinessDraftStore.fingerprint(record)
        #expect(BusinessDraftStore.fingerprint(record) == baseline)
        record.note = "other window changed this"
        #expect(BusinessDraftStore.fingerprint(record) != baseline)
    }
    @MainActor @Test func actualFinancialCommitRollsBackFailureThenRetriesWithoutDuplicateOrStaleOverwrite() async throws {
        enum Failure: Error { case injected }
        let drafts = temporaryStore()
        let dataDirectory = drafts.root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        defer { try? drafts.removeAll() }
        let store = DataStore(storageDirectory: dataDirectory)
        // Deliberately do not await initial load: the commit API must do this itself.
        let record = ProjectFinancialRecord(id: UUID(), projectId: UUID(), amount: NumericInputSupport.money("12"), note: "draft")
        let key = BusinessDraftStore.Key.finance(projectID: record.projectId)
        try drafts.save(record.id, key: key)
        do {
            try await drafts.commitNewFinancialRecord(record, in: store, persist: { throw Failure.injected })
            Issue.record("Expected injected save failure")
        } catch Failure.injected {}
        #expect(store.projectFinancialRecords.isEmpty)
        #expect(try drafts.load(UUID.self, key: key) == record.id)
        try await drafts.commitNewFinancialRecord(record, in: store)
        #expect(store.projectFinancialRecords.map(\.id) == [record.id])
        #expect(try drafts.load(UUID.self, key: key) == nil)
        let restarted = DataStore(storageDirectory: dataDirectory)
        await restarted.awaitInitialLoad()
        #expect(restarted.projectFinancialRecords.map(\.id) == [record.id])
        var newer = record
        newer.note = "edited after save"
        restarted.updateProjectFinancialRecord(newer)
        try drafts.save(record.id, key: key)
        await #expect(throws: (any Error).self) {
            try await drafts.commitNewFinancialRecord(record, in: restarted)
        }
        #expect(restarted.projectFinancialRecords.count == 1)
        #expect(restarted.projectFinancialRecords.first?.note == newer.note)
        #expect(try drafts.load(UUID.self, key: key) == record.id)
    }

    @Test func pendingPhotoLedgerSurvivesRestartAndPreservesEveryAttemptUntilDiscard() throws {
        let store = temporaryStore()
        defer { try? store.removeAll() }
        let key = BusinessDraftStore.Key.daily(projectID: UUID())
        let first = UUID(), retry = UUID()
        try store.registerPhotoAttempt(id: first, count: 2, key: key)
        let restarted = BusinessDraftStore(root: store.root)
        try restarted.registerPhotoAttempt(id: retry, count: 1, key: key)
        #expect(Set(try restarted.pendingPhotoFiles(key: key)) == [first.uuidString + ".jpg", first.uuidString + "-1.jpg", retry.uuidString + ".jpg"])
        try restarted.discard(key: key)
        #expect(try restarted.pendingPhotoFiles(key: key).isEmpty)
    }

    @MainActor @Test func photoAndMetadataFailureKeepsPreviouslySavedOriginalBytesAndRecord() async throws {
        enum Failure: Error { case injected }
        let drafts = temporaryStore()
        defer { try? drafts.removeAll() }
        let dataDirectory = drafts.root.appendingPathComponent("data")
        let photoDirectory = drafts.root.appendingPathComponent("photo-storage")
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: dataDirectory)
        await store.awaitInitialLoad()
        func jpeg(_ color: UIColor) -> Data {
            UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).jpegData(withCompressionQuality: 0.9) { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
        }
        let originalNames = try PhotoStorage.saveManyOrThrow(originals: [jpeg(.red)], logId: UUID(), directory: photoDirectory)
        let originalURL = photoDirectory.appendingPathComponent("Photos").appendingPathComponent(originalNames[0])
        let originalBytes = try Data(contentsOf: originalURL)
        let project = UUID()
        let originalLog = DailyLog(date: BusinessDateValue(legacyText: "2026-10-22"), weather: "晴", content: "already saved", workers: NumericInputSupport.quantity("1"), photoFileName: originalNames[0], photos: [LogPhoto(fileName: originalNames[0])], projectId: project)
        store.insertDailyLogAtTop(originalLog)
        try await store.flushSaveOrThrow()
        let attemptID = UUID()
        let key = BusinessDraftStore.Key.daily(projectID: project)
        try drafts.registerPhotoAttempt(id: attemptID, count: 1, key: key)
        let newNames = try PhotoStorage.saveManyOrThrow(originals: [jpeg(.blue)], logId: attemptID, directory: photoDirectory)
        let newLog = DailyLog(date: BusinessDateValue(legacyText: "2026-10-22"), weather: "晴", content: "new draft", workers: NumericInputSupport.quantity(""), photoFileName: newNames[0], photos: [LogPhoto(fileName: newNames[0])], projectId: project)
        try drafts.save(newLog.id, key: key)
        do {
            try await drafts.commitNewDailyLog(newLog, in: store, persist: { throw Failure.injected })
            Issue.record("Expected metadata persistence failure")
        } catch Failure.injected {}
        #expect(store.dailyLogs.map(\.id) == [originalLog.id])
        #expect(try Data(contentsOf: originalURL) == originalBytes)
        #expect(try drafts.load(UUID.self, key: key) == newLog.id)
        #expect(try drafts.pendingPhotoFiles(key: key) == newNames)
        try await drafts.commitNewDailyLog(newLog, in: store)
        #expect(store.dailyLogs.count == 2)
        #expect(try Data(contentsOf: originalURL) == originalBytes)
        await #expect(throws: (any Error).self) { try await drafts.commitNewDailyLog(newLog, in: store) }
        #expect(store.dailyLogs.count == 2)
    }
}
