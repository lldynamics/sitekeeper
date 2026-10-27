import Foundation
import Testing
@testable import sitekeeper

struct RepositoryQuoteTests {
    static func item(name: String = "报价", quantity: String = "1", price: String = "100", tax: String = "13", discount: String = "5",
                     version: String = "V1", status: QuoteStatus = .draft, project: UUID? = nil, date: String = "") -> QuoteItem {
        QuoteItem(name: name, unitPrice: NumericInputSupport.money(price), quantity: NumericInputSupport.quantity(quantity), unit: "项", notes: "", taxRate: NumericInputSupport.quantity(tax), discountRate: NumericInputSupport.quantity(discount),
            versionName: version, status: status, customerConfirmedDate: BusinessDateValue(legacyText: date), projectId: project)
    }

    @Test(arguments: [false, true])
    func paginationStatusVersionSearchAndAmounts(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        let project = snapshot.projects[0].id
        snapshot.quoteItems = (0..<103).map { Self.item(name: "报价 \($0)", project: project, date: "2026-10-24") }
        snapshot.quoteItems[0].notes = String(repeating: "备注", count: 200) + " CAFÉ %_ 目标"
        snapshot.quoteItems[0].contractAmount = NumericInputSupport.money("999999")
        snapshot.quoteItems += [Self.item(version: "V2", status: .confirmed, project: project), Self.item(project: snapshot.projects[1].id), Self.item()]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        var query = RepositoryQuery(collection: .quoteItems, project: .project(project), order: .newestFirst, quoteVersion: "V1")
        var cursor: RepositoryCursor?
        var ids: [UUID] = []
        repeat {
            let result = try await repository.quotePage(query, after: cursor, limit: 50)
            #expect(result.page.items.count <= 50 && result.summary.count == 103)
            #expect(result.summary.amounts == RepositoryQuoteAmounts(subtotal: 10300, tax: 1339, discount: 515, total: 11124))
            ids += result.page.items.map(\.id)
            cursor = result.page.next
        } while cursor != nil
        #expect(ids == snapshot.quoteItems.prefix(103).sorted { $0.id.uuidString > $1.id.uuidString }.map(\.id))
        query.order = .oldestFirst
        let firstAscending = try await repository.quotePage(query, after: nil, limit: 1)
        #expect(firstAscending.page.items.first?.id == ids.last)
        query.quoteVersion = nil
        query.quoteStatus = .confirmed
        #expect(try await repository.quotePage(query, after: nil, limit: 1).summary.amounts?.total == 108)
        query.quoteStatus = nil
        query.searchText = "cafe %_ 目标"
        #expect(try await repository.quotePage(query, after: nil, limit: 50).page.items.map(\.id) == [snapshot.quoteItems[0].id])
        query.searchText = "无结果"
        #expect(try await repository.quotePage(query, after: nil, limit: 50).summary.amounts?.total == 0)
        #expect(try await repository.quotePage(RepositoryQuery(collection: .quoteItems, project: .unassigned), after: nil, limit: 50).summary.count == 1)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test(arguments: [false, true])
    func legacyMissingAmountsAndExcessDiscountStayRepairable(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.quoteItems = [Self.item(price: ""), Self.item(tax: "", discount: "150")]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryQuery(collection: .quoteItems)
        let before = try await repository.quotePage(query, after: nil, limit: 50)
        #expect(before.summary.invalidValueCount == 1 && before.summary.amounts == nil)
        var missing = RepositoryQuoteDraft(record: snapshot.quoteItems[0])
        missing.unitPriceText = "100"
        _ = try await repository.apply([missing.command()], expectedRevision: 0)
        #expect(try await repository.quotePage(query, after: nil, limit: 50).summary.amounts?.total == 108)
        var excessive = RepositoryQuoteDraft(record: snapshot.quoteItems[1])
        #expect(throws: RepositoryError.invalidQuoteValues) { try excessive.command() }
        excessive.taxRateText = "0"
        excessive.discountRateText = "100"
        _ = try await repository.apply([excessive.command()], expectedRevision: 1)
        #expect(try await repository.quotePage(query, after: nil, limit: 50).summary.amounts?.total == 108)
    }

    @Test(arguments: ["", "bad", "-1", "1e3", "1,234", "NaN", "123456789012345678901234567890123456789"])
    func rawNumericEditsCannotSaveOldValues(text: String) throws {
        let initial = RepositoryQuoteDraft(record: Self.item())
        for key in [\RepositoryQuoteDraft.unitPriceText, \.quantityText, \.taxRateText, \.discountRateText] {
            var draft = initial
            draft[keyPath: key] = text
            #expect(throws: RepositoryError.invalidQuoteValues) { try draft.command() }
            #expect(draft[keyPath: key] == text && draft.record.unitPrice.wireText == "100")
        }
        if !text.isEmpty {
            var draft = initial
            draft.contractAmountText = text
            #expect(throws: RepositoryError.invalidQuoteValues) { try draft.command() }
        }
    }

    @Test func exactFormulaAndPrecisionFailures() throws {
        let item = Self.item(price: "1000")
        let fields = RepositoryQuoteFields(object: try RepositoryJSON.object(JSONEncoder().encode(item)))
        #expect(try RepositoryQuoteArithmetic.amounts(fields) == RepositoryQuoteAmounts(subtotal: 1000, tax: 130, discount: 50, total: 1080))
        let precise = Self.item(quantity: "0.1", price: "0.2", tax: "13", discount: "5")
        #expect(try RepositoryQuoteArithmetic.amounts(RepositoryQuoteFields(object: RepositoryJSON.object(JSONEncoder().encode(precise)))).total == Decimal(string: "0.0216"))
        for (quantity, price, tax) in [("1e-100", "1e-100", "0"), ("1e100", "1e100", "0"), ("1", "1", "1e-128"), ("1", "1e100", "0.0000000000000000000000000000000000001")] {
            var total = RepositoryQuoteAccumulator()
            total.add(RepositoryQuoteFields(quantity: quantity, unitPrice: price, unit: "项", taxRate: tax, discountRate: "0", versionName: "V1", status: .draft))
            #expect(total.result().hasPrecisionError && total.result().amounts == nil)
        }
        var zero = RepositoryQuoteDraft(record: Self.item(quantity: "0", price: "0", discount: "100"))
        zero.contractAmountText = "0"
        _ = try zero.command()
        zero.discountRateText = "100.01"
        #expect(throws: RepositoryError.invalidQuoteValues) { try zero.command() }
        zero.discountRateText = "0"
        zero.record.unit = " "
        #expect(throws: RepositoryError.invalidQuoteValues) { try zero.command() }
    }

    @Test(arguments: [false, true])
    func invalidBatchesAndStaleCursorsAreRejected(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.quoteItems = [Self.item(), Self.item(version: "V2")]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryQuery(collection: .quoteItems)
        let cursor = try #require(try await repository.quotePage(query, after: nil, limit: 1).page.next)
        for changed in [RepositoryQuery(collection: .quoteItems, quoteStatus: .sent), RepositoryQuery(collection: .quoteItems, quoteVersion: "V2"), RepositoryQuery(collection: .quoteItems, project: .unassigned)] {
            await #expect(throws: RepositoryError.invalidCursor) { try await repository.quotePage(changed, after: cursor, limit: 1) }
        }
        var invalid = snapshot.quoteItems[0]
        invalid.discountRate = NumericInputSupport.quantity("101")
        await #expect(throws: RepositoryError.invalidQuoteValues) {
            try await repository.apply([.putProject(Project(name: "回滚", location: "")), .putQuoteItem(invalid)], expectedRevision: 0)
        }
        #expect(try await repository.revision() == 0)
        #expect(try await repository.page(RepositoryQuery(collection: .projects), after: nil, limit: 50).items.count == 2)
        invalid.discountRate = NumericInputSupport.quantity("0")
        invalid.projectId = UUID()
        await #expect(throws: (any Error).self) { try await repository.apply([.putQuoteItem(invalid)], expectedRevision: 0) }
        #expect(try await repository.revision() == 0)
        _ = try await repository.apply([.putQuoteItem(snapshot.quoteItems[0])], expectedRevision: 0)
        await #expect(throws: RepositoryError.staleRevision) { try await repository.quotePage(query, after: cursor, limit: 1) }
        await #expect(throws: RepositoryError.invalidPageSize) { try await repository.quotePage(query, after: nil, limit: 201) }
        await #expect(throws: RepositoryError.invalidRecord("quote query")) { try await repository.quotePage(RepositoryQuery(collection: .projects), after: nil, limit: 1) }
        #expect(try await repository.page(RepositoryQuery(collection: .materialItems, quoteVersion: "V1"), after: nil, limit: 50).items.isEmpty)
    }

