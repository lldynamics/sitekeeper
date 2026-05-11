import Foundation

struct ProjectFileSearchIndexRow {
    let id: String
    let searchableText: String
    let sortDate: Date
}

final class ProjectFileSearchIndexService {
    private let queue = DispatchQueue(label: "project-file-search-index", qos: .userInitiated)
    private var dataSignature: Int = 0
    private var indexRows: [ProjectFileSearchIndexRow] = []
    private var queryCache: [String: [String]] = [:]

    static func normalizedKeyword(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    func rebuild(signature: Int, rows: [ProjectFileSearchIndexRow], completion: @escaping () -> Void) {
        queue.async { [weak self] in
            guard let self else {
                Task { @MainActor in
                    completion()
                }
                return
            }
            if self.dataSignature == signature {
                Task { @MainActor in
                    completion()
                }
                return
            }

            self.dataSignature = signature
            self.queryCache.removeAll(keepingCapacity: true)
            self.indexRows = rows
                .map { row in
                    ProjectFileSearchIndexRow(
                        id: row.id,
                        searchableText: Self.normalizedKeyword(row.searchableText),
                        sortDate: row.sortDate
                    )
                }
                .sorted { lhs, rhs in
                    lhs.sortDate > rhs.sortDate
                }

            Task { @MainActor in
                completion()
            }
        }
    }

    func search(keyword: String, completion: @escaping ([String]) -> Void) {
        let normalized = Self.normalizedKeyword(keyword)
        queue.async { [weak self] in
            guard let self else {
                Task { @MainActor in
                    completion([])
                }
                return
            }
            guard !normalized.isEmpty else {
                Task { @MainActor in
                    completion([])
                }
                return
            }

            if let cached = self.queryCache[normalized] {
                Task { @MainActor in
                    completion(cached)
                }
                return
            }

            let ids = self.indexRows
                .filter { $0.searchableText.contains(normalized) }
                .map(\.id)

            self.queryCache[normalized] = ids
            Task { @MainActor in
                completion(ids)
            }
        }
    }
}
