import Foundation
import Testing
@testable import sitekeeper

struct RepositoryWorkspaceCatalogTests {
    @Test func discoveryReopensSameCandidateAndNeverRebuildsWrittenCopy() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let catalog = RepositoryWorkspaceCatalog()
        #expect(try await catalog.entries(beside: fixture.source).isEmpty)
        let entry = try await catalog.create(source: fixture.source, assets: fixture.assets)
        let repository = try await catalog.open(entry)
        var project = fixture.snapshot.projects[0]
        project.name = "副本独立编辑"
        _ = try await repository.apply([.putProject(project)], expectedRevision: 0)
        try await repository.close()
        let entries = try await RepositoryWorkspaceCatalog().entries(beside: fixture.source)
        #expect(entries.count == 1 && entries[0].id == entry.id)
        let reopened = try await catalog.open(entries[0])
        #expect(try await reopened.page(RepositoryQuery(collection: .projects, searchText: "副本独立编辑"), after: nil, limit: 50).items.count == 1)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        try await reopened.close()
        let second = try await catalog.create(source: fixture.source, assets: fixture.assets)
        #expect(second.id != entry.id)
        #expect(try await catalog.entries(beside: fixture.source).count == 2)
    }

    @Test func failedAndRolledBackCandidatesAreNotOffered() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let catalog = RepositoryWorkspaceCatalog()
        let entry = try await catalog.create(source: fixture.source, assets: fixture.assets)
        try await SQLiteCandidateBuilder().rollback(candidateDirectory: entry.directory)
        await #expect(throws: CocoaError.self) { try await fixture.candidate(options: SQLiteCandidateOptions(availableBytes: { _ in 0 })) }
        #expect(try await catalog.entries(beside: fixture.source).isEmpty)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }
}
