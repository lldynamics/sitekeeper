import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct RepositoryMaterialModelTests {
    private static func sample() -> BackupSnapshot {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.materialItems.append(MaterialItem(name: "免费材料", quantity: NumericInputSupport.quantity("1"), unit: "件", unitPrice: NumericInputSupport.money("0"), purchaseStatus: .used))
        return snapshot
    }

    @Test func failedPagingRetainsSnapshotAndFilteringClearsStaleTotals() async throws {
        let repository = try RepositoryControlledRepository(snapshot: Self.sample())
        let model = RepositoryPageModel(repository: repository, query: RepositoryQuery(collection: .materialItems), pageSize: 1)
        await model.reset()
        let summary = model.materialSummary
        let items = model.items
        #expect(summary?.total == Decimal(string: "7.8"))
        await repository.failReads(true)
        await model.next()
        #expect(model.pageNumber == 1 && model.items == items && model.materialSummary == summary && model.errorMessage != nil)
        await repository.failReads(false)
        await model.next()
        #expect(model.pageNumber == 2 && model.materialSummary == summary)
        let held = Task { await model.reset(to: RepositoryQuery(collection: .materialItems, searchText: "hold")) }
        await repository.waitUntilBlocked()
        #expect(model.items.isEmpty && model.materialSummary == nil)
        await model.reset(to: RepositoryQuery(collection: .materialItems, materialStatus: .used))
        #expect(model.materialSummary?.total == 0 && model.materialSummary?.count == 1)
        await repository.release()
        await held.value
        #expect(model.materialSummary?.total == 0 && model.items.count == 1)
        await model.reset(to: RepositoryQuery(collection: .projects))
        #expect(model.materialSummary == nil)
    }

    @Test func materialSaveFailureAndConflictKeepRawDraftForReview() async throws {
        let snapshot = Self.sample()
        let repository = try RepositoryControlledRepository(snapshot: snapshot)
        let record = snapshot.materialItems[0]
        let editor = RepositoryRecordEditor(repository: repository, collection: .materialItems, id: record.id, initial: RepositoryMaterialDraft(record: record))
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
        _ = try await repository.apply([.putMaterialItem(remote)], expectedRevision: 0)
        #expect(await editor.save { try $0.command() } == false)
        #expect(editor.draft.unitPriceText == "12.34" && editor.errorMessage != nil)
        await editor.load()
        #expect(editor.draft.unitPriceText == "45.67")
        editor.draft.unitPriceText = "9007199254740993.01"
        #expect(await editor.save { try $0.command() })
        #expect(try await repository.revision() == 2)
        let payload = try #require(try await repository.record(.materialItems, id: record.id))
        #expect(try JSONDecoder().decode(MaterialItem.self, from: payload).unitPrice.wireText == "9007199254740993.01")
    }
}
