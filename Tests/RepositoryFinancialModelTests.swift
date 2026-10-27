import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct RepositoryFinancialModelTests {
    @Test func failedPagingRetainsSnapshotAndFilteringClearsStaleTotals() async throws {
        let repository = try RepositoryControlledRepository(snapshot: RepositoryTestFixture.sample())
        let model = RepositoryPageModel(repository: repository, query: RepositoryQuery(collection: .projectFinancialRecords), pageSize: 1)
        await model.reset()
        let summary = model.financialSummary
        let items = model.items
        #expect(summary?.income == Decimal(string: "0.3"))
        await repository.failReads(true)
        await model.next()
        #expect(model.pageNumber == 1 && model.items == items && model.financialSummary == summary && model.errorMessage != nil)
        await repository.failReads(false)
        await model.next()
        #expect(model.pageNumber == 2 && model.financialSummary == summary)
        let held = Task { await model.reset(to: RepositoryQuery(collection: .projectFinancialRecords, searchText: "hold")) }
        await repository.waitUntilBlocked()
        #expect(model.items.isEmpty && model.financialSummary == nil)
        await model.reset(to: RepositoryQuery(collection: .projectFinancialRecords, financialDirection: .expense))
        #expect(model.financialSummary?.income == 0 && model.financialSummary?.expense == Decimal(string: "100.01"))
        await repository.release()
        await held.value
        #expect(model.financialSummary?.expense == Decimal(string: "100.01") && model.items.count == 1)
        await model.reset(to: RepositoryQuery(collection: .projects))
        #expect(model.financialSummary == nil)
    }

    @Test func financeSaveFailureAndConflictKeepRawDraftForReview() async throws {
        let snapshot = RepositoryTestFixture.sample()
        let repository = try RepositoryControlledRepository(snapshot: snapshot)
        let record = snapshot.projectFinancialRecords[0]
        let editor = RepositoryRecordEditor(repository: repository, collection: .projectFinancialRecords, id: record.id, initial: RepositoryFinancialDraft(record: record))
        await editor.load()
        editor.draft.amountText = "12oops"
        #expect(await editor.save { try $0.command() } == false)
        #expect(editor.draft.amountText == "12oops" && editor.revision == 0)
        editor.draft.amountText = "12.34"
        await repository.failWrites(true)
        #expect(await editor.save { try $0.command() } == false)
        #expect(editor.draft.amountText == "12.34" && editor.revision == 0)
        await repository.failWrites(false)
        var remote = record
        remote.amount = NumericInputSupport.money("45.67")
        _ = try await repository.apply([.putFinancialRecord(remote)], expectedRevision: 0)
        #expect(await editor.save { try $0.command() } == false)
        #expect(editor.draft.amountText == "12.34" && editor.errorMessage != nil)
        await editor.load()
        #expect(editor.draft.amountText == "45.67")
        editor.draft.amountText = "9007199254740993.01"
        #expect(await editor.save { try $0.command() })
        #expect(try await repository.revision() == 2)
        let payload = try #require(try await repository.record(.projectFinancialRecords, id: record.id))
        #expect(try JSONDecoder().decode(ProjectFinancialRecord.self, from: payload).amount.wireText == "9007199254740993.01")
    }
}
