import SwiftUI

enum DashboardDestination {
    case dailyLog(initialProjectId: UUID? = nil, autoOpenComposer: Bool = false, focusedLogId: UUID? = nil)
    case siteTodo(initialProjectId: UUID? = nil, autoOpenComposer: Bool = false, focusedTodoId: UUID? = nil)
    case quickNote(focusedNoteId: UUID? = nil)
    case watermarkCamera(initialProjectId: UUID? = nil, autoOpenCameraOnAppear: Bool = false)
    case projectDetail(
        projectId: UUID,
        autoOpenFinancialAdd: Bool = false,
        autoOpenDocumentScanSetup: Bool = false,
        autoOpenDeliveryGuide: Bool = false,
        initialMode: ProjectDetailMode? = nil,
        focus: ProjectDetailFocus? = nil
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
    case quotation(focusedQuoteID: UUID)
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

@MainActor @ViewBuilder
func dashboardDestinationView(_ destination: DashboardDestination) -> some View {
    LazyDashboardDestinationView(destination: destination)
}

struct LazyDashboardDestinationView: View {
    let destination: DashboardDestination

    @ViewBuilder
    var body: some View {
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
        case .quickNote(let focusedNoteId):
            QuickNoteView(focusedNoteId: focusedNoteId, embedsNavigationStack: false)
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
            let initialMode,
            let focus
        ):
            ProjectDetailView(
                projectId: projectId,
                initialMode: initialMode,
                focus: focus,
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
        case .quotation(let id):
            QuotationView(focusedQuoteId: id)
        }
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
        horizontalSizeClass == .regular
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

    var body: some View {
        NavigationLink {
            LazyDashboardDestinationView(destination: destination)
        } label: {
            HStack(spacing: AppSpacing.tight) {
                Image(systemName: systemImage)
                    .font(iconFont)
                    .foregroundStyle(color)
                    .fixedSize()
                Text(title)
                    .font(titleFont)
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .contentShape(Rectangle())
            .background {
                AppSurface(
                    tone: .tertiary,
                    cornerRadius: 12,
                    stroke: Color(uiColor: .separator).opacity(0.12)
                ) {
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
        .accessibilityHint(String(format: AppLocalization.string("打开%@功能"), title))
        .contextMenu {
            ForEach(quickActions) { action in
                NavigationLink {
                    LazyDashboardDestinationView(destination: action.destination)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
        }
    }
}

struct BookkeepingProjectPickerView: View {
    let projects: [Project]

    var body: some View {
        List {
            if projects.isEmpty {
                AppActionableEmptyState(
                    title: AppLocalization.string("暂无进行中工程"),
                    systemImage: "building.2",
                    message: AppLocalization.string("先创建或启用一个工程，再记录收支。")
                ) {
                    NavigationLink {
                        ProjectListView()
                    } label: {
                        Label(AppLocalization.string("前往工程管理"), systemImage: "arrow.right.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("bookkeeping-empty-open-projects")
                }
            } else {
                Section(AppLocalization.string("选择工程后直接进入项目记账")) {
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
        .navigationTitle(AppLocalization.string("选择记账工程"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
