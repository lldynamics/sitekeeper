import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct RepositoryWarehouseModelTests {
    @Test func stockPagingFailureStaleRevisionAndOldResponsePreserveCurrentQuery() async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.projectWarehouseMovements += (0..<3).map { ProjectWarehouseMovement(projectId: snapshot.projects[0].id, materialName: "材料 \($0)", quantity: NumericInputSupport.quantity("1")) }
        let repository = try RepositoryControlledRepository(snapshot: snapshot)
        let query = RepositoryStockQuery(projectID: snapshot.projects[0].id)
        let model = RepositoryStockPageModel(repository: repository, query: query, pageSize: 2)
        await model.reset()
        let first = model.items
        #expect(first.count == 2 && model.totalMaterials == 4)
        await repository.failReads(true)
        await model.next()
        #expect(model.items == first && model.pageNumber == 1 && model.errorMessage != nil)
        await repository.failReads(false)
        await model.next()
        #expect(model.pageNumber == 2 && model.nextCursor == nil)
        await model.previous()
        #expect(model.items == first)
        var movement = snapshot.projectWarehouseMovements[0]
        movement.quantity = NumericInputSupport.quantity("8")
        _ = try await repository.apply([.putWarehouseMovement(movement)], expectedRevision: 0)
        await model.next()
        #expect(model.pageNumber == 1 && model.errorMessage == nil)
        let held = Task { await model.reset(to: RepositoryStockQuery(projectID: query.projectID, searchText: "hold")) }
        await repository.waitUntilBlocked()
        #expect(model.items.isEmpty && model.totalMaterials == 0)
        await model.reset(to: RepositoryStockQuery(projectID: snapshot.projects[1].id))
        await repository.release()
        await held.value
        #expect(model.items.isEmpty && model.totalMaterials == 0)
        let cancelled = Task { await model.reset(to: RepositoryStockQuery(projectID: query.projectID, searchText: "hold")) }
        await repository.waitUntilBlocked()
        cancelled.cancel()
        model.cancel()
        await repository.release()
        await cancelled.value
        #expect(!model.isLoading && model.items.isEmpty)
    }

    @Test func failureConflictAndRetryRetainRawDraft() async throws {
        let snapshot = RepositoryTestFixture.sample()
        let repository = try RepositoryControlledRepository(snapshot: snapshot)
        let record = snapshot.projectWarehouseMovements[0]
        let editor = RepositoryRecordEditor(repository: repository, collection: .projectWarehouseMovements, id: record.id, initial: RepositoryWarehouseDraft(record: record))
        await editor.load()
        editor.draft.quantityText = "bad"
        #expect(await editor.save { try $0.command() } == false)
        #expect(editor.draft.quantityText == "bad" && editor.revision == 0)
        editor.draft.quantityText = "12.34"
        await repository.failWrites(true)
        #expect(await editor.save { try $0.command() } == false)
        #expect(editor.draft.quantityText == "12.34" && editor.revision == 0)
        await repository.failWrites(false)
        var remote = record
        remote.quantity = NumericInputSupport.quantity("5")
        _ = try await repository.apply([.putWarehouseMovement(remote)], expectedRevision: 0)
        #expect(await editor.save { try $0.command() } == false)
        #expect(editor.draft.quantityText == "12.34")
        await editor.load()
        #expect(editor.draft.quantityText == "5")
        editor.draft.quantityText = "12.34"
        #expect(await editor.save { try $0.command() })
        #expect(try await repository.revision() == 2)
    }
}
