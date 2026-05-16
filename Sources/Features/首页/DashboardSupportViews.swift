import SwiftUI

enum DashboardDestination {
    case dailyLog(initialProjectId: UUID? = nil, autoOpenComposer: Bool = false, focusedLogId: UUID? = nil)
    case siteTodo(initialProjectId: UUID? = nil, autoOpenComposer: Bool = false, focusedTodoId: UUID? = nil)
    case watermarkCamera(initialProjectId: UUID? = nil, autoOpenCameraOnAppear: Bool = false)
    case projectDetail(
        projectId: UUID,
        autoOpenFinancialAdd: Bool = false,
        autoOpenDocumentScanSetup: Bool = false,
        initialMode: ProjectDetailMode? = nil
    )
    case bookkeepingProjectPicker(projects: [Project])
    case projectList(initialOverviewFilter: ProjectOverviewFilter? = nil)
    case warehouseOverview
    case warehouse(project: Project)
    case dataManagement(initialTab: String? = nil)
    case projectContacts(focusedContactId: UUID? = nil)
    case materialPriceDatabase(focusedEntryId: UUID? = nil)
    case constructionMethodLibrary(focusedMethodId: UUID? = nil)
    case materialPriceSpikeDetails
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
    case .projectDetail(let projectId, let autoOpenFinancialAdd, let autoOpenDocumentScanSetup, let initialMode):
        ProjectDetailView(
            projectId: projectId,
            initialMode: initialMode,
            autoOpenFinancialAdd: autoOpenFinancialAdd,
            autoOpenDocumentScanSetup: autoOpenDocumentScanSetup
        )
    case .bookkeepingProjectPicker(let projects):
        BookkeepingProjectPickerView(projects: projects)
    case .projectList(let initialOverviewFilter):
        ProjectListView(initialOverviewFilter: initialOverviewFilter)
    case .warehouseOverview:
        ProjectWarehouseOverviewView()
    case .warehouse(let project):
        ProjectWarehouseView(project: project)
    case .dataManagement(let initialTab):
        DataManagementView(initialTab: initialTab)
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
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.tight)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
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
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.tight)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
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
