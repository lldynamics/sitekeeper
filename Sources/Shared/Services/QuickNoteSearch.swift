import Foundation
import Observation

enum QuickNoteSearch {
    static func filter(_ notes: [QuickNote], projects: [Project], keyword: String) -> [QuickNote] {
        let names = Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return SearchMatcher.filter(notes, keyword: keyword,
                                    sort: { $0.createdAt > $1.createdAt },
                                    extraFields: { note in
                                        [note.projectId.flatMap { names[$0] } ?? ""]
                                    })
    }
}

struct QuickNoteSearchRequest: Equatable {
    let version: Int
    let keyword: String
}

@MainActor
@Observable
final class QuickNoteSearchModel {
    typealias Search = @Sendable ([QuickNote], [Project], String) async -> [QuickNote]

    private(set) var notes: [QuickNote] = []
    private var generation = 0
    private let search: Search

    init(search: @escaping Search = { QuickNoteSearch.filter($0, projects: $1, keyword: $2) }) {
        self.search = search
    }

    func refresh(notes: [QuickNote], projects: [Project], keyword: String,
                 debounce: Duration = .milliseconds(150)) async {
        generation &+= 1
        let requestedGeneration = generation
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty, !(await DebouncedTask.wait(for: debounce)) { return }
        guard !Task.isCancelled, generation == requestedGeneration else { return }

        // The view supplies value snapshots; filtering never reads its live store.
        let search = search
        let work = Task.detached(priority: .userInitiated) {
            await search(notes, projects, keyword)
        }
        let results = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        guard !Task.isCancelled, generation == requestedGeneration else { return }
        self.notes = results
    }
}
