import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct RepositoryLaborModelTests {
    private static func sample() -> BackupSnapshot {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.laborRecords = [RepositoryLaborTests.item(), RepositoryLaborTests.item(rate: "0", settled: true)]
        return snapshot
    }

    @Test func failedPagingRetainsSnapshotAndFilteringClearsStaleTotals() async throws {
        let repository = try RepositoryControlledRepository(snapshot: Self.sample())
        let model = RepositoryPageModel(repository: repository, query: RepositoryQuery(collection: .laborRecords), pageSize: 1)
        await model.reset()
        let summary = model.laborSummary
        let items = model.items
        #expect(summary?.total == Decimal(string: "0.06"))
        await repository.failReads(true)
        await model.next()
        #expect(model.pageNumber == 1 && model.items == items && model.laborSummary == summary && model.errorMessage != nil)
        await repository.failReads(false)
        await model.next()
        #expect(model.pageNumber == 2 && model.laborSummary == summary)
        let held = Task { await model.reset(to: RepositoryQuery(collection: .laborRecords, searchText: "hold")) }
        await repository.waitUntilBlocked()
        #expect(model.items.isEmpty && model.laborSummary == nil)
        await model.reset(to: RepositoryQuery(collection: .laborRecords, laborSettled: true))
        #expect(model.laborSummary?.total == 0 && model.laborSummary?.count == 1)
        await repository.release()
        await held.value
        #expect(model.laborSummary?.total == 0 && model.items.count == 1)
        await model.reset(to: RepositoryQuery(collection: .projects))
        #expect(model.laborSummary == nil)
    }

    @Test func laborSaveFailureAndConflictKeepRawDraftForReview() async throws {
        let snapshot = Self.sample()
        let repository = try RepositoryControlledRepository(snapshot: snapshot)
        let record = snapshot.laborRecords[0]
        let editor = RepositoryRecordEditor(repository: repository, collection: .laborRecords, id: record.id, initial: RepositoryLaborDraft(record: record))
        await editor.load()
        editor.draft.unitRateText = "12oops"
        #expect(await editor.save { try $0.command() } == false)
        #expect(editor.draft.unitRateText == "12oops" && editor.revision == 0)
        editor.draft.unitRateText = "12.34"
        await repository.failWrites(true)
        #expect(await editor.save { try $0.command() } == false)
        #expect(editor.draft.unitRateText == "12.34" && editor.revision == 0)
        await repository.failWrites(false)
        var remote = record
        remote.unitRate = NumericInputSupport.money("45.67")
        _ = try await repository.apply([.putLaborRecord(remote)], expectedRevision: 0)
        #expect(await editor.save { try $0.command() } == false)
        #expect(editor.draft.unitRateText == "12.34" && editor.errorMessage != nil)
        await editor.load()
        #expect(editor.draft.unitRateText == "45.67")
        editor.draft.unitRateText = "9007199254740993.01"
        #expect(await editor.save { try $0.command() })
        #expect(try await repository.revision() == 2)
        let payload = try #require(try await repository.record(.laborRecords, id: record.id))
        #expect(try JSONDecoder().decode(LaborRecord.self, from: payload).unitRate.wireText == "9007199254740993.01")
    }
}
