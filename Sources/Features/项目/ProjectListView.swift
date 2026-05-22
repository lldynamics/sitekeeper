import Foundation
import SwiftUI

struct ProjectListView: View {
    @Environment(DataStore.self) var store
    @Environment(ProjectStore.self) var projectStore
    @Environment(FinanceStore.self) var financeStore
    @Environment(\.openURL) var openURL
    @State var searchText = ""
    @State var showAdd = false
    @State var newName = ""
    @State var newLocation = ""
    @State var newCustomerName = ""
    @State var newCustomerPhone = ""
    @State var newManagerName = ""
    @State var newStartDate = Date()
    @State var newExpectedEndDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State var newContractAmount = ""
    @State var newPaidAmount = ""
    @State var newMaterialCost = ""
    @State var newLaborCost = ""
    @State var newPaymentStatus: PaymentStatus = .unpaid
    @State var newRequiredDocumentCategories = Set(ProjectDocumentRecommendationStage.preConstruction.recommendedCategories)
    @State var projectToDelete: Project?
    @State var showDeleteConfirm = false
    @State var operationNotice: OperationToastNotice?
    @State var undoableDeletion = UndoableDeletionCoordinator()
    @State var statusFilter: ProjectStatus? = nil
    @State var overviewFilter: ProjectOverviewFilter? = nil
    @State var sortOption: ProjectSortOption = .recentUpdate
    @State var lastHandledAutoOpenComposerToken = 0
    @FocusState private var newProjectFocusedField: ProjectCreateNumericField?
    let autoOpenComposerToken: Int

    init(
        initialOverviewFilter: ProjectOverviewFilter? = nil,
        autoOpenComposerToken: Int = 0
    ) {
        _overviewFilter = State(initialValue: initialOverviewFilter)
        self.autoOpenComposerToken = autoOpenComposerToken
    }

    var allowedStatuses: [ProjectStatus] {
        ProjectStatus.allCases
    }

    var filtered: [Project] {
        var result = projectStore.projects
        result = SearchMatcher.filter(result, keyword: searchText)
        if let sf = statusFilter {
            result = result.filter { $0.status == sf }
        }
        if let overviewFilter {
            result = result.filter { project in
                switch overviewFilter {
                case .active:
                    return project.status.isActiveOrPaused
                case .overdue:
                    return hasOverdueItem(for: project)
                case .todo:
                    return openTodoCount(for: project) > 0
                case .missingReceipt:
                    return unattachedReceiptCount(for: project) > 0
                case .financialDue:
                    return hasUnsettledFinancial(for: project)
                case .missingTodayLog:
                    return missingTodayLog(for: project)
                case .priceSpike:
                    return materialPriceSpikeCount(for: project) > 0
                }
            }
        }
        return result
    }

    var sortedProjects: [Project] {
        filtered.sorted { lhs, rhs in
            switch sortOption {
            case .recentUpdate:
                return recentActivityDate(for: lhs) > recentActivityDate(for: rhs)
            case .expectedEnd:
                return expectedEndDate(for: lhs) < expectedEndDate(for: rhs)
            case .unpaidAmount:
                return unpaidAmount(for: lhs) > unpaidAmount(for: rhs)
            }
        }
    }

    var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasAnyFilterApplied: Bool {
        !normalizedSearchText.isEmpty || statusFilter != nil || overviewFilter != nil
    }

    var projectSearchSuggestions: [RealtimeSearchSuggestion] {
        RealtimeSearchSuggestionBuilder.suggestions(
            keyword: searchText,
            categories: [.project],
            projects: projectStore.projects,
            limit: 6
        )
    }

