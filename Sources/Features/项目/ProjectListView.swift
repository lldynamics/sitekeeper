import Foundation
import SwiftUI

struct ProjectListView: View {
    private enum NewProjectNumericField: Hashable {
        case contractAmount
        case paidAmount
        case materialCost
        case laborCost
    }

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
    @State private var projectToDelete: Project?
    @State private var showDeleteConfirm = false
    @State private var statusFilter: ProjectStatus? = nil
    @State private var overviewFilter: ProjectOverviewFilter? = nil
    @State private var sortOption: ProjectSortOption = .recentUpdate
    @State private var selectedProjectId: UUID?
    @State private var lastHandledAutoOpenComposerToken = 0
    @FocusState private var newProjectFocusedField: NewProjectNumericField?
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
                    return project.status == .active || project.status == .paused
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

    private var activeProjectCount: Int {
        projectStore.activeOrPausedProjectCount
    }

    private var overdueCount: Int { projectStore.totalOverdueItemCount }

    private var openTodoCount: Int { projectStore.totalOpenTodoCount }

    private var unattachedReceiptCount: Int {
        projectStore.totalUnattachedReceiptCount
    }

    private var unsettledFinancialCount: Int {
        projectStore.totalUnsettledFinancialCount
    }

    private var missingTodayLogCount: Int {
        projectStore.missingTodayLogActiveProjectCount
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasAnyFilterApplied: Bool {
        !normalizedSearchText.isEmpty || statusFilter != nil || overviewFilter != nil
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
            addProjectForm
        }
        .confirmationDialog("删除项目", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("归档项目，保留全部数据") { archiveProject() }
            Button("删除项目及全部关联数据", role: .destructive) { deleteProject(keepData: false) }
            Button("取消", role: .cancel) {}
        } message: {
            Text(String(localized: "项目「\(projectToDelete?.name ?? "")」有 \(relatedCount) 条关联数据。归档会保留全部联系人、财务、资料、图纸和记录；删除会清除项目及全部关联数据。"))
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
    }

    private var compactProjectLayout: some View {
        projectList(isSplitNavigation: false)
            .navigationTitle("项目")
            .toolbar {
                projectToolbar
            }
    }

    private var splitProjectLayout: some View {
        NavigationSplitView {
            projectList(isSplitNavigation: true)
                .navigationTitle("项目")
                .toolbar {
                    projectToolbar
                }
        } detail: {
            if let selectedProject {
                ProjectDetailView(projectId: selectedProject.id)
            } else {
                ContentUnavailableView(
                    "请选择项目",
                    systemImage: "building.2.crop.circle",
                    description: Text("在左侧选择工程后，右侧常驻展示项目详情。")
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
                Image(systemName: "folder")
            }
            .accessibilityLabel("项目文件浏览")
            Button {
                showAdd = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("新建项目")
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
        Section {
            // 搜索栏
            HStack(spacing: AppSpacing.tight) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("搜索项目名称或地点", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // 状态筛选 chips + 排序 + 清除
            if isSplitNavigation {
                HStack(spacing: AppSpacing.tight) {
                    Menu {
                        Button("全部状态") { statusFilter = nil }
                        ForEach(ProjectStatus.allCases, id: \.rawValue) { status in
                            Button(status.displayName) {
                                statusFilter = status
                            }
                        }
                    } label: {
                        Label(statusFilter?.displayName ?? "全部状态", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, AppSpacing.normal)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                    }

                    Menu {
                        ForEach(ProjectSortOption.allCases, id: \.self) { option in
                            Button(option.displayName) {
                                sortOption = option
                            }
                        }
                    } label: {
                        Label(sortOption.displayName, systemImage: "arrow.up.arrow.down.circle")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, AppSpacing.normal)
                            .padding(.vertical, 6)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                    }

                    Spacer(minLength: 0)

                    if hasAnyFilterApplied {
                        Button {
                            clearAllFilters()
                        } label: {
                            Label("清除", systemImage: "xmark.circle")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: AppSpacing.tight) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.tight) {
                            FilterChip(title: "全部", isSelected: statusFilter == nil) { statusFilter = nil }
                            ForEach(ProjectStatus.allCases, id: \.rawValue) { s in
                                FilterChip(title: s.rawValue, isSelected: statusFilter == s) { statusFilter = s }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    HStack(spacing: AppSpacing.tight) {
                        Picker("排序", selection: $sortOption) {
                            ForEach(ProjectSortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)

                        Spacer(minLength: 0)

                        if hasAnyFilterApplied {
                            Button("清除筛选") {
                                clearAllFilters()
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        }
                    }
                }
            }

            if overviewFilter != nil {
                Button {
                    overviewFilter = nil
                } label: {
                    Label("清除概况筛选", systemImage: "xmark.circle")
                        .font(.caption.weight(.semibold))
                }
            }
        } header: {
            Text("搜索与筛选")
        }
    }

    // MARK: - 空状态

    @ViewBuilder
    private var emptyProjectSection: some View {
        Section("建议下一步") {
            if hasAnyFilterApplied {
                ContentUnavailableView(
                    "没有匹配项目",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("当前筛选条件下没有匹配项，建议先清除筛选再查看全部工程。")
                )
                Button {
                    clearAllFilters()
                } label: {
                    Label("清除筛选条件", systemImage: "arrow.uturn.backward.circle")
                }
            } else {
                ContentUnavailableView(
                    "还没有项目",
                    systemImage: "building.2",
                    description: Text("先新建一个工程，再补充日志、资料、报价和回款。")
                )
                Button {
                    showAdd = true
                } label: {
                    Label("新建第一个项目", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
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
                    .listRowBackground(selectedProjectId == project.id ? Color.orange.opacity(0.14) : Color.clear)
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
                    ProjectDetailView(projectId: project.id, autoOpenFinancialAdd: true)
                } label: {
                    Label("记账", systemImage: "receipt.fill")
                }
                .tint(.pink)

                NavigationLink {
                    DailyLogView(initialProjectId: project.id, autoOpenComposer: true)
                } label: {
                    Label("写日志", systemImage: "book.pages.fill")
                }
                .tint(.green)

                NavigationLink {
                    ProjectDetailView(projectId: project.id, autoOpenDocumentScanSetup: true)
                } label: {
                    Label("加资料", systemImage: "doc.badge.plus")
                }
                .tint(.indigo)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let url = customerPhoneURL(for: project) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("联系客户", systemImage: "phone.fill")
                    }
                    .tint(.blue)
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

    private var addProjectForm: some View {
        NavigationStack {
            Form {
                Section("工程信息") {
                    TextField("工程名称", text: $newName)
                    TextField("项目地址", text: $newLocation, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("负责人", text: $newManagerName)
                }
                Section("客户") {
                    TextField("客户姓名/单位", text: $newCustomerName)
                    TextField("客户电话", text: $newCustomerPhone)
                        .keyboardType(.phonePad)
                }
                Section("工期") {
                    DatePicker("开工日期", selection: $newStartDate, displayedComponents: .date)
                    DatePicker("预计完工", selection: $newExpectedEndDate, displayedComponents: .date)
                }
                Section("合同与收款") {
                    LabeledContent("合同金额") {
                        TextField("0", text: $newContractAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($newProjectFocusedField, equals: .contractAmount)
                    }
                    LabeledContent("已收款") {
                        TextField("0", text: $newPaidAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($newProjectFocusedField, equals: .paidAmount)
                    }
                    LabeledContent("材料成本") {
                        TextField("0", text: $newMaterialCost)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($newProjectFocusedField, equals: .materialCost)
                    }
                    LabeledContent("人工成本") {
                        TextField("0", text: $newLaborCost)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($newProjectFocusedField, equals: .laborCost)
                    }
                    Picker("收款状态", selection: $newPaymentStatus) {
                        ForEach(PaymentStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                }
            }
            .navigationTitle("新建工程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        clearProject()
                        showAdd = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        addProject()
                        showAdd = false
                    }
                    .disabled(!canCreateProject)
                }
                KeyboardNavigationToolbar(
                    focusedField: $newProjectFocusedField,
                    fields: [.contractAmount, .paidAmount, .materialCost, .laborCost]
                )
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func statusBadge(_ status: ProjectStatus) -> some View {
        ProjectStatusBadge(status: status)
    }

    private func deleteProject(keepData: Bool) {
        guard let pid = projectToDelete?.id else { return }
        if keepData {
            archiveProject()
            return
        } else {
            store.deleteProject(pid)
        }
    }

    private func archiveProject() {
        guard let pid = projectToDelete?.id,
              let index = projectStore.projects.firstIndex(where: { $0.id == pid }) else { return }
        store.projects[index].status = .archived
        projectToDelete = nil
        store.scheduleSave()
    }

    private func addProject() {
        guard canCreateProject else { return }
        store.projects.append(Project(
            name: newName.trimmingCharacters(in: .whitespacesAndNewlines),
            location: newLocation,
            status: .active,
            customerName: newCustomerName,
            customerPhone: newCustomerPhone,
            startDate: Formatters.date.string(from: newStartDate),
            expectedEndDate: Formatters.date.string(from: newExpectedEndDate),
            managerName: newManagerName,
            contractAmount: newContractAmount,
            paidAmount: newPaidAmount,
            paymentStatus: newPaymentStatus,
            materialCost: newMaterialCost,
            laborCost: newLaborCost
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
        newStartDate = Date()
        newExpectedEndDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    }

    private var canCreateProject: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (newContractAmount.isEmpty || InputValidator.nonNegativeNumber(newContractAmount)) &&
        (newPaidAmount.isEmpty || InputValidator.nonNegativeNumber(newPaidAmount)) &&
        (newMaterialCost.isEmpty || InputValidator.nonNegativeNumber(newMaterialCost)) &&
        (newLaborCost.isEmpty || InputValidator.nonNegativeNumber(newLaborCost))
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
        if financeStore.hasLegacyPaymentRecord(for: projectId) {
            return financeStore.legacyPaymentAmount(for: projectId)
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
            badges.append(ProjectRiskBadge(title: "延期", systemImage: "exclamationmark.triangle.fill", color: .red))
        }
        let todos = openTodoCount(for: project)
        if todos > 0 {
            badges.append(ProjectRiskBadge(title: "\(todos)待办", systemImage: "checklist", color: .orange))
        }
        let missingReceipts = unattachedReceiptCount(for: project)
        if missingReceipts > 0 {
            badges.append(ProjectRiskBadge(title: "\(missingReceipts)缺票", systemImage: "doc.badge.exclamationmark", color: .pink))
        }
        if unpaidAmount(for: project) > 0 {
            badges.append(ProjectRiskBadge(title: "未收", systemImage: "yensign.circle.fill", color: .blue))
        }
        return Array(badges.prefix(4))
    }

    private func toggleOverviewFilter(_ filter: ProjectOverviewFilter) {
        overviewFilter = overviewFilter == filter ? nil : filter
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

    private func missingTodayLog(for project: Project) -> Bool {
        guard project.status == .active || project.status == .paused else {
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
        if let latestPayment = financeStore.latestPaymentDate(for: projectId) {
            latest = max(latest, latestPayment)
        }
        if let latestLabor = financeStore.latestLaborDate(for: projectId) {
            latest = max(latest, latestLabor)
        }
        return latest
    }
}

// MARK: - 项目行内容（统一组件）

private struct ProjectRowContent: View {
    let project: Project
    let isSelected: Bool
    let unpaidAmount: Double
    let badges: [ProjectRiskBadge]

    private var riskColor: Color {
        if badges.contains(where: { $0.color == .red }) { return .red }
        if badges.contains(where: { $0.color == .orange }) { return .orange }
        if badges.contains(where: { $0.color == .pink }) { return .pink }
        return isSelected ? .orange : .clear
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.normal) {
            RoundedRectangle(cornerRadius: 2)
                .fill(riskColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: AppSpacing.tight * 0.625) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.tight) {
                    Text(project.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: AppSpacing.tight)
                    ProjectStatusBadge(status: project.status)
                }

                HStack(spacing: AppSpacing.tight) {
                    if !project.location.isEmpty {
                        Image(systemName: "mappin").font(.caption2)
                        Text(project.location)
                    }
                    if !project.customerName.isEmpty {
                        Text("·")
                        Text(project.customerName)
                    }
                    if !project.expectedEndDate.isEmpty {
                        Text("·")
                        Text("完工 \(project.expectedEndDate)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                HStack(spacing: AppSpacing.tight) {
                    if !project.contractAmount.isEmpty {
                        Text("合同 \(ReportBuilder.money(project.contractAmountValue.doubleValue))")
                            .font(.caption2.weight(.medium))
                    }
                    if unpaidAmount > 0 {
                        Text("未收 \(ReportBuilder.money(unpaidAmount))")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)

                if !badges.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(badges.prefix(3)), id: \.title) { badge in
                            ProjectRiskBadgeView(badge: badge)
                        }
                        if badges.count > 3 {
                            Text("+\(badges.count - 3)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 项目状态标签

private struct ProjectStatusBadge: View {
    let status: ProjectStatus

    private var color: Color {
        switch status {
        case .active: return .orange
        case .paused: return .yellow
        case .completed: return .green
        case .settled: return .blue
        case .archived: return .gray
        }
    }

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, AppSpacing.tight)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .clipShape(Capsule())
    }
}

// MARK: - 风险标签

private struct ProjectRiskBadgeView: View {
    let badge: ProjectRiskBadge

    var body: some View {
        Label(badge.title, systemImage: badge.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(badge.color)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(badge.color.opacity(0.14), in: Capsule())
            .lineLimit(1)
    }
}

enum ProjectOverviewFilter: String {
    case active
    case overdue
    case todo
    case missingReceipt
    case financialDue
    case missingTodayLog
}

private enum ProjectSortOption: String, CaseIterable {
    case recentUpdate = "最近更新"
    case expectedEnd = "预计完工"
    case unpaidAmount = "未收款"

    var displayName: String { rawValue }
}

private struct ProjectRiskBadge {
    let title: String
    let systemImage: String
    let color: Color
}

private struct FilterChip: View {
    let title: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.medium))
                .padding(.horizontal, AppSpacing.normal).padding(.vertical, 6)
                .background(isSelected ? Color.orange : Color.gray.opacity(0.15))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
