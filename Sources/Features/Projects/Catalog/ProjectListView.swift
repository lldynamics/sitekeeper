import Foundation
import SwiftUI

struct ProjectListView: View {
    @Environment(DataStore.self) var store
    @Environment(ProjectStore.self) var projectStore
    @Environment(FinanceStore.self) var financeStore
    @Environment(\.openURL) var openURL
    @Binding var selectedProjectID: UUID?
    let usesProjectSelection: Bool
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
    let autoOpenComposerToken: Int
    let onAutoOpenComposerConsumed: (Int) -> Void

    init(
        initialOverviewFilter: ProjectOverviewFilter? = nil,
        selection: Binding<UUID?>? = nil,
        autoOpenComposerToken: Int = 0,
        onAutoOpenComposerConsumed: @escaping (Int) -> Void = { _ in }
    ) {
        _selectedProjectID = selection ?? .constant(nil)
        usesProjectSelection = selection != nil
        _overviewFilter = State(initialValue: initialOverviewFilter)
        self.autoOpenComposerToken = autoOpenComposerToken
        self.onAutoOpenComposerConsumed = onAutoOpenComposerConsumed
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
                case .receivableAging:
                    return project.status.isActiveOrPaused && hasReceivableAging(for: project)
                case .recentCollection:
                    return hasRecentCollection(for: project)
                case .costAnomaly:
                    return hasCostAnomaly(for: project)
                case .lowMarginRisk:
                    return hasLowMarginRisk(for: project)
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
                canCreate: canCreateProject,
                onCancel: {
                    clearProject()
                    showAdd = false
                },
                onCreate: completeProjectCreation
            )
        }
        .confirmationDialog(AppLocalization.string("删除项目"), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(AppLocalization.string("归档项目，保留全部数据")) { archiveProject() }
            Button(AppLocalization.string("删除项目及全部关联数据"), role: .destructive) { deleteProject(keepData: false) }
            Button(AppLocalization.string("取消"), role: .cancel) {}
        } message: {
            Text(
                String(
                    format: AppLocalization.string("project_delete_dialog_message"),
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
            .navigationTitle(AppLocalization.string("项目"))
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
            .accessibilityLabel(AppLocalization.string("项目资料"))
            .accessibilityIdentifier("project-file-browser-entry")
            if shouldUseProminentProjectCreateAction {
                Button {
                    showAdd = true
                } label: {
                    Label(AppLocalization.string("新建项目"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.appProminent())
                .accessibilityLabel(AppLocalization.string("新建项目"))
                .accessibilityIdentifier("project-create-open")
            } else {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus").visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel(AppLocalization.string("新建项目"))
                .accessibilityIdentifier("project-create-open")
            }
        }
    }

    @ViewBuilder
    var projectList: some View {
        List(selection: $selectedProjectID) {
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
        Section(AppLocalization.string("建议下一步")) {
            if hasAnyFilterApplied {
                ContentUnavailableView(
                    AppLocalization.string("没有匹配项目"),
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(AppLocalization.string("当前筛选条件下没有匹配项，建议先清除筛选再查看全部工程。"))
                )
                Button {
                    clearAllFilters()
                } label: {
                    Label(AppLocalization.string("清除筛选条件"), systemImage: "arrow.uturn.backward.circle")
                }
            } else {
                ContentUnavailableView(
                    AppLocalization.string("还没有项目"),
                    systemImage: "building.2",
                    description: Text(AppLocalization.string("先新建一个工程，再补充日志、资料、报价和回款。"))
                )
                Button {
                    showAdd = true
                } label: {
                    Label(AppLocalization.string("新建第一个项目"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.appProminent())
            }
        }
    }
}
