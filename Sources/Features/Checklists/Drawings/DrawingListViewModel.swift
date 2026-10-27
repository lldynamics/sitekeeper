import Foundation

enum DrawingAvailabilityFilter: String, CaseIterable, Identifiable {
    case all
    case current
    case missing
    case externalOpenFailed
    case unchecked

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return AppLocalization.string("全部图纸")
        case .current:
            return AppLocalization.string("当前版")
        case .missing:
            return AppLocalization.string("原件缺失")
        case .externalOpenFailed:
            return AppLocalization.string("外部失败")
        case .unchecked:
            return AppLocalization.string("未检查")
        }
    }

    var icon: String {
        switch self {
        case .all:
            return "tray.full"
        case .current:
            return "checkmark.seal.fill"
        case .missing:
            return "exclamationmark.triangle.fill"
        case .externalOpenFailed:
            return "arrow.up.forward.app.fill"
        case .unchecked:
            return "questionmark.circle.fill"
        }
    }

    func matches(_ drawing: ProjectDrawing) -> Bool {
        switch self {
        case .all:
            return true
        case .current:
            return drawing.isCurrentVersion
        case .missing:
            return drawing.fileAvailabilityStatus == .missing
        case .externalOpenFailed:
            return !drawing.externalOpenFailureReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .unchecked:
            return drawing.fileAvailabilityStatus == .unknown
        }
    }
}

struct DrawingListViewModel {
    var projects: [Project]
    var drawings: [ProjectDrawing]
    var selectedProjectID: UUID?
    var searchText: String
    var recentDrawingIDs: [UUID]
    var availabilityFilter: DrawingAvailabilityFilter = .all

    var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sortedDrawings: [ProjectDrawing] {
        drawings
            .filter(Self.isSupportedDrawing(_:))
            .sorted { lhs, rhs in
                let left = Formatters.parseDateOrDateTime(lhs.importedAt) ?? .distantPast
                let right = Formatters.parseDateOrDateTime(rhs.importedAt) ?? .distantPast
                if left != right {
                    return left > right
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private var projectScopedDrawings: [ProjectDrawing] {
        selectedProjectID.map { projectId in
            sortedDrawings.filter { $0.projectId == projectId }
        } ?? sortedDrawings
    }

    private var searchScopedDrawings: [ProjectDrawing] {
        guard !normalizedSearchText.isEmpty else { return projectScopedDrawings }
        return projectScopedDrawings.filter(matchesSearch(_:))
    }

    var filteredDrawings: [ProjectDrawing] {
        searchScopedDrawings.filter(availabilityFilter.matches(_:))
    }

    func count(for filter: DrawingAvailabilityFilter) -> Int {
        searchScopedDrawings.filter(filter.matches(_:)).count
    }

    func hasDrawings(matching filter: DrawingAvailabilityFilter) -> Bool {
        count(for: filter) > 0
    }

    var scannableDrawings: [ProjectDrawing] {
        projectScopedDrawings
    }

    var filteredResultSummary: String? {
        guard availabilityFilter != .all else { return nil }
        return String(
            format: AppLocalization.string("筛选 %@，%lld 张图纸"),
            availabilityFilter.title,
            Int64(filteredDrawings.count)
        )
    }

    private func matchesSearch(_ drawing: ProjectDrawing) -> Bool {
        let query = normalizedSearchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let fields = [
            drawing.name,
            drawing.drawingNumber,
            drawing.discipline,
            drawing.floorArea,
            drawing.fileName,
            drawing.version,
            drawing.issuedAt.storageText,
            drawing.receiver,
            drawing.fileType,
            drawing.fileAvailabilityStatus.displayName,
            drawing.externalOpenFailureReason,
            drawing.issueStatus.displayName,
            drawing.issueNote,
            drawing.note,
            projectName(for: drawing.projectId),
            ProjectDetailDrawingHelper.zipEntryPath(for: drawing) ?? "",
            ProjectDetailDrawingHelper.zipFolderPath(for: drawing) ?? ""
        ]
        return fields.contains { value in
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(query)
        }
    }

    private func isRecentDrawingVisible(_ drawing: ProjectDrawing) -> Bool {
        if let selectedProjectID, drawing.projectId != selectedProjectID {
            return false
        }
        if !availabilityFilter.matches(drawing) {
            return false
        }
        guard !normalizedSearchText.isEmpty else { return true }
        return matchesSearch(drawing)
    }

    var currentFilteredDrawings: [ProjectDrawing] {
        filteredDrawings.filter(\.isCurrentVersion)
    }

    var historicalFilteredDrawings: [ProjectDrawing] {
        filteredDrawings.filter { !$0.isCurrentVersion }
    }

    var recentDrawings: [ProjectDrawing] {
        recentDrawingIDs.compactMap { id in
            sortedDrawings.first(where: { $0.id == id })
        }.filter(isRecentDrawingVisible(_:))
    }

    func projectName(for projectID: UUID) -> String {
        projects.first(where: { $0.id == projectID })?.name ?? AppLocalization.string("未知项目")
    }

    static func recentDrawingIDs(from rawValue: String) -> [UUID] {
        rawValue
            .split(separator: "\n")
            .compactMap { UUID(uuidString: String($0)) }
    }

    static func rawRecentDrawingIDs(recording drawingID: UUID, in rawValue: String, limit: Int = 12) -> String {
        var ids = recentDrawingIDs(from: rawValue)
        ids.removeAll { $0 == drawingID }
        ids.insert(drawingID, at: 0)
        return ids.prefix(limit).map(\.uuidString).joined(separator: "\n")
    }

    static func isSupportedDrawing(_ drawing: ProjectDrawing) -> Bool {
        ProjectDrawing.allowedFileExtensions.contains(drawing.fileType.lowercased())
    }
}
