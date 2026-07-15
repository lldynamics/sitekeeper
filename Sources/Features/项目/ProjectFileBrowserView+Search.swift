import SwiftUI

extension ProjectFileBrowserView {
    var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedDebouncedQuery: String {
        debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var fileSearchExecutionKey: FileSearchExecutionKey {
        FileSearchExecutionKey(keyword: normalizedQuery, signature: fileSearchDataSignature)
    }

    var searchMatchedProjects: [Project] {
        SearchMatcher.filter(
            projectStore.projects,
            keyword: normalizedQuery,
            sort: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }

    var fileSearchResults: [ProjectFileSearchResult] {
        guard !normalizedDebouncedQuery.isEmpty else { return [] }
        return searchResultIDs.compactMap { searchResultByID[$0] }
    }

    var displayedFileSearchResults: [ProjectFileSearchResult] {
        guard normalizedQuery == normalizedDebouncedQuery else { return [] }
        return fileSearchResults.filter { healthFilter.matches($0.item) }
    }

    var fileSearchDataSignature: Int {
        projectStore.fileSearchVersion
    }

    func collectAllFileSearchResults() -> [ProjectFileSearchResult] {
        var results: [ProjectFileSearchResult] = []

        for project in projectStore.projects {
            for category in ProjectFileCategory.allCases {
                let items = ProjectFileCollector.items(for: project.id, category: category, projectStore: projectStore)
                for item in items {
                    results.append(ProjectFileSearchResult(project: project, item: item))
                }
            }
        }

        return results
    }

    func makeIndexRows(from results: [ProjectFileSearchResult]) -> [ProjectFileSearchIndexRow] {
        results.map { result in
            let searchable = [
                result.project.name,
                result.project.location,
                result.item.title,
                result.item.subtitle,
                result.item.fileType
            ].joined(separator: " ")

            return ProjectFileSearchIndexRow(
                id: result.id,
                searchableText: searchable,
                sortDate: result.item.sortDate
            )
        }
    }

    @MainActor
    func refreshSearchIndexIfNeeded() async {
        let signature = fileSearchDataSignature
        if signature == indexedDataSignature, !searchResultByID.isEmpty {
            return
        }

        let allResults = collectAllFileSearchResults()
        searchResultByID = Dictionary(uniqueKeysWithValues: allResults.map { ($0.id, $0) })
        let rows = makeIndexRows(from: allResults)

        isBuildingFileIndex = true
        await fileSearchService.rebuild(signature: signature, rows: rows)
        indexedDataSignature = signature
        isBuildingFileIndex = false
    }

    @MainActor
    func runFileSearchTask(for text: String) async {
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            debouncedSearchText = ""
            searchResultIDs = []
            isSearchingFiles = false
            return
        }

        isSearchingFiles = true
        guard await DebouncedTask.wait(for: .milliseconds(300)) else { return }
        let requestedKeyword = keyword
        await refreshSearchIndexIfNeeded()
        guard !Task.isCancelled else { return }
        let ids = await searchIndexedFileIDs(keyword: requestedKeyword)
        guard !Task.isCancelled else { return }
        guard requestedKeyword == normalizedQuery else { return }
        searchResultIDs = ids
        debouncedSearchText = requestedKeyword
        isSearchingFiles = false
    }

    func searchIndexedFileIDs(keyword: String) async -> [String] {
        await fileSearchService.search(keyword: keyword)
    }

    var missingResultCount: Int {
        displayedFileSearchResults.reduce(0) { result, item in
            result + (item.item.exists ? 0 : 1)
        }
    }

    var fileBrowserSearchSuggestions: [RealtimeSearchSuggestion] {
        if !displayedFileSearchResults.isEmpty {
            return displayedFileSearchResults.prefix(8).map { result in
                RealtimeSearchSuggestion(
                    id: "file-\(result.id)",
                    category: .file,
                    entityId: result.project.id,
                    title: result.item.title,
                    subtitleParts: [result.project.name, result.item.subtitle],
                    score: result.item.exists ? 120 : 80
                )
            }
        }

        return filteredProjects.prefix(8).map { project in
            let summary = ProjectFileSummary(projectId: project.id, projectStore: projectStore)
            return RealtimeSearchSuggestion(
                id: "project-\(project.id.uuidString)",
                category: .project,
                entityId: project.id,
                title: project.name,
                subtitleParts: [
                    project.location,
                    String(format: String(localized: "%lld 个文件"), Int64(summary.totalCount))
                ],
                score: 100
            )
        }
    }
}
