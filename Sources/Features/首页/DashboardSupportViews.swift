import SwiftUI

enum DashboardDestination {
    case dailyLog(initialProjectId: UUID? = nil, autoOpenComposer: Bool = false, focusedLogId: UUID? = nil)
    case siteTodo(initialProjectId: UUID? = nil, autoOpenComposer: Bool = false, focusedTodoId: UUID? = nil)
    case watermarkCamera(initialProjectId: UUID? = nil, autoOpenCameraOnAppear: Bool = false)
    case projectDetail(
        projectId: UUID,
        autoOpenFinancialAdd: Bool = false,
        autoOpenDocumentScanSetup: Bool = false,
        autoOpenDeliveryGuide: Bool = false,
        initialMode: ProjectDetailMode? = nil
    )
    case bookkeepingProjectPicker(projects: [Project])
    case projectList(initialOverviewFilter: ProjectOverviewFilter? = nil)
    case warehouseOverview
    case warehouse(project: Project)
    case dataManagement(initialRoute: DataManagementRoute? = nil)
    case projectContacts(focusedContactId: UUID? = nil)
    case materialPriceDatabase(focusedEntryId: UUID? = nil)
    case constructionMethodLibrary(focusedMethodId: UUID? = nil)
    case materialPriceSpikeDetails
}

struct DashboardDestinationSelection: Identifiable, Hashable {
    let id = UUID()
    let destination: DashboardDestination

    static func == (lhs: DashboardDestinationSelection, rhs: DashboardDestinationSelection) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@ViewBuilder
func dashboardDestinationView(_ destination: DashboardDestination) -> some View {
    switch destination {
    case .dailyLog(let initialProjectId, let autoOpenComposer, let focusedLogId):
        DailyLogView(
            initialProjectId: initialProjectId,
            autoOpenComposer: autoOpenComposer,
            focusedLogId: focusedLogId
        )
    case .siteTodo(let initialProjectId, let autoOpenComposer, let focusedTodoId):
        SiteTodoView(
            initialProjectId: initialProjectId,
            autoOpenComposer: autoOpenComposer,
            focusedTodoId: focusedTodoId
        )
    case .watermarkCamera(let initialProjectId, let autoOpenCameraOnAppear):
        WatermarkCameraToolView(
            initialProjectId: initialProjectId,
            autoOpenCameraOnAppear: autoOpenCameraOnAppear
        )
    case .projectDetail(
        let projectId,
        let autoOpenFinancialAdd,
        let autoOpenDocumentScanSetup,
        let autoOpenDeliveryGuide,
        let initialMode
    ):
        ProjectDetailView(
            projectId: projectId,
            initialMode: initialMode,
            autoOpenFinancialAdd: autoOpenFinancialAdd,
            autoOpenDocumentScanSetup: autoOpenDocumentScanSetup,
            autoOpenDeliveryGuide: autoOpenDeliveryGuide
        )
    case .bookkeepingProjectPicker(let projects):
        BookkeepingProjectPickerView(projects: projects)
    case .projectList(let initialOverviewFilter):
        ProjectListView(initialOverviewFilter: initialOverviewFilter)
    case .warehouseOverview:
        ProjectWarehouseOverviewView()
    case .warehouse(let project):
        ProjectWarehouseView(project: project)
    case .dataManagement(let initialRoute):
        DataManagementView(initialRoute: initialRoute)
    case .projectContacts(let focusedContactId):
        ProjectContactDatabaseView(focusedContactId: focusedContactId)
    case .materialPriceDatabase(let focusedEntryId):
        MaterialPriceDatabaseView(focusedEntryId: focusedEntryId)
    case .constructionMethodLibrary(let focusedMethodId):
        ConstructionMethodLibraryView(focusedMethodId: focusedMethodId)
    case .materialPriceSpikeDetails:
        MaterialPriceSpikeDetailView()
    }
}

struct TodayPrimaryQuickAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let destination: DashboardDestination
}

