import Foundation
import Testing
@testable import sitekeeper

struct RepositoryContractTests {
    @Test(arguments: [false, true])
    func pagingDetailAndExactMoney(sqlite: Bool) async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        let projects = ProjectRepository(repository: repository)
        let projectID = fixture.snapshot.projects[0].id
        var cursor: RepositoryCursor?
        var ids: [UUID] = []
        repeat {
            let page = try await projects.dailyLogs(projectID: projectID, after: cursor, limit: 2)
            #expect(page.items.count <= 2)
            ids += page.items.map(\.id)
            cursor = page.next
        } while cursor != nil
        #expect(ids == fixture.snapshot.dailyLogs.map(\.id).sorted { $0.uuidString < $1.uuidString })
        let detail = try #require(try await projects.dailyLog(id: ids[0]))
        #expect(detail.content.count > 120)
        let summary = try await FinanceRepository(repository: repository).summary(projectID: projectID)
        #expect(summary.count == 3)
        #expect(summary.income == Decimal(string: "0.30"))
        #expect(summary.expense == Decimal(string: "100.01"))
        let refs = try await AttachmentRepository(repository: repository).references(owner: .dailyLogs, id: ids[0])
        #expect(refs.count == 1)
        #expect(refs[0].fileName == "shared.jpg")
    }

    @Test(arguments: [false, true])
    func atomicBatchRollbackAndOptimisticConcurrency(sqlite: Bool) async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        let todo = fixture.snapshot.siteTodos[0]
        do {
            _ = try await repository.apply([.setTodoCompletion(todo.id, true, at: BusinessDateValue(legacyText: "2026-10-24T10:00:00Z")), .removeDailyLog(UUID())], expectedRevision: 0)
            Issue.record("The failing batch must roll back")
        } catch RepositoryError.missingRecord { }
        #expect(try await repository.revision() == 0)
        let unchanged = try #require(try await repository.record(.siteTodos, id: todo.id))
        #expect(try JSONDecoder().decode(SiteTodo.self, from: unchanged).isDone == false)
        let revision = try await repository.apply([.setTodoCompletion(todo.id, true, at: BusinessDateValue(legacyText: "2026-10-24T10:00:00Z"))], expectedRevision: 0)
        #expect(revision == 1)
        let saved = try #require(try await repository.record(.siteTodos, id: todo.id))
        #expect(try JSONDecoder().decode(SiteTodo.self, from: saved).completedAt?.storageText == "2026-10-24T10:00:00Z")
        await #expect(throws: RepositoryError.staleRevision) {
            try await repository.apply([.removeDailyLog(fixture.snapshot.dailyLogs[0].id)], expectedRevision: 0)
        }
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test(arguments: [false, true])
    func cursorValidationAndProjectIsolation(sqlite: Bool) async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryQuery(collection: .dailyLogs, project: .project(fixture.snapshot.projects[0].id))
        let first = try await repository.page(query, after: nil, limit: 1)
        let cursor = try #require(first.next)
        await #expect(throws: RepositoryError.invalidCursor) {
            try await repository.page(RepositoryQuery(collection: .siteTodos), after: cursor, limit: 1)
        }
        await #expect(throws: RepositoryError.invalidPageSize) { try await repository.page(query, after: nil, limit: 0) }
        let other = try await repository.page(RepositoryQuery(collection: .dailyLogs, project: .project(fixture.snapshot.projects[1].id)), after: nil, limit: 5)
        #expect(other.items.isEmpty)
        let sharedContacts = try await repository.page(RepositoryQuery(collection: .projectContacts, project: .project(fixture.snapshot.projects[1].id)), after: nil, limit: 5)
        #expect(sharedContacts.items.map(\.id) == fixture.snapshot.projectContacts.map(\.id))
        _ = try await repository.apply([.putProject(fixture.snapshot.projects[0])], expectedRevision: 0)
        await #expect(throws: RepositoryError.staleRevision) { try await repository.page(query, after: cursor, limit: 1) }
    }

    @Test func jsonPersistenceFailureDoesNotPublishChanges() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let repository = try JSONSnapshotRepository(snapshot: fixture.snapshot) { _ in throw CocoaError(.fileWriteOutOfSpace) }
        await #expect(throws: (any Error).self) {
            try await repository.apply([.removeDailyLog(fixture.snapshot.dailyLogs[0].id)], expectedRevision: 0)
        }
        #expect(await repository.revision() == 0)
        #expect(await repository.record(.dailyLogs, id: fixture.snapshot.dailyLogs[0].id) != nil)
    }
}

extension RepositoryContractTests {
    @Test(arguments: [false, true])
    func danglingProjectWriteRollsBackBatch(sqlite: Bool) async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        var invalid = fixture.snapshot.dailyLogs[0]
        invalid.projectId = UUID()
        await #expect(throws: (any Error).self) {
            try await repository.apply([.setTodoCompletion(fixture.snapshot.siteTodos[0].id, true, at: BusinessDateValue(legacyText: "today")), .putDailyLog(invalid)], expectedRevision: 0)
        }
        #expect(try await repository.revision() == 0)
        #expect(try await repository.exportSnapshot().siteTodos[0].isDone == false)
    }

    @Test(arguments: [false, true])
    func movingLinkedRecordAcrossProjectsIsRejected(sqlite: Bool) async throws {
        var sample = RepositoryTestFixture.sample()
        sample.projectDrawings[0].linkedLogIDs = [sample.dailyLogs[0].id]
        let fixture = try RepositoryTestFixture(snapshot: sample)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        var moved = sample.dailyLogs[0]
        moved.projectId = sample.projects[1].id
        await #expect(throws: RepositoryError.self) {
            try await repository.apply([.putDailyLog(moved)], expectedRevision: 0)
        }
        #expect(try await repository.revision() == 0)
    }
}
