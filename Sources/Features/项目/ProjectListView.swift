import SwiftUI

struct ProjectListView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
        var result = store.projects
        if !normalizedSearchText.isEmpty {
            result = result.filter { $0.name.localizedStandardContains(normalizedSearchText) || $0.location.localizedStandardContains(normalizedSearchText) }
        }
        if let sf = statusFilter {
            result = result.filter { $0.status == sf.rawValue }
        }
        if let overviewFilter {
            result = result.filter { project in
                switch overviewFilter {
                case .active:
                    return project.status == ProjectStatus.active.rawValue || project.status == ProjectStatus.paused.rawValue
                case .overdue:
                    return hasOverdueItem(for: project)
                case .todo:
                    return openTodoCount(for: project) > 0
                case .missingReceipt:
                    return unattachedReceiptCount(for: project) > 0
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
        store.projects.filter { $0.status == ProjectStatus.active.rawValue || $0.status == ProjectStatus.paused.rawValue }.count
    }

    private var overdueCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        let progress = store.progressTasks.filter { task in
            guard task.clampedCompletion < 1,
                  let due = Formatters.date.date(from: task.dueDate) else { return false }
            return due < today
        }.count
        return progress + store.siteTodos.filter(\.isOverdue).count
    }

    private var openTodoCount: Int {
        store.siteTodos.filter { !$0.isDone }.count
    }

    private var unattachedReceiptCount: Int {
        store.projectFinancialRecords.filter { record in
            guard record.requiresAttachment else { return false }
            let linkedByList = !record.linkedDocumentIds.isEmpty
            let linkedByDocument = store.projectDocuments.contains { $0.linkedFinancialRecordId == record.id }
            return !(linkedByList || linkedByDocument)
        }.count
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
        return UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var visibleProjectIDs: [UUID] {
        sortedProjects.map(\.id)
    }

    private var selectedProject: Project? {
        guard let selectedProjectId else { return nil }
        return store.projects.first { $0.id == selectedProjectId }
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
        if isSplitNavigation {
            List {
                projectListSections(isSplitNavigation: true)
            }
            .searchable(text: $searchText, prompt: "按名称或地点搜索")
        } else {
            List {
                projectListSections(isSplitNavigation: false)
            }
            .searchable(text: $searchText, prompt: "按名称或地点搜索")
        }
    }

    @ViewBuilder
    private func projectListSections(isSplitNavigation: Bool) -> some View {
        Section("工程概况") {
            if isSplitNavigation {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                    ProjectCompactMetric(
                        title: "进行中",
                        value: "\(activeProjectCount)",
                        color: .green,
                        isSelected: overviewFilter == .active,
                        expandsToFill: true
                    ) {
                        toggleOverviewFilter(.active)
                    }
                    ProjectCompactMetric(
                        title: "延期",
                        value: "\(overdueCount)",
                        color: overdueCount > 0 ? .red : .green,
                        isSelected: overviewFilter == .overdue,
                        expandsToFill: true
                    ) {
                        toggleOverviewFilter(.overdue)
                    }
                    ProjectCompactMetric(
                        title: "待办",
                        value: "\(openTodoCount)",
                        color: openTodoCount > 0 ? .orange : .green,
                        isSelected: overviewFilter == .todo,
                        expandsToFill: true
                    ) {
                        toggleOverviewFilter(.todo)
                    }
                    ProjectCompactMetric(
                        title: "缺票",
                        value: "\(unattachedReceiptCount)",
                        color: unattachedReceiptCount > 0 ? .pink : .green,
                        isSelected: overviewFilter == .missingReceipt,
                        expandsToFill: true
                    ) {
                        toggleOverviewFilter(.missingReceipt)
                    }
                }
                .padding(.vertical, 2)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ProjectCompactMetric(title: "进行中", value: "\(activeProjectCount)", color: .green, isSelected: overviewFilter == .active) {
                            toggleOverviewFilter(.active)
                        }
                        ProjectCompactMetric(title: "延期", value: "\(overdueCount)", color: overdueCount > 0 ? .red : .green, isSelected: overviewFilter == .overdue) {
                            toggleOverviewFilter(.overdue)
                        }
                        ProjectCompactMetric(title: "待办", value: "\(openTodoCount)", color: openTodoCount > 0 ? .orange : .green, isSelected: overviewFilter == .todo) {
                            toggleOverviewFilter(.todo)
                        }
                        ProjectCompactMetric(title: "缺票", value: "\(unattachedReceiptCount)", color: unattachedReceiptCount > 0 ? .pink : .green, isSelected: overviewFilter == .missingReceipt) {
                            toggleOverviewFilter(.missingReceipt)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 0))
            }
        }

        Section {
            if isSplitNavigation {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Menu {
                            Button("全部状态") { statusFilter = nil }
                            ForEach(ProjectStatus.allCases, id: \.self) { status in
                                Button(status.displayName) {
                                    statusFilter = status
                                }
                            }
                        } label: {
                            Label(statusFilter?.displayName ?? "全部状态", systemImage: "line.3.horizontal.decrease.circle")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
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
                                .padding(.horizontal, 10)
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

                    if overviewFilter != nil {
                        Button {
                            overviewFilter = nil
                        } label: {
                            Label("清除工程概况筛选", systemImage: "xmark.circle")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
                .padding(.vertical, 2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "全部", isSelected: statusFilter == nil) { statusFilter = nil }
                        ForEach(ProjectStatus.allCases, id: \.self) { s in
                            FilterChip(title: s.displayName, isSelected: statusFilter == s) { statusFilter = s }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Picker("排序", selection: $sortOption) {
                    ForEach(ProjectSortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                if overviewFilter != nil {
                    Button {
                        overviewFilter = nil
                    } label: {
                        Label("清除工程概况筛选", systemImage: "xmark.circle")
                            .font(.caption.weight(.semibold))
                    }
                }
            }
        }

        if sortedProjects.isEmpty {
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

        ForEach(sortedProjects) { project in
            Group {
                if isSplitNavigation {
                    Button {
                        selectedProjectId = project.id
                    } label: {
                        projectRowContent(project)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedProjectId == project.id ? Color.orange.opacity(0.1) : Color.clear)
                } else {
                    NavigationLink {
                        ProjectDetailView(projectId: project.id)
                    } label: {
                        projectRowContent(project)
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
            if let target = store.projects.first(where: { ids.contains($0.id) }) {
                projectToDelete = target
                showDeleteConfirm = true
            }
        }
    }

    private func projectRowContent(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.body.weight(.medium))
            HStack {
                Text(project.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                statusBadge(project.status)
            }
            HStack(spacing: 8) {
                if !project.customerName.isEmpty {
                    Text(project.customerName)
                }
                if !project.expectedEndDate.isEmpty {
                    Text("完工 \(project.expectedEndDate)")
                }
                if !project.contractAmount.isEmpty {
                    Text("合同 \(ReportBuilder.money(Double(project.contractAmount) ?? 0))")
                }
                let unpaid = unpaidAmount(for: project)
                if unpaid > 0 {
                    Text("未收 \(ReportBuilder.money(unpaid))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
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
                    }
                    LabeledContent("已收款") {
                        TextField("0", text: $newPaidAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("材料成本") {
                        TextField("0", text: $newMaterialCost)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("人工成本") {
                        TextField("0", text: $newLaborCost)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("收款状态", selection: $newPaymentStatus) {
                        ForEach(PaymentStatus.allCases, id: \.self) { status in
                            Text(status.displayName).tag(status)
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
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        let color: Color = {
            switch status {
            case ProjectStatus.active.rawValue: return .orange
            case ProjectStatus.paused.rawValue: return .yellow
            case ProjectStatus.completed.rawValue: return .green
            case ProjectStatus.settled.rawValue: return .blue
            case ProjectStatus.archived.rawValue: return .gray
            default: return .gray
            }
        }()
        Text(status).font(.caption2.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.2)).clipShape(Capsule())
    }

    private func deleteProject(keepData: Bool) {
        guard let pid = projectToDelete?.id else { return }
        if keepData {
            archiveProject()
        } else {
            store.deleteProject(pid)
        }
    }

    private func archiveProject() {
        guard let pid = projectToDelete?.id,
              let index = store.projects.firstIndex(where: { $0.id == pid }) else { return }
        store.projects[index].status = ProjectStatus.archived.rawValue
        projectToDelete = nil
        store.scheduleSave()
    }

    private func addProject() {
        guard canCreateProject else { return }
        store.projects.append(Project(
            name: newName.trimmingCharacters(in: .whitespacesAndNewlines),
            location: newLocation,
            status: ProjectStatus.active.rawValue,
            customerName: newCustomerName,
            customerPhone: newCustomerPhone,
            startDate: Formatters.date.string(from: newStartDate),
            expectedEndDate: Formatters.date.string(from: newExpectedEndDate),
            managerName: newManagerName,
            contractAmount: newContractAmount,
            paidAmount: newPaidAmount,
            paymentStatus: newPaymentStatus.rawValue,
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
        return store.materialItems.filter { $0.projectId == pid }.count
            + store.quoteItems.filter { $0.projectId == pid }.count
            + store.laborRecords.filter { $0.projectId == pid }.count
            + store.dailyLogs.filter { $0.projectId == pid }.count
            + store.progressTasks.filter { $0.projectId == pid }.count
            + store.lightingCircuitPlans.filter { $0.projectId == pid }.count
            + store.siteTodos.filter { $0.projectId == pid }.count
            + store.paymentRecords.filter { $0.projectId == pid }.count
            + store.projectDrawings.filter { $0.projectId == pid }.count
            + store.projectContacts.filter { $0.projectId == pid }.count
            + store.projectFinancialRecords.filter { $0.projectId == pid }.count
            + store.projectDocuments.filter { $0.projectId == pid }.count
            + store.projectWarehouseMovements.filter { $0.projectId == pid }.count
            + store.quickNotes.filter { $0.projectId == pid }.count
    }

    private func expectedEndDate(for project: Project) -> Date {
        Formatters.date.date(from: project.expectedEndDate) ?? .distantFuture
    }

    private func paidAmount(for project: Project) -> Double {
        let records = store.projectFinancialRecords.filter {
            $0.projectId == project.id && $0.direction == ProjectFinancialDirection.income.rawValue
        }
        let amountFromFinancial = records.reduce(0) { result, item in
            let category = ProjectFinancialCategory(rawValue: item.category)
            guard category == .collection || category == .receipt else { return result }
            return result + ReportBuilder.number(item.amount)
        }
        if amountFromFinancial > 0 {
            return amountFromFinancial
        }
        let legacyPayments = store.paymentRecords.filter { $0.projectId == project.id }
        if !legacyPayments.isEmpty {
            return legacyPayments.reduce(0) { $0 + ReportBuilder.number($1.amount) }
        }
        return ReportBuilder.number(project.paidAmount)
    }

    private func customerPhoneURL(for project: Project) -> URL? {
        let raw = project.customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let normalized = raw.replacingOccurrences(of: " ", with: "")
        return URL(string: "tel:\(normalized)")
    }

    private func unpaidAmount(for project: Project) -> Double {
        max(ReportBuilder.number(project.contractAmount) - paidAmount(for: project), 0)
    }

    private func toggleOverviewFilter(_ filter: ProjectOverviewFilter) {
        overviewFilter = overviewFilter == filter ? nil : filter
    }

    private func hasOverdueItem(for project: Project) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let hasOverdueProgress = store.progressTasks.contains { task in
            guard task.projectId == project.id,
                  task.clampedCompletion < 1,
                  let due = Formatters.date.date(from: task.dueDate) else { return false }
            return due < today
        }
        return hasOverdueProgress || store.siteTodos.contains { $0.projectId == project.id && $0.isOverdue }
    }

    private func openTodoCount(for project: Project) -> Int {
        store.siteTodos.filter { $0.projectId == project.id && !$0.isDone }.count
    }

    private func unattachedReceiptCount(for project: Project) -> Int {
        store.projectFinancialRecords.filter { record in
            guard record.projectId == project.id, record.requiresAttachment else { return false }
            let linkedByList = !record.linkedDocumentIds.isEmpty
            let linkedByDocument = store.projectDocuments.contains { $0.linkedFinancialRecordId == record.id }
            return !(linkedByList || linkedByDocument)
        }.count
    }

    private func recentActivityDate(for project: Project) -> Date {
        var dates: [Date] = []
        let projectId = project.id
        if let start = Formatters.date.date(from: project.startDate) {
            dates.append(start)
        }
        for item in store.dailyLogs where item.projectId == projectId {
            if let date = Formatters.date.date(from: item.date) {
                dates.append(date)
            }
        }
        for item in store.paymentRecords where item.projectId == projectId {
            if let date = Formatters.date.date(from: item.date) {
                dates.append(date)
            }
        }
        for item in store.projectFinancialRecords where item.projectId == projectId {
            if let date = Formatters.date.date(from: item.date) {
                dates.append(date)
            }
        }
        for item in store.laborRecords where item.projectId == projectId {
            if let date = Formatters.date.date(from: item.date) {
                dates.append(date)
            }
        }
        for item in store.progressTasks where item.projectId == projectId {
            if let date = Formatters.date.date(from: item.startDate) {
                dates.append(date)
            }
            if let date = Formatters.date.date(from: item.dueDate) {
                dates.append(date)
            }
        }
        for item in store.siteTodos where item.projectId == projectId {
            if let date = Formatters.date.date(from: item.dueDate) {
                dates.append(date)
            }
        }
        for item in store.projectDrawings where item.projectId == projectId {
            if let date = Formatters.dateTime.date(from: item.importedAt) {
                dates.append(date)
            }
        }
        for item in store.projectDocuments where item.projectId == projectId {
            if let date = Formatters.dateTime.date(from: item.createdAt) {
                dates.append(date)
            }
        }
        for item in store.projectWarehouseMovements where item.projectId == projectId {
            if let date = Formatters.date.date(from: item.date) {
                dates.append(date)
            }
        }
        return dates.max() ?? .distantPast
    }
}

private struct ProjectCompactMetric: View {
    let title: String
    let value: String
    let color: Color
    var isSelected = false
    var expandsToFill = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white.opacity(0.86) : .secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(width: expandsToFill ? nil : 82, alignment: .leading)
            .frame(minHeight: 38, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(isSelected ? color : Color(uiColor: .secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }
}

enum ProjectOverviewFilter: String {
    case active
    case overdue
    case todo
    case missingReceipt
}

private enum ProjectSortOption: String, CaseIterable {
    case recentUpdate
    case expectedEnd
    case unpaidAmount

    var displayName: String {
        switch self {
        case .recentUpdate: "最近更新"
        case .expectedEnd: "预计完工"
        case .unpaidAmount: "未收款"
        }
    }
}

private struct FilterChip: View {
    let title: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? Color.orange : Color.gray.opacity(0.15))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