struct TodayMiniAction: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let title: String
    let systemImage: String
    let color: Color
    let destination: DashboardDestination
    var quickActions: [TodayPrimaryQuickAction] = []
    var onTrigger: (() -> Void)? = nil

    private var usesPadStyle: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var iconFont: Font {
        usesPadStyle ? .subheadline.weight(.semibold) : .caption.weight(.semibold)
    }

    private var titleFont: Font {
        usesPadStyle ? .subheadline.weight(.semibold) : .caption.weight(.semibold)
    }

    private var horizontalPadding: CGFloat {
        usesPadStyle ? AppSpacing.relaxed : AppSpacing.normal
    }

    private var verticalPadding: CGFloat {
        usesPadStyle ? 10 : 7
    }

    private var minHeight: CGFloat {
        usesPadStyle ? 44 : 0
    }

    var body: some View {
        NavigationLink {
            dashboardDestinationView(destination)
        } label: {
            HStack(spacing: AppSpacing.tight) {
                Image(systemName: systemImage)
                    .font(iconFont)
                    .foregroundStyle(color)
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                AppSurface(tone: .grouped, cornerRadius: AppSpacing.tight) {
                    Color.clear
                }
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            AppHaptics.impact(.light)
            onTrigger?()
        })
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(String(format: String(localized: "打开%@功能"), title))
        .contextMenu {
            ForEach(quickActions) { action in
                NavigationLink {
                    dashboardDestinationView(action.destination)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
        }
    }
}

struct TodayCommandAction: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    private var usesPadStyle: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var iconFont: Font {
        usesPadStyle ? .subheadline.weight(.semibold) : .caption.weight(.semibold)
    }

    private var titleFont: Font {
        usesPadStyle ? .subheadline.weight(.semibold) : .caption.weight(.semibold)
    }

    private var horizontalPadding: CGFloat {
        usesPadStyle ? AppSpacing.relaxed : AppSpacing.normal
    }

    private var verticalPadding: CGFloat {
        usesPadStyle ? 10 : 7
    }

    private var minHeight: CGFloat {
        usesPadStyle ? 44 : 0
    }

    var body: some View {
        Button {
            AppHaptics.impact(.light)
            action()
        } label: {
            HStack(spacing: AppSpacing.tight) {
                Image(systemName: systemImage)
                    .font(iconFont)
                    .foregroundStyle(color)
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background {
                AppSurface(tone: .grouped, cornerRadius: AppSpacing.tight) {
                    Color.clear
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct BookkeepingProjectPickerView: View {
    let projects: [Project]

    var body: some View {
        List {
            if projects.isEmpty {
                ContentUnavailableView(String(localized: "暂无进行中工程"), systemImage: "building.2")
            } else {
                Section(String(localized: "选择工程后直接进入项目记账")) {
                    ForEach(projects) { project in
                        NavigationLink {
                            ProjectDetailView(projectId: project.id, autoOpenFinancialAdd: true)
                        } label: {
                            VStack(alignment: .leading, spacing: AppSpacing.tight * 0.5) {
                                Text(project.name)
                                    .font(.body.weight(.semibold))
                                HStack(spacing: AppSpacing.tight) {
                                    Text(project.status.displayName)
                                    if !project.location.isEmpty {
                                        Text(project.location)
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "选择记账工程"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension DashboardView {
    func collectRecentActivities(limit: Int) -> [TimelineActivity] {
        var activities: [TimelineActivity] = []

        for log in projectStore.dailyLogs {
            let title = log.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "施工日志")
                : String(log.content.prefix(40))
            activities.append(
                TimelineActivity(
                    id: "log-\(log.id.uuidString)",
                    projectId: log.projectId,
                    type: .log,
                    title: title,
                    date: log.date,
                    subtitle: String(localized: "施工日志")
                )
            )
        }

        for task in projectStore.progressTasks {
            activities.append(
                TimelineActivity(
                    id: "progress-\(task.id.uuidString)",
                    projectId: task.projectId,
                    type: .progress,
                    title: task.title,
                    date: task.dueDate.isEmpty ? task.startDate : task.dueDate,
                    subtitle: DashboardSubtitleBuilder.progress(task.clampedCompletion * 100)
                )
            )
        }

        for todo in projectStore.siteTodos {
            activities.append(
                TimelineActivity(
                    id: "todo-\(todo.id.uuidString)",
                    projectId: todo.projectId,
                    type: .todo,
                    title: todo.title,
                    date: todo.completedAt ?? todo.dueDate,
                    subtitle: DashboardSubtitleBuilder.todoStatus(isDone: todo.isDone)
                )
            )
        }

        for item in financeStore.materialItems {
            activities.append(
                TimelineActivity(
                    id: "material-\(item.id.uuidString)",
                    projectId: item.projectId,
                    type: .material,
                    title: item.name,
                    date: item.arrivalDate,
                    subtitle: item.purchaseStatus.displayName
                )
            )
        }

        for item in financeStore.quoteItems {
            activities.append(
                TimelineActivity(
                    id: "quote-\(item.id.uuidString)",
                    projectId: item.projectId,
                    type: .quote,
                    title: item.name,
                    date: item.customerConfirmedDate,
                    subtitle: item.status.displayName
                )
            )
        }

        for item in financeStore.laborRecords {
            activities.append(
                TimelineActivity(
                    id: "labor-\(item.id.uuidString)",
                    projectId: item.projectId,
                    type: .labor,
                    title: item.workType.isEmpty ? String(localized: "人工记录") : item.workType,
                    date: item.date,
                    subtitle: DashboardSubtitleBuilder.labor(
                        workers: "\(item.workers)",
                        hours: "\(item.hours)"
                    )
                )
            )
        }

        for record in projectStore.projectFinancialRecords {
            activities.append(
                TimelineActivity(
                    id: "finance-\(record.id.uuidString)",
                    projectId: record.projectId,
                    type: .financial,
                    title: "\(record.normalizedDirection.displayName) \(ReportBuilder.money(ReportBuilder.number(record.amount)))",
                    date: record.date,
                    subtitle: record.normalizedCategory.displayName
                )
            )
        }

        for document in projectStore.projectDocuments {
            activities.append(
                TimelineActivity(
                    id: "document-\(document.id.uuidString)",
                    projectId: document.projectId,
                    type: .document,
                    title: document.title,
                    date: document.createdAt,
                    subtitle: DashboardSubtitleBuilder.document(
                        category: document.category.displayName,
                        pageCount: document.pageCount
                    )
                )
            )
        }

        for movement in projectStore.projectWarehouseMovements {
            activities.append(
                TimelineActivity(
                    id: "warehouse-\(movement.id.uuidString)",
                    projectId: movement.projectId,
                    type: .warehouse,
                    title: "\(movement.normalizedMovementType.displayName) \(movement.materialName)",
                    date: movement.date,
                    subtitle: "\(movement.quantity)\(movement.unit)"
                )
            )
        }

        for note in projectStore.quickNotes {
            activities.append(
                TimelineActivity(
                    id: "note-\(note.id.uuidString)",
                    projectId: note.projectId,
                    type: .note,
                    title: note.title.isEmpty ? String(localized: "随手记") : note.title,
                    date: note.createdAt,
                    subtitle: note.content
                )
            )
        }

        for drawing in projectStore.projectDrawings {
            activities.append(
                TimelineActivity(
                    id: "drawing-\(drawing.id.uuidString)",
                    projectId: drawing.projectId,
                    type: .drawing,
                    title: drawing.name,
                    date: drawing.importedAt,
                    subtitle: drawing.version
                )
            )
        }

        return activities
            .sorted { lhs, rhs in
                let lhsDate = parseDashboardDate(lhs.date) ?? .distantPast
                let rhsDate = parseDashboardDate(rhs.date) ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id > rhs.id
            }
            .prefix(limit)
            .map { $0 }
    }

    func projectName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return projectNameByID[id]
    }

    func dashboardDestination(for suggestion: RealtimeSearchSuggestion) -> DashboardDestination {
        switch suggestion.category {
        case .command:
            guard let command = RealtimeSearchCommand(suggestionId: suggestion.id) else {
                return .projectList()
            }
            return dashboardCommandDestination(for: command)
        case .project:
            return .projectDetail(projectId: suggestion.entityId)
        case .contact:
            return .projectContacts(focusedContactId: suggestion.entityId)
        case .material:
            return .materialPriceDatabase(focusedEntryId: suggestion.entityId)
        case .method:
            return .constructionMethodLibrary(focusedMethodId: suggestion.entityId)
        default:
            return .projectList()
        }
    }

    func dashboardCommandDestination(for command: RealtimeSearchCommand) -> DashboardDestination {
        switch command {
        case .newDailyLog:
            return .dailyLog(initialProjectId: currentProject?.id, autoOpenComposer: true)
        case .attachReceipt:
            if let project = currentProject {
                return .projectDetail(
                    projectId: project.id,
                    autoOpenDocumentScanSetup: true,
                    initialMode: .assets
                )
            }
            return .projectList(initialOverviewFilter: .missingReceipt)
        case .exportDeliveryPackage:
            if let project = currentProject {
                return .projectDetail(projectId: project.id, autoOpenDeliveryGuide: true)
            }
            return .dataManagement(initialRoute: .export)
        case .backupNow:
            return .dataManagement(initialRoute: .backup)
        case .dataHealthCheck:
            return .dataManagement(initialRoute: .health)
        }
    }

    func warehouseLinkedDocuments(for movement: ProjectWarehouseMovement) -> [ProjectDocument] {
        let documentIds = Set(movement.linkedDocumentIds)
        guard !documentIds.isEmpty else { return [] }
        return projectStore.projectDocuments.filter { documentIds.contains($0.id) }
    }

    func dashboardCollectedAmount(for projectId: UUID) -> Double {
        let financial = projectStore.projectFinancialRecords(for: projectId)
        let byFinancialRecords = ProjectFinancialMetrics.collectionAmount(financial)
        return byFinancialRecords > 0 ? byFinancialRecords : 0
    }

    func dashboardReceivableAgeDays(for project: Project, receivableAmount: Double) -> Int? {
        guard receivableAmount > 0 else { return nil }
        guard let endDate = Formatters.date.date(from: project.expectedEndDate) else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        let dueDate = Calendar.current.startOfDay(for: endDate)
        let days = Calendar.current.dateComponents([.day], from: dueDate, to: today).day ?? 0
        return max(days, 0)
    }

    func dashboardLatestCollection() -> CollectionSnapshot? {
        ProjectFinancialMetrics.latestCollection(
            records: activeFinancialRecords,
            projectName: { projectName($0) }
        )
    }

    func parseLocalDate(_ text: String) -> Date? {
        Self.localDateFormatter.date(from: text)
    }

    func parseDashboardDate(_ text: String) -> Date? {
        if let date = parseLocalDate(text) { return date }
        return Formatters.parseDateOrDateTime(text)
    }

    func todayString(for date: Date) -> String {
        Self.localDateFormatter.string(from: date)
    }
}
