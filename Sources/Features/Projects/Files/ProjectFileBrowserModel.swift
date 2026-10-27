import Foundation
import Observation

struct ProjectFileCollectionSnapshot: Sendable {
    var logs: [DailyLog] = []
    var todos: [SiteTodo] = []
    var drawings: [ProjectDrawing] = []
    var documents: [ProjectDocument] = []
    var quickNotes: [QuickNote] = []

    init(logs: [DailyLog] = [], todos: [SiteTodo] = [], drawings: [ProjectDrawing] = [],
         documents: [ProjectDocument] = [], quickNotes: [QuickNote] = []) {
        self.logs = logs
        self.todos = todos
        self.drawings = drawings
        self.documents = documents
        self.quickNotes = quickNotes
    }

    @MainActor
    init(projectId: UUID, projectStore: ProjectStore) {
        self.init(logs: projectStore.dailyLogs(for: projectId), todos: projectStore.siteTodos(for: projectId),
                  drawings: projectStore.projectDrawings(for: projectId),
                  documents: projectStore.projectDocuments(for: projectId),
                  quickNotes: projectStore.quickNotes(for: projectId))
    }
}

struct ProjectFileBrowserSnapshot: Sendable {
    let projects: [Project]
    let filesByProject: [UUID: ProjectFileCollectionSnapshot]

    init(projects: [Project], filesByProject: [UUID: ProjectFileCollectionSnapshot]) {
        self.projects = projects
        self.filesByProject = filesByProject
    }

    @MainActor
    init(projectStore: ProjectStore) {
        projects = projectStore.projects
        filesByProject = Dictionary(uniqueKeysWithValues: projects.map {
            ($0.id, ProjectFileCollectionSnapshot(projectId: $0.id, projectStore: projectStore))
        })
    }
}

struct ProjectFilePreparedData: Sendable {
    let resultsByID: [String: ProjectFileSearchResult]
    let itemsByProject: [UUID: [ProjectFileCategory: [ProjectFileItem]]]
    let indexRows: [ProjectFileSearchIndexRow]
    let inspections: [ProjectDocumentDeliveryInspection]

    static func build(_ snapshot: ProjectFileBrowserSnapshot) throws -> Self {
        var results: [ProjectFileSearchResult] = []
        var itemsByProject: [UUID: [ProjectFileCategory: [ProjectFileItem]]] = [:]
        var inspections: [ProjectDocumentDeliveryInspection] = []
        for project in snapshot.projects {
            let files = snapshot.filesByProject[project.id] ?? ProjectFileCollectionSnapshot()
            for category in ProjectFileCategory.allCases {
                try Task.checkCancellation()
                let items = ProjectFileCollector.items(in: files, category: category).sorted {
                    $0.sortDate == $1.sortDate ? $0.id < $1.id : $0.sortDate > $1.sortDate
                }
                itemsByProject[project.id, default: [:]][category] = items
                results += items.map { ProjectFileSearchResult(project: project, item: $0) }
            }
            try Task.checkCancellation()
            inspections.append(ProjectDocumentDeliveryInspection(
                project: project, documents: files.documents, drawings: files.drawings,
                logs: files.logs, quickNotes: files.quickNotes
            ))
        }
        try Task.checkCancellation()
        return Self(resultsByID: Dictionary(results.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
                    itemsByProject: itemsByProject, indexRows: results.map(indexRow),
                    inspections: inspections.sorted(by: inspectionOrder))
    }

    func items(for projectId: UUID, category: ProjectFileCategory? = nil,
               health: ProjectFileHealthFilter = .all) -> [ProjectFileItem] {
        let categories = itemsByProject[projectId] ?? [:]
        let items = category.map { categories[$0] ?? [] }
            ?? ProjectFileCategory.allCases.flatMap { categories[$0] ?? [] }
        return health == .all ? items : items.filter { health.matches($0) }
    }

    private static func indexRow(_ result: ProjectFileSearchResult) -> ProjectFileSearchIndexRow {
        ProjectFileSearchIndexRow(
            id: result.id,
            searchableText: [result.project.name, result.project.location, result.item.title,
                             result.item.subtitle, result.item.fileType].joined(separator: " "),
            sortDate: result.item.sortDate
        )
    }

    private static func inspectionOrder(_ left: ProjectDocumentDeliveryInspection,
                                        _ right: ProjectDocumentDeliveryInspection) -> Bool {
        if left.isReadyForDelivery != right.isReadyForDelivery { return !left.isReadyForDelivery }
        if left.issueDetailCount != right.issueDetailCount { return left.issueDetailCount > right.issueDetailCount }
        return left.project.name.localizedStandardCompare(right.project.name) == .orderedAscending
    }
}

@MainActor
@Observable
final class ProjectFileBrowserModel {
    typealias Build = @Sendable (ProjectFileBrowserSnapshot) throws -> ProjectFilePreparedData

    private(set) var prepared: ProjectFilePreparedData?
    private(set) var loadedSignature: Int?
    private(set) var resultIDs: [String] = []
    private(set) var keyword = ""
    private(set) var isPreparing = false
    private(set) var isSearching = false
    private var generation = 0
    private let build: Build
    private let index = ProjectFileSearchIndexService()

    init(build: @escaping Build = { try ProjectFilePreparedData.build($0) }) {
        self.build = build
    }

    func data(for signature: Int) -> ProjectFilePreparedData? {
        loadedSignature == signature ? prepared : nil
    }

    func refresh(snapshot: @autoclosure () -> ProjectFileBrowserSnapshot, signature: Int, keyword rawKeyword: String,
                 debounce: Duration = .milliseconds(300)) async {
        generation &+= 1
        let request = generation
        let query = rawKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        isPreparing = loadedSignature != signature
        isSearching = !query.isEmpty
        defer {
            if generation == request { isPreparing = false
            isSearching = false }
        }
        do {
            if loadedSignature != signature {
                let build = build
                let source = snapshot()
                let work = Task.detached(priority: .userInitiated) { try build(source) }
                let data = try await withTaskCancellationHandler {
                    try await work.value
                } onCancel: { work.cancel() }
                guard !Task.isCancelled, generation == request else { return }
                await index.rebuild(signature: signature, rows: data.indexRows)
                guard !Task.isCancelled, generation == request else { return }
                prepared = data
                loadedSignature = signature
                resultIDs = []
            }
            if !query.isEmpty, !(await DebouncedTask.wait(for: debounce)) { return }
            guard !Task.isCancelled, generation == request else { return }
            let ids = query.isEmpty ? [] : await index.search(keyword: query)
            guard !Task.isCancelled, generation == request else { return }
            resultIDs = ids
            keyword = query
        } catch is CancellationError {
            // A newer version/query owns publication; never expose a partial file snapshot.
        } catch {
            // The production collector tolerates missing/unreadable files in each item.
            // Keep a failed injected or future throwing preparation from publishing stale data.
        }
    }

    func cancel() {
        generation &+= 1
        isPreparing = false
        isSearching = false
    }
}

enum ProjectFileBrowserSelection {
    static func projectID(current: UUID?, projectMatches: [UUID], fileMatches: [UUID]) -> UUID? {
        let eligible = Set(projectMatches).union(fileMatches)
        if let current, eligible.contains(current) { return current }
        return projectMatches.first ?? fileMatches.first
    }
}
