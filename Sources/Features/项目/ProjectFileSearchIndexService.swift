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
        queue.async {
            if self.dataSignature == signature {
                DispatchQueue.main.async {
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

            DispatchQueue.main.async {
                completion()
            }
        }
    }

    func search(keyword: String, completion: @escaping ([String]) -> Void) {
        let normalized = Self.normalizedKeyword(keyword)
        queue.async {
            guard !normalized.isEmpty else {
                DispatchQueue.main.async {
                    completion([])
                }
                return
            }

            if let cached = self.queryCache[normalized] {
                DispatchQueue.main.async {
                    completion(cached)
                }
                return
            }

            let ids = self.indexRows
                .filter { $0.searchableText.contains(normalized) }
                .map(\.id)

            self.queryCache[normalized] = ids
            DispatchQueue.main.async {
                completion(ids)
            }
        }
    }
}
