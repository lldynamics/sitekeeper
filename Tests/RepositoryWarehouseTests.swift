import Foundation
import Testing
@testable import sitekeeper

struct RepositoryWarehouseTests {
    @Test(arguments: [false, true])
    func stockPagesGroupFullLedgerAndKeepUnitsSpecificationsAndProjectsSeparate(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        let project = snapshot.projects[0].id
        snapshot.projectWarehouseMovements = (0..<53).flatMap { index in
            [ProjectWarehouseMovement(projectId: project, materialName: String(format: "品种 %03d", index), unit: "米", quantity: NumericInputSupport.quantity("0.3")),
             ProjectWarehouseMovement(projectId: project, movementType: .outbound, materialName: String(format: "品种 %03d", index), unit: "米", quantity: NumericInputSupport.quantity("0.1")),
             ProjectWarehouseMovement(projectId: project, movementType: .outbound, materialName: String(format: "品种 %03d", index), unit: "米", quantity: NumericInputSupport.quantity("0.2"))]
        }
        snapshot.projectWarehouseMovements += [
            ProjectWarehouseMovement(projectId: project, materialName: "品种 000", unit: "卷", quantity: NumericInputSupport.quantity("5")),
            ProjectWarehouseMovement(projectId: project, materialName: "品种 000", specification: "规格B", unit: "米", quantity: NumericInputSupport.quantity("2")),
            ProjectWarehouseMovement(projectId: project, materialName: "X|Y", specification: "Z", unit: "米", quantity: NumericInputSupport.quantity("3")),
            ProjectWarehouseMovement(projectId: project, materialName: "X", specification: "Y|Z", unit: "米", quantity: NumericInputSupport.quantity("4")),
            ProjectWarehouseMovement(projectId: project, materialName: "  ", quantity: NumericInputSupport.quantity("6")),
            ProjectWarehouseMovement(projectId: snapshot.projects[1].id, materialName: "品种 000", unit: "米", quantity: NumericInputSupport.quantity("999"))
        ]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryStockQuery(projectID: project)
        var cursor: RepositoryStockCursor?
        var lines: [RepositoryStockLine] = []
        repeat {
            let result = try await repository.stockPage(query, after: cursor, limit: 17)
            #expect(result.items.count <= 17 && result.totalMaterials == 57 && result.unnamedMovements == 1)
            lines += result.items
            cursor = result.next
        } while cursor != nil
        #expect(lines.count == 57 && Set(lines.map(\.id)).count == 57)
        #expect(lines.map(\.id) == lines.map(\.id).sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) })
        #expect(lines.filter { $0.unit == "米" && $0.specification.isEmpty }.allSatisfy { $0.balance == 0 && $0.movementCount == 3 })
        #expect(lines.first { $0.unit == "卷" }?.balance == 5)
        #expect(lines.first { $0.specification == "规格B" }?.balance == 2)
        let selected = try await repository.stockPage(RepositoryStockQuery(projectID: project, searchText: "品种 000"), after: nil, limit: 50)
        #expect(selected.totalMaterials == 3 && selected.items.count == 3)
        let outbound = try await repository.page(RepositoryQuery(collection: .projectWarehouseMovements, project: .project(project), warehouseType: .outbound), after: nil, limit: 1)
        #expect(outbound.items.count == 1 && outbound.next != nil && outbound.items[0].warehouse?.movementType == .outbound)
        #expect(try await repository.stockPage(query, after: nil, limit: 17).items == Array(lines.prefix(17)))
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test(arguments: [false, true])
    func normalizationSearchAndNegativeStockRemainExact(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        let project = snapshot.projects[0].id
        snapshot.projectWarehouseMovements = [
            ProjectWarehouseMovement(projectId: project, materialName: " C30  Concrete ", specification: " Pumped ", unit: "M3", quantity: NumericInputSupport.quantity("0.3"), note: String(repeating: "备注", count: 200) + " CAFÉ %_ 目标"),
            ProjectWarehouseMovement(projectId: project, movementType: .outbound, materialName: "c30 concrete", specification: "pumped", unit: "m3", quantity: NumericInputSupport.quantity("0.4"), handler: "经手A"),
            ProjectWarehouseMovement(projectId: project, materialName: "Café", quantity: NumericInputSupport.quantity("9007199254740993.01")),
            ProjectWarehouseMovement(projectId: project, materialName: "Cafe\u{301}", quantity: NumericInputSupport.quantity("0.02"))
        ]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        let stock = try await repository.stockPage(RepositoryStockQuery(projectID: project, searchText: "c30 concrete"), after: nil, limit: 50)
        #expect(stock.totalMaterials == 1 && stock.items[0].movementCount == 2 && stock.items[0].balance == Decimal(string: "-0.1"))
        let exact = try await repository.stockPage(RepositoryStockQuery(projectID: project, searchText: "cafe"), after: nil, limit: 50)
        #expect(exact.totalMaterials == 1 && exact.items[0].balance == Decimal(string: "9007199254740993.03"))
        for (text, index) in [("cafe %_ 目标", 0), ("经手A", 1)] {
            let page = try await repository.page(RepositoryQuery(collection: .projectWarehouseMovements, project: .project(project), searchText: text), after: nil, limit: 50)
            #expect(page.items.map(\.id) == [snapshot.projectWarehouseMovements[index].id])
        }
        let empty = try await repository.stockPage(RepositoryStockQuery(projectID: project, searchText: "不存在"), after: nil, limit: 50)
        #expect(empty.items.isEmpty && empty.totalMaterials == 0)
    }

    @Test(arguments: [false, true])
    func invalidLegacyQuantityIsVisibleAndRepairable(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.projectWarehouseMovements[0].quantity = NumericInputSupport.quantity("")
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryStockQuery(projectID: snapshot.projects[0].id)
        let before = try await repository.stockPage(query, after: nil, limit: 50)
        #expect(before.items[0].invalidQuantityCount == 1 && before.items[0].balance == nil)
        var draft = RepositoryWarehouseDraft(record: snapshot.projectWarehouseMovements[0])
        draft.quantityText = "1.25"
        _ = try await repository.apply([draft.command()], expectedRevision: 0)
        #expect(try await repository.stockPage(query, after: nil, limit: 50).items[0].balance == Decimal(string: "1.25"))
    }

    @Test(arguments: ["", "0", "-1", "12oops", "NaN", "1e3", "1,234", "123456789012345678901234567890123456789"])
    func invalidRawQuantityNeverSavesPreviousValue(text: String) throws {
        var draft = RepositoryWarehouseDraft(record: RepositoryTestFixture.sample().projectWarehouseMovements[0])
        draft.quantityText = text
        #expect(throws: RepositoryError.invalidQuantity) { try draft.command() }
        #expect(draft.quantityText == text && draft.record.quantity.wireText == "2.5")
    }

    @Test func overflowAndPrecisionLossAreReportedWithoutFakeStock() throws {
        let fields = try RepositoryWarehouseFields(object: ["materialName": "测试", "movementType": "入库"])
        var total = RepositoryStockAccumulator()
        try total.add(quantity: "1e100", type: "入库")
        try total.add(quantity: "0.01", type: "入库")
        let line = try total.line(fields: fields)
        #expect(line.hasPrecisionError && line.balance == nil)
    }

    @Test(arguments: [false, true])
    func failedBatchAndChangedQueryOrRevisionCannotPublishStaleStock(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.projectWarehouseMovements.append(ProjectWarehouseMovement(projectId: snapshot.projects[0].id, materialName: "另一种", quantity: NumericInputSupport.quantity("2")))
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryStockQuery(projectID: snapshot.projects[0].id)
        let first = try await repository.stockPage(query, after: nil, limit: 1)
        await #expect(throws: RepositoryError.invalidCursor) { try await repository.stockPage(RepositoryStockQuery(projectID: snapshot.projects[1].id), after: first.next, limit: 1) }
        let invalid = ProjectWarehouseMovement(projectId: snapshot.projects[0].id, materialName: " ", quantity: NumericInputSupport.quantity("2"))
        await #expect(throws: RepositoryError.invalidRecord("warehouse")) {
            try await repository.apply([.putProject(Project(name: "回滚", location: "")), .putWarehouseMovement(invalid)], expectedRevision: 0)
        }
        #expect(try await repository.revision() == 0)
        #expect(try await repository.page(RepositoryQuery(collection: .projects), after: nil, limit: 50).items.count == 2)
        var edited = snapshot.projectWarehouseMovements[0]
        edited.unit = "卷"
        _ = try await repository.apply([.putWarehouseMovement(edited)], expectedRevision: 0)
        await #expect(throws: RepositoryError.staleRevision) { try await repository.stockPage(query, after: first.next, limit: 1) }
        let result = try await repository.stockPage(query, after: nil, limit: 50)
        #expect(!result.items.contains { $0.materialName == edited.materialName && $0.unit == "" })
        #expect(result.items.first { $0.unit == "卷" }?.balance == Decimal(string: "2.5"))
    }
}
