import Foundation
import Testing
@testable import sitekeeper

struct RepositoryFinancialTests {
    @Test(arguments: [false, true])
    func pagesFiltersAndExactTotalsCoverAllMatchingRecords(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        let project = snapshot.projects[0].id
        snapshot.projectFinancialRecords = (0..<103).map { index in
            ProjectFinancialRecord(projectId: project, date: BusinessDateValue(legacyText: "2026-10-24"), direction: index < 100 ? .income : .expense,
                amount: NumericInputSupport.money(index < 100 ? "0.10" : "0.20"), counterparty: "往来 \(index)")
        }
        snapshot.projectFinancialRecords[0].note = String(repeating: "备注", count: 200) + " CAFÉ %_ 目标"
        snapshot.projectFinancialRecords[1].invoiceNumber = "查票-001"
        snapshot.projectFinancialRecords += [
            ProjectFinancialRecord(projectId: project, amount: NumericInputSupport.money("999"), status: .draft),
            ProjectFinancialRecord(projectId: project, amount: NumericInputSupport.money("888"), status: .archived),
            ProjectFinancialRecord(projectId: snapshot.projects[1].id, amount: NumericInputSupport.money("777"))
        ]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        var query = RepositoryQuery(collection: .projectFinancialRecords, project: .project(project), order: .newestFirst)
        var cursor: RepositoryCursor?
        var ids: [UUID] = []
        repeat {
            let result = try await repository.financialPage(query, after: cursor, limit: 50)
            #expect(result.page.items.count <= 50)
            #expect(result.summary.count == 105 && result.summary.activeCount == 103)
            #expect(result.summary.income == 10 && result.summary.expense == Decimal(string: "0.6"))
            #expect(result.summary.balance == Decimal(string: "9.4"))
            #expect(result.page.items.allSatisfy { $0.financial != nil })
            ids += result.page.items.map(\.id)
            cursor = result.page.next
        } while cursor != nil
        let expected = snapshot.projectFinancialRecords.filter { $0.projectId == project }.sorted { ($0.date, $0.id.uuidString) > ($1.date, $1.id.uuidString) }.map(\.id)
        #expect(ids == expected && Set(ids).count == 105)
        query.financialDirection = .expense
        query.financialStatus = .active
        let expenses = try await repository.financialPage(query, after: nil, limit: 1)
        #expect(expenses.summary.count == 3 && expenses.summary.balance == Decimal(string: "-0.6"))
        query.financialStatus = .draft
        let draft = try await repository.financialPage(query, after: nil, limit: 50)
        #expect(draft.summary.count == 1 && draft.summary.activeCount == 0 && draft.summary.expense == 0)
        query.financialDirection = nil
        query.financialStatus = nil
        for (search, index) in [("cafe %_ 目标", 0), ("查票-001", 1), ("往来 102", 102)] {
            query.searchText = search
            let found = try await repository.financialPage(query, after: nil, limit: 50)
            #expect(found.page.items.map(\.id) == [snapshot.projectFinancialRecords[index].id])
            #expect(found.summary.count == 1)
        }
        query.searchText = "无结果"
        let empty = try await repository.financialPage(query, after: nil, limit: 50)
        #expect(empty.page.items.isEmpty && empty.summary.balance == 0)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test(arguments: [false, true])
    func missingLegacyAmountRemainsRepairableAndDoesNotMislead(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.projectFinancialRecords[0].amount = NumericInputSupport.money("")
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryQuery(collection: .projectFinancialRecords)
        let before = try await repository.financialPage(query, after: nil, limit: 50)
        #expect(before.page.items.count == 3 && before.summary.invalidAmountCount == 1)
        #expect(before.summary.income == nil && before.summary.balance == nil)
        var draft = RepositoryFinancialDraft(record: snapshot.projectFinancialRecords[0])
        draft.amountText = "0.10"
        _ = try await repository.apply([draft.command()], expectedRevision: 0)
        let after = try await repository.financialPage(query, after: nil, limit: 50)
        #expect(after.summary.invalidAmountCount == 0 && after.summary.income == Decimal(string: "0.30"))
    }

    @Test(arguments: ["", "12oops", "-1", "0", "NaN", "Infinity", "1e3", "1,234", "1.2.3", "123456789012345678901234567890123456789"])
    func invalidInputCannotSaveOldAmount(text: String) throws {
        var draft = RepositoryFinancialDraft(record: RepositoryTestFixture.sample().projectFinancialRecords[0])
        draft.amountText = text
        #expect(RepositoryMoney.input(text) == nil)
        #expect(throws: RepositoryError.invalidAmount) { try draft.command() }
        #expect(draft.amountText == text && draft.record.amount.wireText == "0.1")
    }

    @Test func exactDecimalsBeyondDoubleAndArithmeticFailureAreExplicit() throws {
        #expect(RepositoryMoney.parse("1e999") == nil && RepositoryMoney.parse("1e-999") == nil)
        #expect(RepositoryMoney.input("12．34") == Decimal(string: "12.34"))
        var total = RepositoryFinancialAccumulator()
        for text in ["9007199254740993.01", "0.10", "0.20"] {
            try total.add(amount: text, direction: ProjectFinancialDirection.income.rawValue, status: ProjectFinancialStatus.active.rawValue)
        }
        #expect(total.result().income == Decimal(string: "9007199254740993.31"))
        #expect(RepositoryMoney.display(try #require(total.result().income)) == "9007199254740993.31")
        var overflow = RepositoryFinancialAccumulator()
        try overflow.add(amount: "1e100", direction: "收入", status: "正式")
        try overflow.add(amount: "0.01", direction: "收入", status: "正式")
        #expect(overflow.result().hasPrecisionError && overflow.result().income == nil)
        var excluded = RepositoryFinancialAccumulator()
        try excluded.add(amount: "", direction: "收入", status: "草稿")
        try excluded.add(amount: "0", direction: "支出", status: "正式")
        #expect(excluded.result().invalidAmountCount == 0 && excluded.result().balance == 0)
    }

    @Test(arguments: [false, true])
    func invalidBatchRollsBackAndCursorRejectsChangedFilterOrRevision(sqlite: Bool) async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryQuery(collection: .projectFinancialRecords)
        let first = try await repository.financialPage(query, after: nil, limit: 1)
        var changed = query
        changed.financialDirection = .income
        await #expect(throws: RepositoryError.invalidCursor) { try await repository.financialPage(changed, after: first.page.next, limit: 1) }
        var invalid = fixture.snapshot.projectFinancialRecords[0]
        invalid.amount = NumericInputSupport.money("")
        await #expect(throws: RepositoryError.invalidAmount) {
            try await repository.apply([.putProject(Project(name: "应回滚", location: "")), .putFinancialRecord(invalid)], expectedRevision: 0)
        }
        #expect(try await repository.revision() == 0)
        #expect(try await repository.page(RepositoryQuery(collection: .projects), after: nil, limit: 50).items.count == 2)
        var valid = invalid
        valid.amount = NumericInputSupport.money("1.25")
        _ = try await repository.apply([.putFinancialRecord(valid)], expectedRevision: 0)
        await #expect(throws: RepositoryError.staleRevision) { try await repository.financialPage(query, after: first.page.next, limit: 1) }
    }
}
