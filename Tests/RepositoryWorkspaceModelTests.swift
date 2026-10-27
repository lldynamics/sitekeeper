import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct RepositoryWorkspaceModelTests {
    @Test func boundedPagesNavigateAndRecoverFromConcurrentWrites() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: true)
        let query = RepositoryQuery(collection: .dailyLogs, project: .project(fixture.snapshot.projects[0].id), order: .newestFirst)
        let model = RepositoryPageModel(repository: repository, query: query, pageSize: 2)
        await model.reset()
        let first = model.items
        #expect(first.count == 2)
        await model.next()
        #expect(model.pageNumber == 2 && model.items.count == 2)
        #expect(Set(first.map(\.id)).isDisjoint(with: model.items.map(\.id)))
        await model.previous()
        #expect(model.items == first)
        _ = try await repository.apply([.putDailyLog(DailyLog(date: BusinessDateValue(legacyText: "2030-01-01"), weather: "", content: "新记录", workers: NumericInputSupport.quantity(""), projectId: fixture.snapshot.projects[0].id))], expectedRevision: 0)
        await model.next()
        #expect(model.pageNumber == 1)
        #expect(model.items.first?.title == "新记录")
        #expect(model.errorMessage == nil)
        #expect(!model.isLoading)
        await model.reset(to: RepositoryQuery(collection: .dailyLogs, project: .project(fixture.snapshot.projects[1].id)))
        #expect(model.items.isEmpty && model.pageNumber == 1 && model.nextCursor == nil)
    }

    @Test func oldSearchResponseAndCancelledRequestCannotOverwriteNewPage() async throws {
        let repository = try RepositoryControlledRepository(snapshot: RepositoryTestFixture.sample())
        let model = RepositoryPageModel(repository: repository, query: RepositoryQuery(collection: .projects, searchText: "hold"))
        let old = Task { await model.reset() }
        await repository.waitUntilBlocked()
        await model.reset(to: RepositoryQuery(collection: .projects))
        #expect(model.items.count == 2)
        await repository.release()
        await old.value
        #expect(model.items.count == 2 && !model.isLoading)
        let cancelled = Task { await model.reset(to: RepositoryQuery(collection: .projects, searchText: "hold")) }
        await repository.waitUntilBlocked()
        cancelled.cancel()
        await repository.release()
        await cancelled.value
        #expect(!model.isLoading)
        await model.reset(to: RepositoryQuery(collection: .projects))
        #expect(model.items.count == 2)
    }

    @Test func failedPageCanRetryWithoutAdvancingOrLosingVisibleRows() async throws {
        let repository = try RepositoryControlledRepository(snapshot: RepositoryTestFixture.sample())
        let model = RepositoryPageModel(repository: repository, query: RepositoryQuery(collection: .dailyLogs), pageSize: 2)
        await model.reset()
        let original = model.items
        await repository.failReads(true)
        await model.next()
        #expect(model.pageNumber == 1 && model.items == original && model.errorMessage != nil)
        await repository.failReads(false)
        await model.next()
        #expect(model.pageNumber == 2 && model.items.count == 2 && model.errorMessage == nil)
    }

    @Test(arguments: [false, true])
    func staleEditorAndFailedSaveKeepDraftAndSource(sqlite: Bool) async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        let original = fixture.snapshot.dailyLogs[0]
        let editor = RepositoryRecordEditor(repository: repository, collection: .dailyLogs, id: original.id, initial: original)
        await editor.load()
        #expect(editor.isLoaded && editor.revision == 0)
        editor.draft.content = "本地尚未保存的编辑"
        var remote = original
        remote.content = "其他窗口已保存"
        _ = try await repository.apply([.putDailyLog(remote)], expectedRevision: 0)
        #expect(await editor.save(command: RepositoryCommand.putDailyLog) == false)
        #expect(editor.draft.content == "本地尚未保存的编辑")
        #expect(editor.errorMessage != nil && editor.revision == 0 && !editor.isBusy)
        await editor.load()
        #expect(editor.draft.content == remote.content && editor.revision == 1)
        editor.draft.content = "核对后保存"
        #expect(await editor.save(command: RepositoryCommand.putDailyLog))
        let saved = try #require(try await repository.detail(.dailyLogs, id: original.id))
        #expect(saved.revision == 2)
        #expect(try JSONDecoder().decode(DailyLog.self, from: saved.payload).allPhotoFileNames == original.allPhotoFileNames)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test func saveErrorDoesNotAdvanceRevisionAndRetryCommitsOnce() async throws {
        let snapshot = RepositoryTestFixture.sample()
        let repository = try RepositoryControlledRepository(snapshot: snapshot)
        let editor = RepositoryRecordEditor(repository: repository, collection: .projects, id: snapshot.projects[0].id, initial: snapshot.projects[0])
        await editor.load()
        editor.draft.name = "磁盘恢复后保存"
        await repository.failWrites(true)
        #expect(await editor.save(command: RepositoryCommand.putProject) == false)
        #expect(editor.draft.name == "磁盘恢复后保存" && editor.revision == 0)
        #expect(try await repository.revision() == 0)
        await repository.failWrites(false)
        #expect(await editor.save(command: RepositoryCommand.putProject))
        #expect(try await repository.revision() == 1)
    }

    @Test func newProjectAndLogPersistAndMissingDetailCannotBeSaved() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let repository = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        let project = Project(name: "新建副本项目", location: "")
        let editor = RepositoryRecordEditor(repository: repository, collection: .projects, id: nil, initial: project)
        #expect(await editor.save(command: RepositoryCommand.putProject) == false)
        await editor.load()
        #expect(await editor.save(command: RepositoryCommand.putProject))
        let log = DailyLog(date: BusinessDateValue(legacyText: "2026-10-24"), weather: "", content: "新建日志", workers: NumericInputSupport.quantity(""), projectId: project.id)
        let logEditor = RepositoryRecordEditor(repository: repository, collection: .dailyLogs, id: nil, initial: log)
        await logEditor.load()
        #expect(await logEditor.save(command: RepositoryCommand.putDailyLog))
        let missing = RepositoryRecordEditor(repository: repository, collection: .projects, id: UUID(), initial: project)
        await missing.load()
        #expect(!missing.isLoaded && missing.errorMessage != nil)
        #expect(await missing.save(command: RepositoryCommand.putProject) == false)
        try await repository.close()
        let reopened = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        #expect(try await reopened.detail(.projects, id: project.id) != nil)
        #expect(try await reopened.page(RepositoryQuery(collection: .dailyLogs, project: .project(project.id)), after: nil, limit: 50).items.map(\.id) == [log.id])
        try await reopened.close()
    }
}

