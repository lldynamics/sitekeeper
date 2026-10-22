import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct ProjectWarehouseDeletionTests {
    @Test func undoPreservesInterveningInsertUpdateAndDeleteAcrossAllCollections() async throws {
        let fixture = await Fixture()
        defer { fixture.cleanUp() }
        let deletion = try #require(ProjectWarehouseDeletionActions.execute(
            ids: [fixture.movements[0].id], deleteAttachments: false, store: fixture.store
        ))
        fixture.applyInterveningChanges()

        deletion.restore(in: fixture.store)
        deletion.restore(in: fixture.store)

        #expect(Set(fixture.store.projectWarehouseMovements.map(\.id)) == Set([fixture.movements[0].id, fixture.movements[1].id, fixture.movements[3].id]))
        #expect(fixture.store.projectWarehouseMovements.first { $0.id == fixture.movements[1].id }?.quantity == "7")
        #expect(fixture.store.projectWarehouseMovements.count == 3)
        fixture.expectInterveningDocumentsAndFinancePreserved()
    }

    @Test func attachmentUndoRestoresOnlyDeletedUnsharedDocuments() async throws {
        let fixture = await Fixture()
        defer { fixture.cleanUp() }
        let shared = fixture.documents[1]
        let financialShared = fixture.documents[2]
        fixture.store.mutateProjectWarehouseMovement(id: fixture.movements[0].id) {
            $0.linkedDocumentIds = [fixture.documents[0].id, shared.id, financialShared.id]
        }
        fixture.store.mutateProjectWarehouseMovement(id: fixture.movements[1].id) { $0.linkedDocumentIds = [shared.id] }
        fixture.store.mutateProjectFinancialRecord(id: fixture.records[0].id) { $0.linkedDocumentIds = [financialShared.id] }
        let deletion = try #require(ProjectWarehouseDeletionActions.execute(
            ids: [fixture.movements[0].id], deleteAttachments: true, store: fixture.store
        ))
        #expect(deletion.documents?.removed.map(\.id) == [fixture.documents[0].id])
        #expect(Set(fixture.store.projectDocuments.map(\.id)) == Set([shared.id, financialShared.id]))
        fixture.applyInterveningChanges()

        deletion.restore(in: fixture.store)

        #expect(fixture.store.projectDocuments.contains { $0.id == fixture.documents[0].id })
        #expect(!fixture.store.projectDocuments.contains { $0.id == financialShared.id })
        fixture.expectInterveningDocumentsAndFinancePreserved()
    }

    @Test func repeatedUndoKeepsNewerValuesWithRestoredIDs() async throws {
        let fixture = await Fixture()
        defer { fixture.cleanUp() }
        let deletion = try #require(ProjectWarehouseDeletionActions.execute(
            ids: [fixture.movements[0].id], deleteAttachments: true, store: fixture.store
        ))
        deletion.restore(in: fixture.store)
        fixture.store.mutateProjectWarehouseMovement(id: fixture.movements[0].id) { $0.quantity = "12" }
        fixture.store.mutateProjectDocument(id: fixture.documents[0].id) { $0.title = "更新后的附件" }

        deletion.restore(in: fixture.store)

        #expect(fixture.store.projectWarehouseMovements.first { $0.id == fixture.movements[0].id }?.quantity == "12")
        #expect(fixture.store.projectDocuments.first { $0.id == fixture.documents[0].id }?.title == "更新后的附件")
        #expect(fixture.store.projectWarehouseMovements.count == 3)
        #expect(fixture.store.projectDocuments.count == 3)
    }
}

private extension ProjectWarehouseDeletionTests {
    @MainActor
    struct Fixture {
        let directory: URL
        let store: DataStore
        let movements: [ProjectWarehouseMovement]
        let documents: [ProjectDocument]
        let records: [ProjectFinancialRecord]

        init() async {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("warehouse-undo-\(UUID().uuidString)")
            store = DataStore(storageDirectory: directory)
            await store.awaitInitialLoad()
            let project = Project(name: "仓库撤销", location: "")
            let fixtureDocuments = (0..<4).map { ProjectDocument(projectId: project.id, title: "附件\($0)", fileName: "\($0).pdf") }
            documents = fixtureDocuments
            records = (0..<4).map { ProjectFinancialRecord(projectId: project.id, amount: String($0 + 1)) }
            movements = (0..<4).map { index in
                ProjectWarehouseMovement(projectId: project.id, materialName: "材料\(index)", unit: "吨", quantity: "1",
                                         linkedDocumentIds: index == 0 ? [fixtureDocuments[0].id] : [])
            }
            store.replaceProjects([project])
            store.replaceProjectWarehouseMovements(Array(movements.prefix(3)))
            store.replaceProjectDocuments(Array(documents.prefix(3)))
            store.replaceProjectFinancialRecords(Array(records.prefix(3)))
        }

        func applyInterveningChanges() {
            store.mutateProjectWarehouseMovement(id: movements[1].id) { $0.quantity = "7" }
            store.mutateProjectDocument(id: documents[1].id) { $0.title = "已编辑" }
            store.mutateProjectFinancialRecord(id: records[1].id) { $0.amount = "99" }
            store.removeProjectWarehouseMovements(ids: [movements[2].id])
            store.removeProjectDocuments(ids: [documents[2].id])
            store.removeProjectFinancialRecords(ids: [records[2].id])
            store.appendProjectWarehouseMovement(movements[3])
            store.appendProjectDocument(documents[3])
            store.appendProjectFinancialRecord(records[3])
        }

        func expectInterveningDocumentsAndFinancePreserved() {
            #expect(Set(store.projectDocuments.map(\.id)) == Set([documents[0].id, documents[1].id, documents[3].id]))
            #expect(store.projectDocuments.first { $0.id == documents[1].id }?.title == "已编辑")
            #expect(Set(store.projectFinancialRecords.map(\.id)) == Set([records[0].id, records[1].id, records[3].id]))
            #expect(store.projectFinancialRecords.first { $0.id == records[1].id }?.amount == "99")
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