    @Test(arguments: [false, true])
    func decimalModelRoundTripPreservesExactAmountsAndOptionalContract(sqlite: Bool) async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        var draft = RepositoryQuoteDraft(record: fixture.snapshot.quoteItems[0])
        draft.quantityText = "0.3"
        draft.unitPriceText = "9007199254740993.01"
        draft.taxRateText = "13"
        draft.discountRateText = "5"
        draft.contractAmountText = "9007199254740993.02"
        _ = try await repository.apply([draft.command()], expectedRevision: 0)
        let payload = try #require(try await repository.record(.quoteItems, id: draft.record.id))
        let saved = try JSONDecoder().decode(QuoteItem.self, from: payload)
        #expect(saved.quantity.optionalDecimal == Decimal(string: "0.3"))
        #expect(saved.unitPrice.optionalDecimal == Decimal(string: "9007199254740993.01"))
        #expect(saved.contractAmount.optionalDecimal == Decimal(string: "9007199254740993.02"))
        let wire = try RepositoryJSON.object(payload)
        #expect(wire["quantity"] as? String == "0.3")
        #expect(wire["unitPrice"] as? String == "9007199254740993.01")
        let query = RepositoryQuery(collection: .quoteItems, project: draft.record.projectId.map(RepositoryProjectFilter.project) ?? .unassigned)
        #expect(try await repository.quotePage(query, after: nil, limit: 50).summary.amounts?.total == Decimal(string: "2918332558536081.73524"))
        var reloaded = RepositoryQuoteDraft(record: saved)
        reloaded.contractAmountText = ""
        _ = try await repository.apply([reloaded.command()], expectedRevision: 1)
        let blankPayload = try #require(try await repository.record(.quoteItems, id: saved.id))
        #expect(try JSONDecoder().decode(QuoteItem.self, from: blankPayload).contractAmount.isEmpty)
        reloaded.contractAmountText = "0"
        _ = try await repository.apply([reloaded.command()], expectedRevision: 2)
        let zeroPayload = try #require(try await repository.record(.quoteItems, id: saved.id))
        let zero = try JSONDecoder().decode(QuoteItem.self, from: zeroPayload).contractAmount
        #expect(!zero.isEmpty && zero.optionalDecimal == .zero)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test(arguments: [false, true])
    func unresolvedDecimalModelRequiresExplicitRepair(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        var legacy = Self.item(project: snapshot.projects[0].id)
        legacy.unitPrice = MoneyValue(storage: .unresolved("历史待核价"))
        snapshot.quoteItems = [legacy]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        let payload = try #require(try await repository.record(.quoteItems, id: legacy.id))
        var draft = try JSONDecoder().decode(RepositoryQuoteDraft.self, from: payload)
        #expect(draft.unitPriceText == "历史待核价")
        #expect(throws: RepositoryError.invalidQuoteValues) { try draft.command() }
        await #expect(throws: RepositoryError.invalidQuoteValues) {
            try await repository.apply([.putQuoteItem(legacy)], expectedRevision: 0)
        }
        let query = RepositoryQuery(collection: .quoteItems)
        let before = try await repository.quotePage(query, after: nil, limit: 50)
        #expect(before.summary.invalidValueCount == 1 && before.summary.amounts == nil && before.page.revision == 0)
        draft.unitPriceText = "0.1"
        _ = try await repository.apply([draft.command()], expectedRevision: 0)
        #expect(try await repository.quotePage(query, after: nil, limit: 50).summary.amounts?.total == Decimal(string: "0.108"))
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }
}
