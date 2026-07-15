import Foundation

struct ProjectFileSearchIndexRow: Sendable {
    let id: String
    let searchableText: String
    let sortDate: Date
}

actor ProjectFileSearchIndexService {
    private static let queryCacheLimit = 64

    private var dataSignature: Int?
    private var indexRows: [ProjectFileSearchIndexRow] = []
    private var bigramIndex: [String: [Int]] = [:]
    private var queryCache: [String: [String]] = [:]
    private var queryCacheOrder: [String] = []

    static func normalizedKeyword(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }

    func rebuild(signature: Int, rows: [ProjectFileSearchIndexRow]) {
        guard dataSignature != signature else { return }

        dataSignature = signature
        queryCache.removeAll(keepingCapacity: true)
        queryCacheOrder.removeAll(keepingCapacity: true)
        indexRows = rows
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
        bigramIndex = Self.makeBigramIndex(rows: indexRows)
    }

    func search(keyword: String) -> [String] {
        let normalized = Self.normalizedKeyword(keyword)
        guard !normalized.isEmpty else { return [] }
        if let cached = queryCache[normalized] {
            return cached
        }

        let ids = matchingIDs(for: normalized)
        cache(ids: ids, for: normalized)
        return ids
    }

    private static func bigrams(in text: String) -> Set<String> {
        var result: Set<String> = []
        var previous: Character?
        for character in text {
            if let previous {
                result.insert(String(previous) + String(character))
            }
            previous = character
        }
        return result
    }

    private static func makeBigramIndex(rows: [ProjectFileSearchIndexRow]) -> [String: [Int]] {
        var result: [String: [Int]] = [:]
        result.reserveCapacity(rows.count * 2)
        for (index, row) in rows.enumerated() {
            for bigram in bigrams(in: row.searchableText) {
                result[bigram, default: []].append(index)
            }
        }
        return result
    }

    private func matchingIDs(for normalized: String) -> [String] {
        let queryBigrams = Self.bigrams(in: normalized)
        guard !queryBigrams.isEmpty else {
            return indexRows.compactMap { row in
                row.searchableText.contains(normalized) ? row.id : nil
            }
        }

        let postingLists = queryBigrams.compactMap { bigramIndex[$0] }
        guard postingLists.count == queryBigrams.count,
              let shortest = postingLists.min(by: { $0.count < $1.count }) else {
            return []
        }

        var candidates = Set(shortest)
        for postingList in postingLists where postingList.count != shortest.count || postingList != shortest {
            candidates.formIntersection(postingList)
            if candidates.isEmpty { return [] }
        }
        return indexRows.enumerated().compactMap { index, row in
            guard candidates.contains(index), row.searchableText.contains(normalized) else { return nil }
            return row.id
        }
    }

    private func cache(ids: [String], for keyword: String) {
        if queryCache[keyword] == nil {
            if queryCacheOrder.count >= Self.queryCacheLimit {
                let expired = queryCacheOrder.removeFirst()
                queryCache.removeValue(forKey: expired)
            }
            queryCacheOrder.append(keyword)
        }
        queryCache[keyword] = ids
    }
}
