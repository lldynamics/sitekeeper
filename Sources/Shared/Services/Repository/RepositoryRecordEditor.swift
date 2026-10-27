import Foundation
import Observation

/// Detail and revision come from one database snapshot. Never acknowledge a save
/// or change the base revision until the transaction commits successfully.
@MainActor @Observable
final class RepositoryRecordEditor<Value: Codable & Sendable> {
    var draft: Value
    private(set) var isLoaded = false
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    @ObservationIgnored private(set) var revision: Int?
    @ObservationIgnored private let repository: any BusinessRepository
    @ObservationIgnored private let collection: RepositoryCollection
    @ObservationIgnored private let id: UUID?
    @ObservationIgnored private var generation = UUID()

    init(repository: any BusinessRepository, collection: RepositoryCollection, id: UUID?, initial: Value) {
        self.repository = repository
        self.collection = collection
        self.id = id
        draft = initial
    }

    func load() async {
        guard !isBusy else { return }
        generation = UUID()
        let token = generation
        isBusy = true
        errorMessage = nil
        defer { if generation == token { isBusy = false } }
        do {
            if let id {
                guard let detail = try await repository.detail(collection, id: id) else { throw RepositoryError.missingRecord }
                try Task.checkCancellation()
                guard generation == token else { return }
                draft = try JSONDecoder().decode(Value.self, from: detail.payload)
                revision = detail.revision
            } else {
                let current = try await repository.revision()
                try Task.checkCancellation()
                guard generation == token else { return }
                revision = current
            }
            isLoaded = true
        } catch {
            if generation == token { errorMessage = RepositoryUserMessage.describe(error) }
        }
    }

    func save(command: (Value) throws -> RepositoryCommand) async -> Bool {
        guard isLoaded, !isBusy, let revision else { return false }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            // A committed transaction remains successful even if its caller was cancelled.
            self.revision = try await repository.apply([command(draft)], expectedRevision: revision)
            return true
        } catch {
            errorMessage = RepositoryUserMessage.describe(error)
            return false
        }
    }
}
