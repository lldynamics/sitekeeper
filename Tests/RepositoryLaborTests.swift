import Foundation
import Testing
@testable import sitekeeper

struct RepositoryLaborTests {
    static func item(workers: String = "2", hours: String = "0.3", rate: String = "0.1", unit: LaborWorkloadUnit = .hour,
                     settled: Bool = false, project: UUID? = nil) -> LaborRecord {
        LaborRecord(date: BusinessDateValue(legacyText: "2026-10-25"), workers: NumericInputSupport.quantity(workers), hours: NumericInputSupport.quantity(hours),
            workloadUnit: unit, unitRate: NumericInputSupport.money(rate), workType: "木工", teamName: "班组", isSettled: settled, note: "", projectId: project)
    }

    @Test(arguments: [false, true])
    func pagingFiltersAndExactTotals(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        let project = snapshot.projects[0].id
        snapshot.laborRecords = (0..<103).map { _ in Self.item(project: project) }
        snapshot.laborRecords[0].note = String(repeating: "备注", count: 200) + " CAFÉ %_ 目标"
        snapshot.laborRecords += [Self.item(unit: .workday, settled: true, project: project), Self.item(project: snapshot.projects[1].id), Self.item()]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repo = try await fixture.repository(sqlite: sqlite)
        var query = RepositoryQuery(collection: .laborRecords, project: .project(project), laborSettled: false, laborUnit: .hour)
        var cursor: RepositoryCursor?
        var ids: [UUID] = []
        repeat {
            let result = try await repo.laborPage(query, after: cursor, limit: 50)
            #expect(result.page.items.count <= 50 && result.summary.count == 103)
            #expect(result.summary.total == Decimal(string: "6.18") && result.summary.unsettled == result.summary.total)
            ids += result.page.items.map(\.id)
            cursor = result.page.next
        } while cursor != nil
        #expect(ids == snapshot.laborRecords.prefix(103).sorted { $0.id.uuidString < $1.id.uuidString }.map(\.id))
        query.order = .newestFirst
        #expect(try await repo.laborPage(query, after: nil, limit: 1).page.items.first?.id == ids.last)
        query.laborSettled = true
        query.laborUnit = .workday
        #expect(try await repo.laborPage(query, after: nil, limit: 1).summary.total == Decimal(string: "0.06"))
        #expect(try await repo.laborPage(query, after: nil, limit: 1).summary.unsettled == 0)
        query.laborSettled = nil
        query.laborUnit = nil
        query.searchText = "cafe %_ 目标"
        #expect(try await repo.laborPage(query, after: nil, limit: 50).page.items.map(\.id) == [snapshot.laborRecords[0].id])
        query.searchText = "不存在"
        #expect(try await repo.laborPage(query, after: nil, limit: 50).summary.total == 0)
        #expect(try await repo.laborPage(RepositoryQuery(collection: .laborRecords, project: .unassigned), after: nil, limit: 50).summary.count == 1)
        #expect(try await repo.page(RepositoryQuery(collection: .projects, laborSettled: false), after: nil, limit: 50).items.isEmpty)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test(arguments: [false, true])
    func legacyMissingWorkersZeroUnpricedAndRepair(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.laborRecords = [Self.item(workers: "", hours: "8", rate: "50", unit: .legacyUnspecified), Self.item(workers: "0", hours: "8", rate: "50"), Self.item(rate: "")]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repo = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryQuery(collection: .laborRecords)
        let before = try await repo.laborPage(query, after: nil, limit: 50)
        #expect(before.summary.total == nil && before.summary.knownSubtotal == 400)
        #expect(before.summary.unpricedCount == 1 && before.summary.unconfirmedUnitCount == 1)
        var legacy = RepositoryLaborDraft(record: snapshot.laborRecords[0])
        #expect(throws: RepositoryError.invalidLaborValues) { try legacy.command() }
        legacy.workersText = "1"
        legacy.record.workloadUnit = .hour
        _ = try await repo.apply([legacy.command()], expectedRevision: 0)
        var free = RepositoryLaborDraft(record: snapshot.laborRecords[2])
        free.unitRateText = "0"
        _ = try await repo.apply([free.command()], expectedRevision: 1)
        let after = try await repo.laborPage(query, after: nil, limit: 50)
        #expect(after.summary.total == 400 && after.summary.unconfirmedUnitCount == 0)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test(arguments: [false, true])
    func decimalRoundTripInvalidHistoryAndAtomicWrites(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        var record = Self.item(project: snapshot.projects[0].id)
        record.unitRate = MoneyValue(storage: .unresolved("待核价"))
        snapshot.laborRecords = [record, Self.item()]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repo = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryQuery(collection: .laborRecords)
        let first = try await repo.laborPage(query, after: nil, limit: 1)
        #expect(first.summary.total == nil && first.summary.invalidValueCount == 1)
        var draft = RepositoryLaborDraft(record: record)
        #expect(draft.unitRateText == "待核价")
        await #expect(throws: RepositoryError.invalidLaborValues) { try await repo.apply([.putProject(Project(name: "不能留下", location: "")), .putLaborRecord(record)], expectedRevision: 0) }
        #expect(try await repo.revision() == 0)
        #expect(try await repo.page(RepositoryQuery(collection: .projects), after: nil, limit: 50).items.count == 2)
        draft.workersText = "1"
        draft.hoursText = "0.3"
        draft.unitRateText = "9007199254740993.01"
        _ = try await repo.apply([draft.command()], expectedRevision: 0)
        let payload = try #require(try await repo.record(.laborRecords, id: record.id))
        let saved = try JSONDecoder().decode(LaborRecord.self, from: payload)
        #expect(saved.unitRate.wireText == "9007199254740993.01")
        #expect(try await repo.laborPage(RepositoryQuery(collection: .laborRecords, project: .project(snapshot.projects[0].id)), after: nil, limit: 50).summary.total == Decimal(string: "2702159776422297.903"))
        await #expect(throws: RepositoryError.staleRevision) { try await repo.laborPage(query, after: first.page.next, limit: 1) }
        var dangling = saved
        dangling.projectId = UUID()
        await #expect(throws: (any Error).self) { try await repo.apply([.putLaborRecord(dangling)], expectedRevision: 1) }
        #expect(try await repo.revision() == 1)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test(arguments: [false, true])
    func cursorScopeAndPageSizeAreChecked(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.laborRecords = [Self.item(), Self.item(settled: true)]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repo = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryQuery(collection: .laborRecords)
        let cursor = try #require(try await repo.laborPage(query, after: nil, limit: 1).page.next)
        for changed in [RepositoryQuery(collection: .laborRecords, laborSettled: true), RepositoryQuery(collection: .laborRecords, laborUnit: .hour), RepositoryQuery(collection: .laborRecords, project: .unassigned)] {
            await #expect(throws: RepositoryError.invalidCursor) { try await repo.laborPage(changed, after: cursor, limit: 1) }
        }
        await #expect(throws: RepositoryError.invalidPageSize) { try await repo.laborPage(query, after: nil, limit: 201) }
        await #expect(throws: RepositoryError.invalidRecord("labor query")) { try await repo.laborPage(RepositoryQuery(collection: .projects), after: nil, limit: 1) }
    }

    @Test func requiredWorkloadAndOptionalRateRemainDistinct() throws {
        var draft = RepositoryLaborDraft(record: Self.item())
        draft.workersText = ""
        #expect(throws: RepositoryError.invalidLaborValues) { try draft.command() }
        draft.workersText = "0"
        draft.hoursText = ""
        #expect(throws: RepositoryError.invalidLaborValues) { try draft.command() }
        draft.hoursText = "0"
        draft.unitRateText = ""
        guard case .putLaborRecord(let empty) = try draft.command() else { Issue.record("Unexpected command"); return }
        #expect(empty.unitRate.isEmpty && empty.workers.optionalDecimal == 0)
        draft.unitRateText = "0"
        guard case .putLaborRecord(let zero) = try draft.command() else { Issue.record("Unexpected command"); return }
        #expect(!zero.unitRate.isEmpty && zero.unitRate.optionalDecimal == 0)
    }

    @Test(arguments: ["bad", "-1", "1e3", "NaN", "123456789012345678901234567890123456789"])
    func rawInvalidEditsNeverSavePreviousValues(text: String) throws {
        for key in [\RepositoryLaborDraft.workersText, \.hoursText, \.unitRateText] {
            var draft = RepositoryLaborDraft(record: Self.item())
            draft[keyPath: key] = text
            #expect(throws: RepositoryError.invalidLaborValues) { try draft.command() }
            #expect(draft[keyPath: key] == text)
        }
    }

    @Test func precisionFailuresHideAllAmounts() {
        var sum = RepositoryLaborAccumulator()
        sum.add(RepositoryLaborFields(workers: "1e100", hours: "1e100", unitRate: "1", workloadUnit: .hour, teamName: "", workType: "", isSettled: false))
        #expect(sum.result().hasPrecisionError && sum.result().knownSubtotal == nil && sum.result().unsettled == nil)
        var addition = RepositoryLaborAccumulator()
        for rate in ["1e100", "0.1"] {
            addition.add(RepositoryLaborFields(workers: "1", hours: "1", unitRate: rate, workloadUnit: .hour, teamName: "", workType: "", isSettled: true))
        }
        #expect(addition.result().hasPrecisionError && addition.result().total == nil)
    }
}
