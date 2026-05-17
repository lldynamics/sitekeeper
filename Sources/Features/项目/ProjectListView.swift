import Foundation
import SwiftUI

struct ProjectListView: View {
    @Environment(DataStore.self) private var store
    @Environment(ProjectStore.self) private var projectStore
    @Environment(FinanceStore.self) private var financeStore
    @Environment(\.openURL) private var openURL
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newLocation = ""
    @State private var newCustomerName = ""
    @State private var newCustomerPhone = ""
    @State private var newManagerName = ""
    @State private var newStartDate = Date()
    @State private var newExpectedEndDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var newContractAmount = ""
    @State private var newPaidAmount = ""
    @State private var newMaterialCost = ""
    @State private var newLaborCost = ""
    @State private var newPaymentStatus: PaymentStatus = .unpaid
    @State private var newRequiredDocumentCategories = Set(ProjectDocumentRecommendationStage.preConstruction.recommendedCategories)
    @State private var projectToDelete: Project?
    @State private var showDeleteConfirm = false
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()
    @State private var statusFilter: ProjectStatus? = nil
    @State private var overviewFilter: ProjectOverviewFilter? = nil
    @State private var sortOption: ProjectSortOption = .recentUpdate
    @State private var selectedProjectId: UUID?
    @State private var lastHandledAutoOpenComposerToken = 0
    @FocusState private var newProjectFocusedField: ProjectCreateNumericField?
    private let autoOpenComposerToken: Int
    private let prefersSplitNavigation: Bool?

    init(
        initialOverviewFilter: ProjectOverviewFilter? = nil,
        autoOpenComposerToken: Int = 0,
        prefersSplitNavigation: Bool? = nil
    ) {
        _overviewFilter = State(initialValue: initialOverviewFilter)
        self.autoOpenComposerToken = autoOpenComposerToken
        self.prefersSplitNavigation = prefersSplitNavigation
    }

    private var allowedStatuses: [ProjectStatus] {
        ProjectStatus.allCases
    }

