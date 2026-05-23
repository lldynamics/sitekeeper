import SwiftUI

private enum ProjectFileSearchContinuationTimeout {
    static let interval: DispatchTimeInterval = .seconds(8)
}

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
        var hasher = Hasher()

        for project in projectStore.projects {
            hasher.combine(project.id)
            hasher.combine(project.name)
            hasher.combine(project.location)
        }

        for log in projectStore.dailyLogs {
            hasher.combine(log.id)
            hasher.combine(log.projectId)
            hasher.combine(log.date)
            for photo in log.photoAttachments {
                hasher.combine(photo.id)
                hasher.combine(photo.fileName)
                hasher.combine(photo.note)
                hasher.combine(photo.tag)
            }
        }

        for todo in projectStore.siteTodos {
            hasher.combine(todo.id)
            hasher.combine(todo.projectId)
            hasher.combine(todo.title)
            hasher.combine(todo.dueDate)
            hasher.combine(todo.completedAt)
            hasher.combine(todo.rectificationBeforePhotoFileName)
            hasher.combine(todo.rectificationAfterPhotoFileName)
        }

        for drawing in projectStore.projectDrawings {
            hasher.combine(drawing.id)
            hasher.combine(drawing.projectId)
            hasher.combine(drawing.name)
            hasher.combine(drawing.fileName)
            hasher.combine(drawing.fileType)
            hasher.combine(drawing.importedAt)
            hasher.combine(drawing.note)
        }

        for document in projectStore.projectDocuments {
            hasher.combine(document.id)
            hasher.combine(document.projectId)
            hasher.combine(document.title)
            hasher.combine(document.fileName)
            hasher.combine(document.fileType)
            hasher.combine(document.category)
            hasher.combine(document.submissionStatus.rawValue)
            hasher.combine(document.responsiblePerson)
            hasher.combine(document.formedAt)
            hasher.combine(document.createdAt)
            hasher.combine(document.amount)
            hasher.combine(document.note)
            hasher.combine(document.linkedFinancialRecordId)
        }

        for note in projectStore.quickNotes {
            hasher.combine(note.id)
            hasher.combine(note.projectId)
            hasher.combine(note.title)
            hasher.combine(note.createdAt)
            hasher.combine(note.updatedAt)
            for attachment in note.attachments {
                hasher.combine(attachment.id)
                hasher.combine(attachment.kind)
                hasher.combine(attachment.fileName)
                hasher.combine(attachment.originalName)
                hasher.combine(attachment.createdAt)
            }
        }

        return hasher.finalize()
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

    func refreshSearchIndexIfNeeded(completion: @escaping () -> Void) {
        let signature = fileSearchDataSignature
        if signature == indexedDataSignature, !searchResultByID.isEmpty {
            completion()
            return
        }

        let allResults = collectAllFileSearchResults()
        searchResultByID = Dictionary(uniqueKeysWithValues: allResults.map { ($0.id, $0) })
        let rows = makeIndexRows(from: allResults)

        isBuildingFileIndex = true
        fileSearchService.rebuild(signature: signature, rows: rows) {
            indexedDataSignature = signature
            isBuildingFileIndex = false
            completion()
        }
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

    func refreshSearchIndexIfNeeded() async {
        await withTimeoutContinuation(
            timeout: ProjectFileSearchContinuationTimeout.interval,
            fallback: ()
        ) { resume in
            refreshSearchIndexIfNeeded {
                resume(())
            }
        }
    }

    func searchIndexedFileIDs(keyword: String) async -> [String] {
        await withTimeoutContinuation(
            timeout: ProjectFileSearchContinuationTimeout.interval,
            fallback: []
        ) { resume in
            fileSearchService.search(keyword: keyword) { ids in
                resume(ids)
            }
        }
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

    private func withTimeoutContinuation<T>(
        timeout: DispatchTimeInterval,
        fallback: T,
        operation: (@escaping (T) -> Void) -> Void
    ) async -> T {
        await withCheckedContinuation { continuation in
            let resumeQueue = DispatchQueue(label: "project-file-browser.continuation-resume")
            var didResume = false

            let resume: (T) -> Void = { value in
                resumeQueue.async {
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(returning: value)
                }
            }

            operation { value in
                resume(value)
            }

            resumeQueue.asyncAfter(deadline: .now() + timeout) {
                resume(fallback)
            }
        }
    }
}
