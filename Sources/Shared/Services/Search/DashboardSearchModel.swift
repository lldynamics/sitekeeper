import Foundation
import Observation

/// Only scalar revisions participate in SwiftUI task identity; comparing this request
/// never hashes or scans the underlying record collections.
struct DashboardSearchRequest: Equatable, Sendable {
    var keyword: String
    var projectID: UUID? = nil
    var category: RealtimeSearchSuggestion.Category? = nil
    var collectionVersions: [UInt64] = []
    var language = ""
    var timeZoneIdentifier = ""
    var storeSource: ObjectIdentifier? = nil
    var projectSource: ObjectIdentifier? = nil
    var financeSource: ObjectIdentifier? = nil
    var limit = 10
}

/// A value snapshot copied once per refresh, never read from live stores off actor.
struct DashboardSearchSnapshot: Sendable {
    var projects: [Project] = []
    var contacts: [ProjectContact] = []
    var suppliers: [SupplierProfile] = []
    var materials: [MaterialPriceEntry] = []
    var methods: [ConstructionMethod] = []
    var logs: [DailyLog] = []
    var todos: [SiteTodo] = []
    var notes: [QuickNote] = []
    var quotes: [QuoteItem] = []
    var financialRecords: [ProjectFinancialRecord] = []
    var drawings: [ProjectDrawing] = []
    var documents: [ProjectDocument] = []

    /// Also serves as the deterministic synchronous entry point for benchmarks.
    func suggestions(for request: DashboardSearchRequest) -> [RealtimeSearchSuggestion] {
        RealtimeSearchSuggestionBuilder.suggestions(
            keyword: request.keyword,
            categories: request.category.map { Set([$0]) } ?? Set(RealtimeSearchSuggestion.Category.allCases),
            projects: projects, contacts: contacts, suppliers: suppliers, materials: materials,
            methods: methods, logs: logs, todos: todos, notes: notes, quotes: quotes,
            financialRecords: financialRecords, drawings: drawings, documents: documents,
            projectID: request.projectID, limit: request.limit
        )
    }
}

@MainActor
@Observable
final class DashboardSearchModel {
    typealias Search = @Sendable (DashboardSearchSnapshot, DashboardSearchRequest) async -> [RealtimeSearchSuggestion]

    private var results: [RealtimeSearchSuggestion] = []
    private var completedRequest: DashboardSearchRequest?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let search: Search

    init(search: @escaping Search = { $0.suggestions(for: $1) }) {
        self.search = search
    }

    /// Hide stale rows immediately when the query, scope, or data revisions change,
    /// including the interval before SwiftUI starts the replacement task.
    func suggestions(for request: DashboardSearchRequest) -> [RealtimeSearchSuggestion] {
        completedRequest == request ? results : []
    }

    func refresh(snapshot: DashboardSearchSnapshot, request: DashboardSearchRequest,
                 debounce: Duration = .milliseconds(150)) async {
        guard !Task.isCancelled else { return }
        generation &+= 1
        let requestedGeneration = generation
        if request.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || request.limit <= 0 {
            results = []
            completedRequest = request
            return
        }
        guard await DebouncedTask.wait(for: debounce), !Task.isCancelled,
              generation == requestedGeneration else { return }

        let search = search
        let work = Task.detached(priority: .userInitiated) { await search(snapshot, request) }
        let matches = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        guard !Task.isCancelled, generation == requestedGeneration else { return }
        results = matches
        completedRequest = request
    }
}
