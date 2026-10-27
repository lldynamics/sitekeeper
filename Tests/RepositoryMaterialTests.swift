import Foundation
import Testing
@testable import sitekeeper

struct RepositoryMaterialTests {
    @Test(arguments: [false, true])
    func pagesFiltersSearchAndTotalsCoverAllMatches(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        let project = snapshot.projects[0].id
        snapshot.materialItems = (0..<103).map { index in
            MaterialItem(name: "材料 \(index)", quantity: NumericInputSupport.quantity("0.3"), unit: "米", unitPrice: NumericInputSupport.money("0.1"),
                specification: "规格 \(index)", brand: "品牌 \(index)", supplier: "供应商 \(index)",
                purchaseStatus: index < 100 ? .arrived : .notPurchased, arrivalDate: BusinessDateValue(legacyText: "2026-10-24"), projectId: project)
        }
        snapshot.materialItems[0].supplier = String(repeating: "供应商", count: 200) + " CAFÉ %_ 目标"
        snapshot.materialItems += [MaterialItem(name: "其他项目", quantity: NumericInputSupport.quantity("1"), unit: "件", unitPrice: NumericInputSupport.money("999"), projectId: snapshot.projects[1].id),
                                   MaterialItem(name: "未分配", quantity: NumericInputSupport.quantity("2"), unit: "件", unitPrice: NumericInputSupport.money("5"))]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        var query = RepositoryQuery(collection: .materialItems, project: .project(project), order: .newestFirst)
        var cursor: RepositoryCursor?
        var ids: [UUID] = []
        repeat {
            let result = try await repository.materialPage(query, after: cursor, limit: 50)
            #expect(result.page.items.count <= 50 && result.summary.count == 103)
            #expect(result.summary.total == Decimal(string: "3.09"))
            #expect(result.page.items.allSatisfy { $0.material != nil })
            ids += result.page.items.map(\.id)
            cursor = result.page.next
        } while cursor != nil
        let expected = snapshot.materialItems.filter { $0.projectId == project }.sorted { ($0.arrivalDate, $0.id.uuidString) > ($1.arrivalDate, $1.id.uuidString) }.map(\.id)
        #expect(ids == expected && Set(ids).count == 103)
        query.materialStatus = .arrived
        let arrived = try await repository.materialPage(query, after: nil, limit: 1)
        #expect(arrived.summary.count == 100 && arrived.summary.total == 3)
        query.materialStatus = nil
        for (search, index) in [("cafe %_ 目标", 0), ("规格 102", 102), ("品牌 101", 101)] {
            query.searchText = search
            let found = try await repository.materialPage(query, after: nil, limit: 50)
            #expect(found.page.items.map(\.id) == [snapshot.materialItems[index].id])
            #expect(found.summary.count == 1 && found.summary.total == Decimal(string: "0.03"))
        }
        query.searchText = "无结果"
        #expect(try await repository.materialPage(query, after: nil, limit: 50).summary.total == 0)
        let unassigned = try await repository.materialPage(RepositoryQuery(collection: .materialItems, project: .unassigned), after: nil, limit: 50)
        #expect(unassigned.summary.count == 1 && unassigned.summary.total == 10)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test(arguments: [false, true])
    func missingPriceAndQuantityRemainRepairable(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.materialItems = [MaterialItem(name: "未定价", quantity: NumericInputSupport.quantity("2"), unit: "米"),
                                  MaterialItem(name: "待核数量", quantity: NumericInputSupport.quantity(""), unit: "件", unitPrice: NumericInputSupport.money("10")),
                                  MaterialItem(name: "免费", quantity: NumericInputSupport.quantity("1"), unit: "件", unitPrice: NumericInputSupport.money("0")),
                                  MaterialItem(name: "已定价", quantity: NumericInputSupport.quantity("2.5"), unit: "件", unitPrice: NumericInputSupport.money("3.12"))]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryQuery(collection: .materialItems)
        let before = try await repository.materialPage(query, after: nil, limit: 50)
        #expect(before.summary.unpricedCount == 1 && before.summary.invalidValueCount == 1)
        #expect(before.summary.total == nil && before.summary.knownSubtotal == Decimal(string: "7.8"))
        var price = RepositoryMaterialDraft(record: snapshot.materialItems[0])
        price.unitPriceText = "0.1"
        var quantity = RepositoryMaterialDraft(record: snapshot.materialItems[1])
        quantity.quantityText = "0.2"
        _ = try await repository.apply([price.command(), quantity.command()], expectedRevision: 0)
        #expect(try await repository.materialPage(query, after: nil, limit: 50).summary.total == 10)
        price.unitPriceText = ""
        _ = try await repository.apply([price.command()], expectedRevision: 1)
        #expect(try await repository.materialPage(query, after: nil, limit: 50).summary.unpricedCount == 1)
    }

    @Test(arguments: ["12oops", "-1", "NaN", "Infinity", "1e3", "1,234", "1.2.3", "123456789012345678901234567890123456789"])
    func invalidRawEditsCannotSavePreviousValue(text: String) throws {
        var draft = RepositoryMaterialDraft(record: RepositoryTestFixture.sample().materialItems[0])
        draft.quantityText = text
        #expect(throws: RepositoryError.invalidMaterialValues) { try draft.command() }
        #expect(draft.quantityText == text && draft.record.quantity.wireText == "2.5")
        draft.quantityText = "2.5"
        draft.unitPriceText = text
        #expect(throws: RepositoryError.invalidMaterialValues) { try draft.command() }
        #expect(draft.unitPriceText == text && draft.record.unitPrice.wireText == "3.12")
    }

    @Test func exactProductsAndArithmeticErrorsAreExplicit() throws {
        var total = RepositoryMaterialAccumulator()
        total.add(quantity: "0.1", unitPrice: "0.2")
        total.add(quantity: "1", unitPrice: "9007199254740993.01")
        #expect(total.result().total == Decimal(string: "9007199254740993.03"))
        for (quantity, price) in [("1e100", "1e100"), ("1e-100", "1e-100"), ("12345678901234567890123456789012345678", "12345678901234567890123456789012345678")] {
            var overflow = RepositoryMaterialAccumulator()
            overflow.add(quantity: quantity, unitPrice: price)
            #expect(overflow.result().hasPrecisionError && overflow.result().total == nil && overflow.result().knownSubtotal == nil)
        }
        var addition = RepositoryMaterialAccumulator()
        addition.add(quantity: "1", unitPrice: "1e100")
        addition.add(quantity: "1", unitPrice: "0.01")
        #expect(addition.result().hasPrecisionError && addition.result().total == nil)
        var invalid = RepositoryMaterialAccumulator()
        invalid.add(quantity: "bad", unitPrice: "2")
        invalid.add(quantity: "1", unitPrice: "bad")
        #expect(invalid.result().invalidValueCount == 2 && invalid.result().total == nil)
        var draft = RepositoryMaterialDraft(record: RepositoryTestFixture.sample().materialItems[0])
        draft.unitPriceText = "0"
        _ = try draft.command()
        draft.quantityText = "0"
        _ = try draft.command()
        draft.quantityText = "-1"
        #expect(throws: RepositoryError.invalidMaterialValues) { try draft.command() }
        draft.quantityText = "2．5"
        _ = try draft.command()
        draft.record.unit = "  "
        #expect(throws: RepositoryError.invalidMaterialValues) { try draft.command() }
    }

    @Test(arguments: [("0", "1e100", "0"), ("0.0000000001", "0.0000000001", "0.00000000000000000001"),
                      ("1e-64", "1e-64", "1e-128"), ("10", "12345678901234567890123456789012345678", "123456789012345678901234567890123456780"),
                      ("2.5", "3.12", "7.8"), ("0.123456789", "0.123456789", "0.015241578750190521")])
    func productsMatchExactDecimalOracle(values: (String, String, String)) throws {
        let left = try #require(RepositoryMoney.parse(values.0))
        let right = try #require(RepositoryMoney.parse(values.1))
        #expect(RepositoryMaterialArithmetic.product(left, right) == RepositoryMoney.parse(values.2))
    }

    @Test(arguments: [false, true])
    func batchesRollbackAndCursorChecksScopeStatusAndRevision(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.materialItems.append(MaterialItem(name: "另一个", quantity: NumericInputSupport.quantity("1"), unit: "件"))
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryQuery(collection: .materialItems)
        let first = try await repository.materialPage(query, after: nil, limit: 1)
        let cursor = try #require(first.page.next)
        for changed in [RepositoryQuery(collection: .materialItems, materialStatus: .arrived), RepositoryQuery(collection: .materialItems, project: .unassigned)] {
            await #expect(throws: RepositoryError.invalidCursor) { try await repository.materialPage(changed, after: cursor, limit: 1) }
        }
        var invalid = snapshot.materialItems[0]
        invalid.quantity = NumericInputSupport.quantity("")
        await #expect(throws: RepositoryError.invalidMaterialValues) {
            try await repository.apply([.putProject(Project(name: "应回滚", location: "")), .putMaterialItem(invalid)], expectedRevision: 0)
        }
        #expect(try await repository.revision() == 0)
        #expect(try await repository.page(RepositoryQuery(collection: .projects), after: nil, limit: 50).items.count == 2)
        var orphan = snapshot.materialItems[0]
        orphan.projectId = UUID()
        await #expect(throws: (any Error).self) { try await repository.apply([.putMaterialItem(orphan)], expectedRevision: 0) }
        #expect(try await repository.revision() == 0)
        _ = try await repository.apply([.putMaterialItem(snapshot.materialItems[0])], expectedRevision: 0)
        await #expect(throws: RepositoryError.staleRevision) { try await repository.materialPage(query, after: cursor, limit: 1) }
        await #expect(throws: RepositoryError.invalidPageSize) { try await repository.materialPage(query, after: nil, limit: 201) }
        await #expect(throws: RepositoryError.invalidRecord("material query")) { try await repository.materialPage(RepositoryQuery(collection: .projects), after: nil, limit: 1) }
        let wrongFilter = try await repository.page(RepositoryQuery(collection: .projects, materialStatus: .arrived), after: nil, limit: 50)
        #expect(wrongFilter.items.isEmpty)
    }
}