    private var filtered: [Project] {
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

    private var sortedProjects: [Project] {
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

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasAnyFilterApplied: Bool {
        !normalizedSearchText.isEmpty || statusFilter != nil || overviewFilter != nil
    }

    private var projectSearchSuggestions: [RealtimeSearchSuggestion] {
        RealtimeSearchSuggestionBuilder.suggestions(
            keyword: searchText,
            categories: [.project],
            projects: projectStore.projects,
            limit: 6
        )
    }

    private var shouldUseSplitNavigation: Bool {
        if let prefersSplitNavigation {
            return prefersSplitNavigation
        }
        return false
    }

    private var visibleProjectIDs: [UUID] {
        sortedProjects.map(\.id)
    }

    private var selectedProject: Project? {
        guard let selectedProjectId else { return nil }
        return projectStore.projects.first { $0.id == selectedProjectId }
    }

    var body: some View {
        Group {
            if shouldUseSplitNavigation {
                splitProjectLayout
            } else {
                compactProjectLayout
            }
        }
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
            syncSelectedProjectIfNeeded()
        }
        .onChange(of: autoOpenComposerToken) { _, _ in
            handleAutoOpenComposer()
        }
        .onChange(of: visibleProjectIDs) { _, _ in
            syncSelectedProjectIfNeeded()
        }
        .onChange(of: shouldUseSplitNavigation) { _, _ in
            syncSelectedProjectIfNeeded()
        }
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
        .operationToast(notice: $operationNotice)
    }

    private var compactProjectLayout: some View {
        projectList(isSplitNavigation: false)
            .navigationTitle(String(localized: "项目"))
            .toolbar {
                projectToolbar
            }
    }

    private var splitProjectLayout: some View {
        NavigationSplitView {
            projectList(isSplitNavigation: true)
                .navigationTitle(String(localized: "项目"))
                .toolbar {
                    projectToolbar
                }
        } detail: {
            if let selectedProject {
                ProjectDetailView(projectId: selectedProject.id)
            } else {
                ContentUnavailableView(
                    String(localized: "请选择项目"),
                    systemImage: "building.2.crop.circle",
                    description: Text(String(localized: "在左侧选择工程后，右侧常驻展示项目详情。"))
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ToolbarContentBuilder
    private var projectToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationLink {
                ProjectFileBrowserView()
            } label: {
                Image(systemName: "folder").visibleIconStyle()
            }
            .buttonStyle(.appIcon())
            .accessibilityLabel(String(localized: "项目资料"))
            .accessibilityIdentifier("project-file-browser-entry")
            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus").visibleIconStyle()
            }
            .buttonStyle(.appIcon())
            .accessibilityLabel(String(localized: "新建项目"))
        }
    }

    @ViewBuilder
    private func projectList(isSplitNavigation: Bool) -> some View {
        List {
            searchFilterSection(isSplitNavigation: isSplitNavigation)

            if sortedProjects.isEmpty {
                emptyProjectSection
            }

            projectRowsSection(isSplitNavigation: isSplitNavigation)
        }
    }

    // MARK: - 内联搜索与筛选

    @ViewBuilder
    private func searchFilterSection(isSplitNavigation: Bool) -> some View {
        ProjectListFiltersSection(
            searchText: $searchText,
            statusFilter: $statusFilter,
            sortOption: $sortOption,
            overviewFilter: $overviewFilter,
            allowedStatuses: allowedStatuses,
            searchSuggestions: projectSearchSuggestions,
            hasAnyFilterApplied: hasAnyFilterApplied,
            isSplitNavigation: isSplitNavigation,
            onSelectSuggestion: applyProjectSuggestion,
            onClearAll: clearAllFilters
        )
    }

    // MARK: - 空状态

    @ViewBuilder
    private var emptyProjectSection: some View {
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

    // MARK: - 项目列表行

    @ViewBuilder
    private func projectRowsSection(isSplitNavigation: Bool) -> some View {
        ForEach(sortedProjects) { project in
            Group {
                if isSplitNavigation {
                    Button {
                        selectedProjectId = project.id
                    } label: {
                        ProjectRowContent(
                            project: project,
                            isSelected: selectedProjectId == project.id,
                            unpaidAmount: unpaidAmount(for: project),
                            badges: projectRiskBadges(for: project)
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedProjectId == project.id ? Color.appPeachSurfaceSubtle : Color.clear)
                } else {
                    NavigationLink {
                        ProjectDetailView(projectId: project.id)
                    } label: {
                        ProjectRowContent(
                            project: project,
                            isSelected: false,
                            unpaidAmount: unpaidAmount(for: project),
                            badges: projectRiskBadges(for: project)
                        )
                    }
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                NavigationLink {
                    ProjectDetailView(projectId: project.id, initialMode: .finance)
                } label: {
                    Label(String(localized: "财务"), systemImage: "wallet.pass.fill")
                }
                .tint(Color.appFinance)

                NavigationLink {
                    SiteTodoView(initialProjectId: project.id)
                } label: {
                    Label(String(localized: "待办"), systemImage: "checkmark.circle.fill")
                }
                .tint(Color.appSuccess)

                NavigationLink {
                    ProjectDetailView(projectId: project.id, initialMode: .assets)
                } label: {
                    Label(String(localized: "图纸"), systemImage: "square.on.square.squareshape.controlhandles")
                }
                .tint(Color.appPrimaryAction)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                NavigationLink {
                    ProjectDetailView(projectId: project.id, autoOpenDocumentScanSetup: true)
                } label: {
                    Label(String(localized: "加资料"), systemImage: "doc.badge.plus")
                }
                .tint(Color.appDoc)

                NavigationLink {
                    DailyLogView(initialProjectId: project.id, autoOpenComposer: true)
                } label: {
                    Label(String(localized: "写日志"), systemImage: "book.pages.fill")
                }
                .tint(Color.appSuccess)

                NavigationLink {
                    ProjectDetailView(projectId: project.id, autoOpenFinancialAdd: true)
                } label: {
                    Label(String(localized: "记账"), systemImage: "receipt.fill")
                }
                .tint(Color.appFinance)

                if let url = customerPhoneURL(for: project) {
                    Button {
                        openURL(url)
                    } label: {
                        Label(String(localized: "联系客户"), systemImage: "phone.fill")
                    }
                    .tint(Color.appDoc)
                }
            }
        }
        .onDelete { indexSet in
            let ids = indexSet.map { sortedProjects[$0].id }
            if let target = projectStore.projects.first(where: { ids.contains($0.id) }) {
                projectToDelete = target
                showDeleteConfirm = true
            }
        }
    }

    private func syncSelectedProjectIfNeeded() {
        guard shouldUseSplitNavigation else { return }
        guard !visibleProjectIDs.isEmpty else {
            selectedProjectId = nil
            return
        }
        if let selectedProjectId, visibleProjectIDs.contains(selectedProjectId) {
            return
        }
        selectedProjectId = visibleProjectIDs.first
    }

    private func clearAllFilters() {
        searchText = ""
        statusFilter = nil
        overviewFilter = nil
    }

    private func handleAutoOpenComposer() {
        guard autoOpenComposerToken > 0,
              autoOpenComposerToken != lastHandledAutoOpenComposerToken else { return }
        lastHandledAutoOpenComposerToken = autoOpenComposerToken
        showAdd = true
    }

    private func deleteProject(keepData: Bool) {
        guard let pid = projectToDelete?.id else { return }
        if keepData {
            archiveProject()
            return
        } else {
            let projectName = projectToDelete?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let normalizedName = projectName.isEmpty ? String(localized: "项目") : projectName
            let relationCount = relatedCount
            let deletion = store.removeProjectCascade(pid)
            guard !deletion.isEmpty else {
                projectToDelete = nil
                return
            }

            projectToDelete = nil
            syncSelectedProjectIfNeeded()
            undoableDeletion.queue(
                notice: $operationNotice,
                message: String(format: String(localized: "已删除项目 %@"), normalizedName),
                commit: {
                    deletion.performDeferredFileCleanup()
                    store.scheduleSave()
                },
                undo: {
                    store.restoreProjectCascade(deletion)
                    if shouldUseSplitNavigation {
                        selectedProjectId = pid
                    }
                    store.scheduleSave()
                },
                audit: UndoableDeletionAuditContext(
                    summary: String(localized: "删除项目及全部关联数据"),
                    detail: [
                        "\(normalizedName)",
                        "related=\(relationCount)",
                        "records=\(deletion.deletedRecordCount)",
                        "files=\(deletion.deferredFileCleanup?.fileCount ?? 0)"
                    ].joined(separator: " · "),
                    source: "ProjectListView"
                )
            )
        }
    }

    private func archiveProject() {
        guard let pid = projectToDelete?.id,
              let index = projectStore.projects.firstIndex(where: { $0.id == pid }) else { return }
        var project = projectStore.projects[index]
        project.status = .archived
        guard store.updateProject(project) else { return }
        projectToDelete = nil
        store.scheduleSave()
    }

    private func addProject() {
        guard canCreateProject else { return }
        store.appendProject(Project(
            name: newName.trimmingCharacters(in: .whitespacesAndNewlines),
            location: newLocation,
            status: .active,
            customerName: newCustomerName,
            customerPhone: newCustomerPhone,
            startDate: Formatters.date.string(from: newStartDate),
            expectedEndDate: Formatters.date.string(from: newExpectedEndDate),
            managerName: newManagerName,
            contractAmount: NumericInputSupport.normalizedStorageText(newContractAmount, kind: .amount),
            paidAmount: NumericInputSupport.normalizedStorageText(newPaidAmount, kind: .amount),
            paymentStatus: newPaymentStatus,
            materialCost: NumericInputSupport.normalizedStorageText(newMaterialCost, kind: .amount),
            laborCost: NumericInputSupport.normalizedStorageText(newLaborCost, kind: .amount),
            requiredDocumentCategories: ProjectDocumentCategory.normalizedConstructionArchiveRequirements(
                Array(newRequiredDocumentCategories)
            )
        ))
        store.scheduleSave()
        clearProject()
    }
    private func clearProject() {
        newName = ""
        newLocation = ""
        newCustomerName = ""
        newCustomerPhone = ""
        newManagerName = ""
        newContractAmount = ""
        newPaidAmount = ""
        newMaterialCost = ""
        newLaborCost = ""
        newPaymentStatus = .unpaid
        newRequiredDocumentCategories = Set(ProjectDocumentRecommendationStage.preConstruction.recommendedCategories)
        newStartDate = Date()
        newExpectedEndDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    }

    private var canCreateProject: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !newRequiredDocumentCategories.isEmpty &&
        InputValidator.validate(newContractAmount, kind: .amount, requirement: .optionalNonNegative).isValid &&
        InputValidator.validate(newPaidAmount, kind: .amount, requirement: .optionalNonNegative).isValid &&
        InputValidator.validate(newMaterialCost, kind: .amount, requirement: .optionalNonNegative).isValid &&
        InputValidator.validate(newLaborCost, kind: .amount, requirement: .optionalNonNegative).isValid
    }

    private var relatedCount: Int {
        guard let pid = projectToDelete?.id else { return 0 }
        return store.relatedDataCount(for: pid)
    }

    private func expectedEndDate(for project: Project) -> Date {
        Formatters.date.date(from: project.expectedEndDate) ?? .distantFuture
    }

    private func paidAmount(for project: Project) -> Double {
        let projectId = project.id
        let summary = projectStore.projectActivitySummary(for: projectId)
        if summary.collectedIncomeAmount > 0 {
            return summary.collectedIncomeAmount
        }
        return project.paidAmountValue.doubleValue
    }

    private func customerPhoneURL(for project: Project) -> URL? {
        let raw = project.customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let normalized = raw.replacingOccurrences(of: " ", with: "")
        return URL(string: "tel:\(normalized)")
    }

    private func unpaidAmount(for project: Project) -> Double {
        max(project.contractAmountValue.doubleValue - paidAmount(for: project), 0)
    }

    private func projectRiskBadges(for project: Project) -> [ProjectRiskBadge] {
        var badges: [ProjectRiskBadge] = []
        if hasOverdueItem(for: project) {
            badges.append(ProjectRiskBadge(title: String(localized: "延期"), systemImage: "exclamationmark.triangle.fill", color: .appRisk))
        }
        let todos = openTodoCount(for: project)
        if todos > 0 {
            badges.append(ProjectRiskBadge(
                title: String(format: String(localized: "%d待办"), todos),
                systemImage: "checklist",
                color: .appWarning
            ))
        }
        let missingReceipts = unattachedReceiptCount(for: project)
        if missingReceipts > 0 {
            badges.append(ProjectRiskBadge(
                title: String(format: String(localized: "%d缺票"), missingReceipts),
                systemImage: "doc.badge.exclamationmark",
                color: .appFinance
            ))
        }
        let priceSpikes = materialPriceSpikeCount(for: project)
        if priceSpikes > 0 {
            badges.append(ProjectRiskBadge(
                title: String(format: String(localized: "%d价格异动"), priceSpikes),
                systemImage: "arrow.up.right.circle.fill",
                color: .appFinance
            ))
        }
        if unpaidAmount(for: project) > 0 {
            badges.append(ProjectRiskBadge(title: String(localized: "未收"), systemImage: "yensign.circle.fill", color: .appDoc))
        }
        return Array(badges.prefix(4))
    }

    private func applyProjectSuggestion(_ suggestion: RealtimeSearchSuggestion) {
        guard suggestion.category == .project else { return }
        if let project = projectStore.projects.first(where: { $0.id == suggestion.entityId }) {
            searchText = project.name
            selectedProjectId = project.id
        } else {
            searchText = suggestion.title
        }
    }

    private func hasOverdueItem(for project: Project) -> Bool {
        projectStore.projectActivitySummary(for: project.id).overdueItemCount > 0
    }

    private func openTodoCount(for project: Project) -> Int {
        projectStore.projectActivitySummary(for: project.id).openTodoCount
    }

    private func unattachedReceiptCount(for project: Project) -> Int {
        projectStore.projectActivitySummary(for: project.id).unattachedReceiptCount
    }

    private func hasUnsettledFinancial(for project: Project) -> Bool {
        projectStore.projectActivitySummary(for: project.id).hasUnsettledFinancial
    }

    private func materialPriceSpikeCount(for project: Project) -> Int {
        financeStore.materialPriceSpikeCount(for: project.id)
    }

    private func missingTodayLog(for project: Project) -> Bool {
        guard project.status.isActiveOrPaused else {
            return false
        }
        return !projectStore.hasTodayLog(for: project.id)
    }

    private func recentActivityDate(for project: Project) -> Date {
        let projectId = project.id
        var latest = projectStore.projectActivitySummary(for: projectId).latestActivityDate ?? .distantPast
        if let startDate = Formatters.parseDateOrDateTime(project.startDate) {
            latest = max(latest, startDate)
        }
        if let latestLabor = financeStore.latestLaborDate(for: projectId) {
            latest = max(latest, latestLabor)
        }
        return latest
    }
}