    var body: some View {
        compactProjectLayout
        .sheet(isPresented: $showAdd) {
            ProjectCreateSheet(
                name: $newName,
                location: $newLocation,
                customerName: $newCustomerName,
                customerPhone: $newCustomerPhone,
                managerName: $newManagerName,
                startDate: $newStartDate,
                expectedEndDate: $newExpectedEndDate,
                contractAmount: $newContractAmount,
                paidAmount: $newPaidAmount,
                materialCost: $newMaterialCost,
                laborCost: $newLaborCost,
                paymentStatus: $newPaymentStatus,
                requiredDocumentCategories: $newRequiredDocumentCategories,
                focusedField: $newProjectFocusedField,
                canCreate: canCreateProject,
                onCancel: {
                    clearProject()
                    showAdd = false
                },
                onCreate: {
                    addProject()
                    showAdd = false
                }
            )
        }
        .confirmationDialog(String(localized: "删除项目"), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(String(localized: "归档项目，保留全部数据")) { archiveProject() }
            Button(String(localized: "删除项目及全部关联数据"), role: .destructive) { deleteProject(keepData: false) }
            Button(String(localized: "取消"), role: .cancel) {}
        } message: {
            Text(
                String(
                    format: String(localized: "project_delete_dialog_message"),
                    projectToDelete?.name ?? "",
                    relatedCount
                )
            )
        }
        .onAppear {
            handleAutoOpenComposer()
        }
        .onChange(of: autoOpenComposerToken) { _, _ in
            handleAutoOpenComposer()
        }
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
        .operationToast(notice: $operationNotice)
    }

    var compactProjectLayout: some View {
        projectList
            .navigationTitle(String(localized: "项目"))
            .toolbar {
                projectToolbar
            }
    }

    @ToolbarContentBuilder
    var projectToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationLink {
                ProjectFileBrowserView()
            } label: {
                Image(systemName: "folder").visibleIconStyle()
            }
            .buttonStyle(.appIcon())
            .accessibilityLabel(String(localized: "项目资料"))
            .accessibilityIdentifier("project-file-browser-entry")
            if shouldUseProminentProjectCreateAction {
                Button {
                    showAdd = true
                } label: {
                    Label(String(localized: "新建项目"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.appProminent())
                .accessibilityLabel(String(localized: "新建项目"))
            } else {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus").visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel(String(localized: "新建项目"))
            }
        }
    }

    var shouldUseProminentProjectCreateAction: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || projectStore.projects.isEmpty
    }

    @ViewBuilder
    var projectList: some View {
        List {
            searchFilterSection

            if sortedProjects.isEmpty {
                emptyProjectSection
            }

            projectRowsSection
        }
    }

    // MARK: - 内联搜索与筛选

    @ViewBuilder
    var searchFilterSection: some View {
        ProjectListFiltersSection(
            searchText: $searchText,
            statusFilter: $statusFilter,
            sortOption: $sortOption,
            overviewFilter: $overviewFilter,
            allowedStatuses: allowedStatuses,
            searchSuggestions: projectSearchSuggestions,
            hasAnyFilterApplied: hasAnyFilterApplied,
            onSelectSuggestion: applyProjectSuggestion,
            onClearAll: clearAllFilters
        )
    }

    // MARK: - 空状态

    @ViewBuilder
    var emptyProjectSection: some View {
        Section(String(localized: "建议下一步")) {
            if hasAnyFilterApplied {
                ContentUnavailableView(
                    String(localized: "没有匹配项目"),
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(String(localized: "当前筛选条件下没有匹配项，建议先清除筛选再查看全部工程。"))
                )
                Button {
                    clearAllFilters()
                } label: {
                    Label(String(localized: "清除筛选条件"), systemImage: "arrow.uturn.backward.circle")
                }
            } else {
                ContentUnavailableView(
                    String(localized: "还没有项目"),
                    systemImage: "building.2",
                    description: Text(String(localized: "先新建一个工程，再补充日志、资料、报价和回款。"))
                )
                Button {
                    showAdd = true
                } label: {
                    Label(String(localized: "新建第一个项目"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.appProminent())
            }
        }
    }
}