actor RepositoryControlledRepository: BusinessRepository {
    let base: JSONSnapshotRepository
    private var readFailure = false
    private var writeFailure = false
    private var held: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    init(snapshot: BackupSnapshot) throws { base = try JSONSnapshotRepository(snapshot: snapshot) }
    func failReads(_ value: Bool) { readFailure = value }
    func failWrites(_ value: Bool) { writeFailure = value }
    func waitUntilBlocked() async {
        if held != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { held?.resume()
    held = nil }
    func revision() async throws -> Int { await base.revision() }
    func record(_ collection: RepositoryCollection, id: UUID) async throws -> Data? { await base.record(collection, id: id) }
    func detail(_ collection: RepositoryCollection, id: UUID) async throws -> RepositoryDetail? { await base.detail(collection, id: id) }
    func page(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) async throws -> RepositoryPage {
        if readFailure { throw CocoaError(.fileReadNoPermission) }
        if query.searchText == "hold" {
            await withCheckedContinuation { held = $0
            started?.resume()
            started = nil }
        }
        return try await base.page(query, after: after, limit: limit)
    }
    func financialPage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) async throws -> RepositoryFinancialPage {
        if readFailure { throw CocoaError(.fileReadNoPermission) }
        if query.searchText == "hold" {
            await withCheckedContinuation { held = $0
            started?.resume()
            started = nil }
        }
        return try await base.financialPage(query, after: after, limit: limit)
    }
    func laborPage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) async throws -> RepositoryLaborPage {
        if readFailure { throw CocoaError(.fileReadNoPermission) }
        if query.searchText == "hold" {
            await withCheckedContinuation { held = $0
            started?.resume()
            started = nil }
        }
        return try await base.laborPage(query, after: after, limit: limit)
    }

    func quotePage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) async throws -> RepositoryQuotePage {
        if readFailure { throw CocoaError(.fileReadNoPermission) }
        if query.searchText == "hold" {
            await withCheckedContinuation { held = $0
            started?.resume()
            started = nil }
        }
        return try await base.quotePage(query, after: after, limit: limit)
    }

    func materialPage(_ query: RepositoryQuery, after: RepositoryCursor?, limit: Int) async throws -> RepositoryMaterialPage {
        if readFailure { throw CocoaError(.fileReadNoPermission) }
        if query.searchText == "hold" {
            await withCheckedContinuation { held = $0
            started?.resume()
            started = nil }
        }
        return try await base.materialPage(query, after: after, limit: limit)
    }

    func stockPage(_ query: RepositoryStockQuery, after: RepositoryStockCursor?, limit: Int) async throws -> RepositoryStockPage {
        if readFailure { throw CocoaError(.fileReadNoPermission) }
        if query.searchText == "hold" {
            await withCheckedContinuation { held = $0
            started?.resume()
            started = nil }
        }
        return try await base.stockPage(query, after: after, limit: limit)
    }
    func summary(_ query: RepositoryQuery) async throws -> RepositorySummary { try await base.summary(query) }
    func apply(_ commands: [RepositoryCommand], expectedRevision: Int) async throws -> Int {
        if writeFailure { throw CocoaError(.fileWriteOutOfSpace) }
        return try await base.apply(commands, expectedRevision: expectedRevision)
    }
    func exportSnapshot() async throws -> BackupSnapshot { try await base.exportSnapshot() }
    func attachments(owner: RepositoryCollection, id: UUID) async throws -> [RepositoryAttachment] { try await base.attachments(owner: owner, id: id) }
}
