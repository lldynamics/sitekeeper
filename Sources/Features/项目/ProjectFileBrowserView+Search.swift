import SwiftUI

extension ProjectFileBrowserView {
    var normalizedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedDebouncedQuery: String {
        fileBrowserModel.keyword
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
        return fileBrowserModel.resultIDs.compactMap { preparedFiles?.resultsByID[$0] }
    }

    var displayedFileSearchResults: [ProjectFileSearchResult] {
        guard normalizedQuery == normalizedDebouncedQuery else { return [] }
        return fileSearchResults.filter { healthFilter.matches($0.item) }
    }

    var fileSearchDataSignature: Int {
        projectStore.fileSearchVersion
    }

    var preparedFiles: ProjectFilePreparedData? {
        fileBrowserModel.data(for: fileSearchDataSignature)
    }

    var isBuildingFileIndex: Bool { fileBrowserModel.isPreparing }
    var isSearchingFiles: Bool { fileBrowserModel.isSearching }

    @MainActor
    func runFileSearchTask(for text: String) async {
        await fileBrowserModel.refresh(
            snapshot: ProjectFileBrowserSnapshot(projectStore: projectStore),
            signature: fileSearchDataSignature,
            keyword: text
        )
        guard !Task.isCancelled else { return }
        syncSplitSelectionIfNeeded()
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
