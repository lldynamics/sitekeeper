import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct RepositoryQuoteModelTests {
    private static func sample() -> BackupSnapshot {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.quoteItems.append(RepositoryQuoteTests.item(price: "0", status: .sent))
        return snapshot
    }

    @Test func failedPagingRetainsSnapshotAndFilteringClearsStaleTotals() async throws {
        let repository = try RepositoryControlledRepository(snapshot: Self.sample())
        let model = RepositoryPageModel(repository: repository, query: RepositoryQuery(collection: .quoteItems), pageSize: 1)
        await model.reset()
        let summary = model.quoteSummary
        let items = model.items
        #expect(summary?.amounts?.total == Decimal(string: "7.05"))
        await repository.failReads(true)
        await model.next()
        #expect(model.pageNumber == 1 && model.items == items && model.quoteSummary == summary && model.errorMessage != nil)
        await repository.failReads(false)
        await model.next()
        #expect(model.pageNumber == 2 && model.quoteSummary == summary)
        let held = Task { await model.reset(to: RepositoryQuery(collection: .quoteItems, searchText: "hold")) }
        await repository.waitUntilBlocked()
        #expect(model.items.isEmpty && model.quoteSummary == nil)
        await model.reset(to: RepositoryQuery(collection: .quoteItems, quoteStatus: .sent))
        #expect(model.quoteSummary?.amounts?.total == 0 && model.quoteSummary?.count == 1)
        await repository.release()
        await held.value
        #expect(model.quoteSummary?.amounts?.total == 0 && model.items.count == 1)
        await model.reset(to: RepositoryQuery(collection: .projects))
        #expect(model.quoteSummary == nil)
    }

    @Test func quoteSaveFailureAndConflictKeepRawDraftForReview() async throws {
        let snapshot = Self.sample()
        let repository = try RepositoryControlledRepository(snapshot: snapshot)
        let record = snapshot.quoteItems[0]
        let editor = RepositoryRecordEditor(repository: repository, collection: .quoteItems, id: record.id, initial: RepositoryQuoteDraft(record: record))
        await editor.load()
        editor.draft.unitPriceText = "12oops"
        #expect(await editor.save { try $0.command() } == false)
        #expect(editor.draft.unitPriceText == "12oops" && editor.revision == 0)
        editor.draft.unitPriceText = "12.34"
        await repository.failWrites(true)
        #expect(await editor.save { try $0.command() } == false)
        #expect(editor.draft.unitPriceText == "12.34" && editor.revision == 0)
        await repository.failWrites(false)
        var remote = record
        remote.unitPrice = NumericInputSupport.money("45.67")
        _ = try await repository.apply([.putQuoteItem(remote)], expectedRevision: 0)
        #expect(await editor.save { try $0.command() } == false)
        #expect(editor.draft.unitPriceText == "12.34" && editor.errorMessage != nil)
        await editor.load()
        #expect(editor.draft.unitPriceText == "45.67")
        editor.draft.unitPriceText = "9007199254740993.01"
        #expect(await editor.save { try $0.command() })
        #expect(try await repository.revision() == 2)
        let payload = try #require(try await repository.record(.quoteItems, id: record.id))
        #expect(try JSONDecoder().decode(QuoteItem.self, from: payload).unitPrice.wireText == "9007199254740993.01")
    }
}
