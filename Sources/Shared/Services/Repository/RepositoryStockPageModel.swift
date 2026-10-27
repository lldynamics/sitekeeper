import Foundation
import Observation

/// Holds one page, never accumulated bodies or the complete project/log collection.
@MainActor @Observable
final class RepositoryStockPageModel {
    private(set) var totalMaterials = 0
    private(set) var unnamedMovements = 0
    private(set) var items: [RepositoryStockLine] = []
    private(set) var query: RepositoryStockQuery
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var pageNumber = 1
    private(set) var nextCursor: RepositoryStockCursor?
    @ObservationIgnored private let repository: any BusinessRepository
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private var starts: [RepositoryStockCursor?] = [nil]
    @ObservationIgnored private var generation = UUID()

    init(repository: any BusinessRepository, query: RepositoryStockQuery, pageSize: Int = 50) {
        self.repository = repository
        self.query = query
        self.pageSize = pageSize
    }

    func reset(to query: RepositoryStockQuery? = nil) async {
        if let query { self.query = query }
        generation = UUID()
        starts = [nil]
        pageNumber = 1
        items = []
        totalMaterials = 0
        unnamedMovements = 0
        nextCursor = nil
        await load(start: nil, targetPage: 1)
    }

    func next() async {
        guard !isLoading, let nextCursor else { return }
        await load(start: nextCursor, targetPage: pageNumber + 1)
    }

    func previous() async {
        guard !isLoading, pageNumber > 1 else { return }
        await load(start: starts[pageNumber - 2], targetPage: pageNumber - 1)
    }

    func retry() async {
        guard !isLoading else { return }
        await load(start: starts[pageNumber - 1], targetPage: pageNumber)
    }

    func cancel() {
        generation = UUID()
        isLoading = false
    }

    private func load(start: RepositoryStockCursor?, targetPage: Int) async {
        let token = generation
        isLoading = true
        errorMessage = nil
        defer { if token == generation { isLoading = false } }
        do {
            let page = try await WarehouseRepository(repository: repository).stock(query, after: start, limit: pageSize)
            guard token == generation, !Task.isCancelled else { return }
            items = page.items
            totalMaterials = page.totalMaterials
            unnamedMovements = page.unnamedMovements
            nextCursor = page.next
            if targetPage > starts.count { starts.append(start) }
            pageNumber = targetPage
        } catch RepositoryError.staleRevision {
            guard token == generation, !Task.isCancelled else { return }
            await reset()
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            errorMessage = RepositoryUserMessage.describe(error)
        }
    }
}
