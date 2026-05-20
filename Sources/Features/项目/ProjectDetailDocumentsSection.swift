import SwiftUI

struct ProjectDocumentsView: View {
    @Environment(DataStore.self) private var store
    let project: Project
    let documents: [ProjectDocument]
    let requiredCategories: [ProjectDocumentCategory]
    let progressTasks: [ProgressTask]
    let financialRecords: [ProjectFinancialRecord]
    let constructionMethods: [ConstructionMethod]
    let icon: (ProjectDocumentCategory) -> String
    let onOpen: (ProjectDocument) -> Void
    let onLink: (UUID, UUID) -> Void
    let onScanCategory: (ProjectDocumentCategory) -> Void
    @State private var categoryFilter: DocumentCategoryFilter = .all
    @State private var relationFilter: DocumentRelationFilter = .all
    @State private var useDateRange = false
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var minAmount = ""
    @State private var maxAmount = ""
    @State private var operationNotice: OperationToastNotice?
    @State private var showSaveTemplatePrompt = false
    @State private var templateName = ""

    private var filteredDocuments: [ProjectDocument] {
        documents.filter { document in
            if !categoryFilter.matches(document) { return false }
            if !relationFilter.matches(document) { return false }
            if useDateRange {
                guard let date = parseDate(document.createdAt) else { return false }
                let start = Calendar.current.startOfDay(for: min(startDate, endDate))
                let endStart = Calendar.current.startOfDay(for: max(startDate, endDate))
                let end = Calendar.current.date(byAdding: .day, value: 1, to: endStart) ?? endStart
                if date < start || date >= end { return false }
            }
            let amount = document.amountValue.doubleValue
            if !minAmount.isEmpty && amount < MoneyValue(text: minAmount).doubleValue { return false }
            if !maxAmount.isEmpty && amount > MoneyValue(text: maxAmount).doubleValue { return false }
            return true
        }
    }

    private var suggestedMatches: [DocumentFinancialMatch] {
        filteredDocuments.compactMap { document in
            guard document.linkedFinancialRecordId == nil else { return nil }
            return ProjectFinancialDocumentMatcher.bestMatch(
                for: document,
                in: financialRecords
            )
        }
    }

    private var checklistSnapshot: DocumentArchiveChecklistSnapshot {
        DocumentArchiveChecklistSnapshot(
            documents: documents,
            requiredCategories: requiredCategories
        )
    }

    private var recommendedStage: ProjectDocumentRecommendationStage {
        ProjectDocumentCategory.recommendedStage(for: project, progressTasks: progressTasks)
    }

    private var savedDocumentChecklistTemplates: [ProjectDocumentChecklistTemplate] {
        ProjectDocumentChecklistTemplate.customTemplates(from: store.templates)
    }

    private var missingRecommendedCategories: [ProjectDocumentCategory] {
        let enabledCategories = Set(checklistSnapshot.requiredCategories)
        return ProjectDocumentCategory
            .recommendedConstructionArchiveRequirements(for: recommendedStage)
            .filter { !enabledCategories.contains($0) }
    }

    private var outsideTemplateChecklistItems: [DocumentArchiveChecklistItem] {
        let enabledCategories = Set(checklistSnapshot.requiredCategories)
        return outsideTemplateCategoryOrder(enabledCategories: enabledCategories).compactMap { category in
            let categoryDocuments = documents.filter { $0.category == category }
            guard !categoryDocuments.isEmpty else { return nil }
            return DocumentArchiveChecklistItem(category: category, documents: categoryDocuments)
        }
    }

    private var outsideTemplateDocumentCount: Int {
        outsideTemplateChecklistItems.reduce(0) { $0 + $1.documentCount }
    }

    var body: some View {
        Group {
            checklistSection

            if !documents.isEmpty || hasActiveFilters {
                Section {
                    Button {
                        showFilterSheet = true
                    } label: {
                        HStack {
                            Label(String(localized: "筛选"), systemImage: "line.3.horizontal.decrease.circle")
                            Spacer()
                            Text(filterSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if hasActiveFilters {
                        Button(String(localized: "清除筛选")) {
                            resetFilters()
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }

            Section(String(format: String(localized: "资料 (%lld)"), Int64(filteredDocuments.count))) {
                if filteredDocuments.isEmpty {
                    ProjectInlineEmptyState(
                        documents.isEmpty ? String(localized: "还没有资料") : String(localized: "没有匹配资料"),
                        systemImage: "doc.viewfinder",
                        detail: documents.isEmpty ? String(localized: "扫描票据或导入资料后可关联账目。") : String(localized: "调整筛选条件后再看。")
                    )
                } else {
                    if !suggestedMatches.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.tight) {
                            Label(String(localized: "缺票自动匹配建议"), systemImage: "wand.and.stars")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appWarning)
                            ForEach(suggestedMatches) { match in
                                HStack(alignment: .top, spacing: AppSpacing.tight) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(match.document.title)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        Text("\(match.record.date) · \(match.record.counterparty.isEmpty ? String(localized: "未填写单位") : match.record.counterparty)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(String(format: String(localized: "建议关联 %@"), ReportBuilder.money(match.record.amountValue.doubleValue)))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(String(localized: "关联")) {
                                        onLink(match.document.id, match.record.id)
                                    }
                                    .buttonStyle(.appProminent())
                                    .font(.caption2.weight(.semibold))
                                }
                            }
                        }
                        .padding(AppSpacing.tight)
                        .background(
                            RoundedRectangle(cornerRadius: AppSpacing.tight, style: .continuous)
                                .fill(Color.appPeachSurfaceSubtle)
                        )
                    }
                    ForEach(filteredDocuments) { document in
                        Button {
                            onOpen(document)
                        } label: {
                            HStack(spacing: AppSpacing.normal) {
                                Image(systemName: icon(document.category))
                                    .foregroundStyle(Color.appDoc)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(document.title).font(.callout.weight(.medium)).foregroundStyle(.primary)
                                    HStack(spacing: AppSpacing.tight) {
                                        Text(document.category.displayName)
                                        Text(String(format: String(localized: "%lld 页"), Int64(document.pageCount)))
                                        if document.amountValue.isPositive {
                                            Text(ReportBuilder.money(document.amountValue.doubleValue))
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    Text(document.createdAt)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    let registerLine = documentRegisterSummary(for: document)
                                    if !registerLine.isEmpty {
                                        Text(registerLine)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    let linkedTitles = linkedMethodTitles(for: document)
                                    if !linkedTitles.isEmpty {
                                        Text(String(format: String(localized: "工艺: %@"), linkedTitles.joined(separator: "、")))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            NavigationStack {
                Form {
                    filterForm
                }
                .navigationTitle(String(localized: "资料筛选"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "重置")) {
                            resetFilters()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "完成")) {
                            showFilterSheet = false
                        }
                    }
                    KeyboardDismissToolbar {
                        AppKeyboard.dismiss()
                    }
                }
            }
        }
        .operationToast(notice: $operationNotice)
        .alert(String(localized: "保存资料清单模板"), isPresented: $showSaveTemplatePrompt) {
            TextField(String(localized: "模板名称"), text: $templateName)
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "保存")) {
                saveCurrentChecklistTemplate()
            }
        } message: {
            Text(String(localized: "保存后，新建或编辑工程时可以直接套用。"))
        }
    }

    @State private var showFilterSheet = false

    private var checklistSection: some View {
        let snapshot = checklistSnapshot
        let inspection = ProjectDocumentDeliveryInspection(project: project, store: store)
        let pendingRemediationDrafts = remediationTodoDraftsWithoutOpenTodo(inspection.remediationTodoDrafts)
        return Section(String(localized: "资料清单")) {
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                HStack(alignment: .firstTextBaseline) {
                    Label(
                        String(format: String(localized: "覆盖 %lld/%lld 类"), Int64(snapshot.coveredCount), Int64(snapshot.requiredCount)),
                        systemImage: "checklist"
                    )
                    .font(.callout.weight(.semibold))
                    Spacer()
                    Text(snapshot.statusLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(snapshot.hasAttention ? Color.appWarning : Color.appSuccess)
                }
                ProgressView(
                    value: Double(snapshot.coveredCount),
                    total: Double(max(snapshot.requiredCount, 1))
                )
                HStack(spacing: AppSpacing.normal) {
                    Text(String(format: String(localized: "缺项 %lld"), Int64(snapshot.missingCount)))
                    Text(String(format: String(localized: "待处理 %lld"), Int64(snapshot.actionCount)))
                    Text(String(format: String(localized: "已归档 %lld"), Int64(snapshot.archivedDocumentCount)))
                    if outsideTemplateDocumentCount > 0 {
                        Text(String(format: String(localized: "模板外 %lld"), Int64(outsideTemplateDocumentCount)))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if snapshot.legacyDocumentCount > 0 {
                    Text(String(format: String(localized: "旧类资料 %lld 份待细分"), Int64(snapshot.legacyDocumentCount)))
                        .font(.caption2)
                        .foregroundStyle(Color.appWarning)
                }
                HStack(spacing: AppSpacing.tight) {
                    checklistTemplateMenu
                    Button {
                        beginSaveCurrentChecklistTemplate()
                    } label: {
                        Label(String(localized: "保存为模板"), systemImage: "tray.and.arrow.down.fill")
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption.weight(.semibold))
                if !missingRecommendedCategories.isEmpty {
                    stageRecommendationCard(missingRecommendedCategories)
                }
                if !missingChecklistItemsWithoutOpenTodo(snapshot.items).isEmpty {
                    Button {
                        createMissingDocumentTodos(from: snapshot.items)
                    } label: {
                        Label(String(localized: "生成缺项待办"), systemImage: "checklist.checked")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))
                }
                if !pendingRemediationDrafts.isEmpty {
                    Button {
                        createDeliveryInspectionTodos(from: inspection)
                    } label: {
                        Label(String(localized: "生成体检整改待办"), systemImage: "wrench.and.screwdriver.fill")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))
                }
            }

            ForEach(snapshot.items) { item in
                HStack(spacing: AppSpacing.tight) {
                    Button {
                        categoryFilter = DocumentCategoryFilter(category: item.category)
                    } label: {
                        checklistRow(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onScanCategory(item.category)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.appPrimaryAction)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(format: String(localized: "补录%@"), item.category.displayName))
                }
            }

            if !outsideTemplateChecklistItems.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Label(
                        String(format: String(localized: "模板外资料 %lld 份"), Int64(outsideTemplateDocumentCount)),
                        systemImage: "tray.full.fill"
                    )
                    .font(.callout.weight(.semibold))
                    Text(String(localized: "不计入当前施工资料模板覆盖率，仍保留在项目资料台账中。"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, AppSpacing.tight)

                ForEach(outsideTemplateChecklistItems) { item in
                    Button {
                        categoryFilter = DocumentCategoryFilter(category: item.category)
                    } label: {
                        checklistRow(item)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var checklistTemplateMenu: some View {
        Menu {
            Section(String(localized: "项目类型")) {
                ForEach(ProjectDocumentChecklistTemplate.builtInPresets) { template in
                    Button {
                        applyChecklistTemplate(template)
                    } label: {
                        Text(template.name)
                    }
                }
            }
            if !savedDocumentChecklistTemplates.isEmpty {
                Section(String(localized: "我的模板")) {
                    ForEach(savedDocumentChecklistTemplates) { template in
                        Button {
                            applyChecklistTemplate(template)
                        } label: {
                            Text(template.name)
                        }
                    }
                }
            }
        } label: {
            Label(String(localized: "套用模板"), systemImage: "square.stack.3d.up.fill")
        }
        .buttonStyle(.bordered)
    }

    private func applyChecklistTemplate(_ template: ProjectDocumentChecklistTemplate) {
        guard let index = store.projects.firstIndex(where: { $0.id == project.id }) else { return }
        var updatedProject = store.projects[index]
        updatedProject.requiredDocumentCategories = ProjectDocumentCategory.normalizedConstructionArchiveRequirements(
            template.categories
        )
        guard store.updateProject(updatedProject) else { return }
        store.scheduleSave()
        operationNotice = .info(String(format: String(localized: "已套用%@模板"), template.name))
    }

    private func beginSaveCurrentChecklistTemplate() {
        let normalizedProjectName = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = normalizedProjectName.isEmpty ? String(localized: "项目") : normalizedProjectName
        templateName = String(format: String(localized: "%@资料清单"), baseName)
        showSaveTemplatePrompt = true
    }

    private func saveCurrentChecklistTemplate() {
        let normalizedName = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = normalizedName.isEmpty ? String(localized: "资料清单模板") : normalizedName
        let template = ProjectTemplate.documentChecklistTemplate(
            name: resolvedName,
            categories: checklistSnapshot.requiredCategories
        )
        if let existing = store.templates.first(where: {
            $0.category == .projectDocumentChecklist &&
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == resolvedName
        }) {
            var updatedTemplate = template
            updatedTemplate.id = existing.id
            store.upsertTemplate(updatedTemplate, insertAtTopWhenNew: true)
        } else {
            store.insertTemplateAtTop(template)
        }
        store.scheduleSave()
        operationNotice = .info(String(localized: "已保存资料清单模板"))
    }

    private func stageRecommendationCard(_ missingCategories: [ProjectDocumentCategory]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            Label(
                String(format: String(localized: "%@建议补开 %lld 类"), recommendedStage.displayName, Int64(missingCategories.count)),
                systemImage: "wand.and.stars"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.appPrimaryAction)

            Text(missingCategories.map(\.displayName).joined(separator: "、"))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button {
                applyStageRecommendation(missingCategories)
            } label: {
                Label(String(localized: "启用阶段推荐"), systemImage: "checklist.checked")
            }
            .buttonStyle(.bordered)
            .font(.caption.weight(.semibold))
        }
        .padding(AppSpacing.tight)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.tight, style: .continuous)
                .fill(Color.appPeachSurfaceSubtle)
        )
    }

    private func checklistRow(_ item: DocumentArchiveChecklistItem) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.normal) {
            Image(systemName: item.systemImage)
                .font(.callout)
                .foregroundStyle(item.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.category.displayName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                Text(item.detailText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.tint)
        }
    }

    @ViewBuilder
    private var filterForm: some View {
        Section(String(localized: "类型")) {
            Picker(String(localized: "资料类型"), selection: $categoryFilter) {
                ForEach(DocumentCategoryFilter.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
            Picker(String(localized: "关联状态"), selection: $relationFilter) {
                ForEach(DocumentRelationFilter.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
        }
        Section(String(localized: "日期")) {
            Toggle(String(localized: "限定日期范围"), isOn: $useDateRange)
            if useDateRange {
                DatePicker(String(localized: "开始"), selection: $startDate, displayedComponents: .date)
                DatePicker(String(localized: "结束"), selection: $endDate, displayedComponents: .date)
            }
        }
        Section(String(localized: "金额")) {
            LabeledContent(String(localized: "最小金额")) {
                TextField("0", text: $minAmount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent(String(localized: "最大金额")) {
                TextField(String(localized: "不限"), text: $maxAmount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var hasActiveFilters: Bool {
        categoryFilter != .all || relationFilter != .all || useDateRange || !minAmount.isEmpty || !maxAmount.isEmpty
    }

    private var filterSummary: String {
        guard hasActiveFilters else { return String(localized: "全部资料") }
        var parts: [String] = []
        if categoryFilter != .all { parts.append(categoryFilter.displayName) }
        if relationFilter != .all { parts.append(relationFilter.displayName) }
        if useDateRange { parts.append(String(localized: "日期")) }
        if !minAmount.isEmpty || !maxAmount.isEmpty { parts.append(String(localized: "金额")) }
        return parts.joined(separator: " · ")
    }

    private func resetFilters() {
        categoryFilter = .all
        relationFilter = .all
        useDateRange = false
        minAmount = ""
        maxAmount = ""
    }

    private func parseDate(_ text: String) -> Date? {
        if let dt = Formatters.dateTime.date(from: text) {
            return dt
        }
        return Formatters.date.date(from: text)
    }

    private func outsideTemplateCategoryOrder(enabledCategories: Set<ProjectDocumentCategory>) -> [ProjectDocumentCategory] {
        var seen = Set<ProjectDocumentCategory>()
        let constructionOutsideTemplate = ProjectDocumentCategory.defaultConstructionArchiveRequirements
            .filter { !enabledCategories.contains($0) }
        let fixedOutsideCategories: [ProjectDocumentCategory] = [
            .construction,
            .acceptance,
            .contract,
            .invoice,
            .receipt,
            .paymentRequest,
            .other
        ]
        return (constructionOutsideTemplate + fixedOutsideCategories).filter { seen.insert($0).inserted }
    }

    private func linkedMethodTitles(for document: ProjectDocument) -> [String] {
        guard !document.linkedConstructionMethodIDs.isEmpty else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: constructionMethods.map { method in
            (method.id, methodTitle(method))
        })
        return document.linkedConstructionMethodIDs.compactMap { lookup[$0] }
    }

    private func documentRegisterSummary(for document: ProjectDocument) -> String {
        [
            document.versionDisplayText,
            document.submissionStatus.displayName,
            document.formedAt.isEmpty ? nil : String(format: String(localized: "形成 %@"), document.formedAt),
            document.responsiblePerson.isEmpty ? nil : String(format: String(localized: "责任人 %@"), document.responsiblePerson),
            document.workSection.isEmpty ? nil : document.workSection
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func methodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trade = method.trade.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? String(localized: "未命名工艺") : title
        return trade.isEmpty ? displayTitle : "\(trade) · \(displayTitle)"
    }

    private func missingChecklistItemsWithoutOpenTodo(_ items: [DocumentArchiveChecklistItem]) -> [DocumentArchiveChecklistItem] {
        items.filter { item in
            item.isMissing && !hasOpenArchiveTodo(for: item.category)
        }
    }

    private func hasOpenArchiveTodo(for category: ProjectDocumentCategory) -> Bool {
        hasOpenTodo(title: archiveTodoTitle(for: category))
    }

    private func hasOpenTodo(title: String) -> Bool {
        return store.siteTodos.contains { todo in
            todo.projectId == project.id &&
            !todo.isDone &&
            todo.title == title
        }
    }

    private func createMissingDocumentTodos(from items: [DocumentArchiveChecklistItem]) {
        let missingItems = missingChecklistItemsWithoutOpenTodo(items)
        guard !missingItems.isEmpty else {
            operationNotice = .info(String(localized: "缺项待办已存在"))
            return
        }
        let dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        for item in missingItems {
            store.insertSiteTodoAtTop(SiteTodo(
                title: archiveTodoTitle(for: item.category),
                owner: project.managerName,
                dueDate: Formatters.date.string(from: dueDate),
                priority: .medium,
                issueType: .general,
                note: String(format: String(localized: "施工资料清单缺项：%@。补录后到项目资料页更新报验状态和归档信息。"), item.category.displayName),
                projectId: project.id
            ))
        }
        store.scheduleSave()
        operationNotice = .info(String(format: String(localized: "已生成 %lld 条缺项待办"), Int64(missingItems.count)))
    }

    private func remediationTodoDraftsWithoutOpenTodo(
        _ drafts: [ProjectDocumentDeliveryInspectionTodoDraft]
    ) -> [ProjectDocumentDeliveryInspectionTodoDraft] {
        var seenTitles = Set<String>()
        return drafts.filter { draft in
            seenTitles.insert(draft.title).inserted && !hasOpenTodo(title: draft.title)
        }
    }

    private func createDeliveryInspectionTodos(from inspection: ProjectDocumentDeliveryInspection) {
        let drafts = remediationTodoDraftsWithoutOpenTodo(inspection.remediationTodoDrafts)
        guard !drafts.isEmpty else {
            operationNotice = .info(String(localized: "体检整改待办已存在"))
            return
        }

        let dueDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        for draft in drafts {
            store.insertSiteTodoAtTop(SiteTodo(
                title: draft.title,
                owner: project.managerName,
                dueDate: Formatters.date.string(from: dueDate),
                priority: draft.priority,
                issueType: draft.issueType,
                note: draft.note,
                projectId: project.id
            ))
        }

        store.scheduleSave()
        operationNotice = .info(String(format: String(localized: "已生成 %lld 条体检整改待办"), Int64(drafts.count)))
    }

    private func applyStageRecommendation(_ missingCategories: [ProjectDocumentCategory]) {
        guard !missingCategories.isEmpty else { return }
        guard let index = store.projects.firstIndex(where: { $0.id == project.id }) else { return }
        var updatedProject = store.projects[index]
        let merged = updatedProject.requiredDocumentCategories + missingCategories
        updatedProject.requiredDocumentCategories = ProjectDocumentCategory.normalizedConstructionArchiveRequirements(merged)
        guard store.updateProject(updatedProject) else { return }
        store.scheduleSave()
        operationNotice = .info(String(format: String(localized: "已启用%@推荐"), recommendedStage.displayName))
    }

    private func archiveTodoTitle(for category: ProjectDocumentCategory) -> String {
        String(format: String(localized: "补齐施工资料：%@"), category.displayName)
    }

}

extension DocumentArchiveChecklistItem {
    var tint: Color {
        if isMissing || returnedCount > 0 { return .appWarning }
        if actionCount > 0 { return .appPrimaryAction }
        return .appSuccess
    }
}

private enum DocumentCategoryFilter: String, CaseIterable {
    case all
    case constructionArchive
    case constructionTechnical
    case constructionMaterial
    case constructionSurvey
    case constructionRecord
    case constructionTest
    case constructionManagement
    case processAcceptance
    case completionAcceptance
    case businessArchive
    case paymentRequest
    case contract
    case invoice
    case receipt
    case legacyConstruction
    case acceptance
    case other

    var displayName: String {
        switch self {
        case .all:
            return String(localized: "全部")
        case .constructionArchive:
            return String(localized: "全部施工资料")
        case .constructionTechnical:
            return String(localized: "施工技术")
        case .constructionMaterial:
            return String(localized: "施工物资")
        case .constructionSurvey:
            return String(localized: "施工测量")
        case .constructionRecord:
            return String(localized: "施工记录")
        case .constructionTest:
            return String(localized: "施工试验")
        case .constructionManagement:
            return String(localized: "施工管理")
        case .processAcceptance:
            return String(localized: "过程验收")
        case .completionAcceptance:
            return String(localized: "竣工验收")
        case .businessArchive:
            return String(localized: "商务/财务")
        case .paymentRequest:
            return String(localized: "请款资料")
        case .contract:
            return String(localized: "合同")
        case .invoice:
            return String(localized: "发票")
        case .receipt:
            return String(localized: "收据")
        case .legacyConstruction:
            return String(localized: "施工资料")
        case .acceptance:
            return String(localized: "验收资料")
        case .other:
            return String(localized: "其他资料")
        }
    }

    init(category: ProjectDocumentCategory) {
        switch category {
        case .constructionTechnical:
            self = .constructionTechnical
        case .constructionMaterial:
            self = .constructionMaterial
        case .constructionSurvey:
            self = .constructionSurvey
        case .constructionRecord:
            self = .constructionRecord
        case .constructionTest:
            self = .constructionTest
        case .constructionManagement:
            self = .constructionManagement
        case .processAcceptance:
            self = .processAcceptance
        case .completionAcceptance:
            self = .completionAcceptance
        case .invoice:
            self = .invoice
        case .receipt:
            self = .receipt
        case .paymentRequest:
            self = .paymentRequest
        case .contract:
            self = .contract
        case .acceptance:
            self = .acceptance
        case .other:
            self = .other
        case .construction:
            self = .legacyConstruction
        }
    }

    func matches(_ document: ProjectDocument) -> Bool {
        switch self {
        case .all:
            return true
        case .constructionArchive:
            return document.category.isConstructionArchive
        case .constructionTechnical:
            return document.category == .constructionTechnical
        case .constructionMaterial:
            return document.category == .constructionMaterial
        case .constructionSurvey:
            return document.category == .constructionSurvey
        case .constructionRecord:
            return document.category == .constructionRecord
        case .constructionTest:
            return document.category == .constructionTest
        case .constructionManagement:
            return document.category == .constructionManagement
        case .processAcceptance:
            return document.category == .processAcceptance
        case .completionAcceptance:
            return document.category == .completionAcceptance
        case .businessArchive:
            return document.category.isBusinessArchive
        case .paymentRequest:
            return document.category == .paymentRequest
        case .contract:
            return document.category == .contract
        case .invoice:
            return document.category == .invoice
        case .receipt:
            return document.category == .receipt
        case .legacyConstruction:
            return document.category == .construction
        case .acceptance:
            return document.category == .acceptance
        case .other:
            return document.category == .other
        }
    }
}

private enum DocumentRelationFilter: String, CaseIterable {
    case all
    case linked
    case unlinked

    var displayName: String {
        switch self {
        case .all:
            return String(localized: "全部")
        case .linked:
            return String(localized: "已关联账目")
        case .unlinked:
            return String(localized: "未关联账目")
        }
    }

    func matches(_ document: ProjectDocument) -> Bool {
        switch self {
        case .all:
            return true
        case .linked:
            return document.linkedFinancialRecordId != nil
        case .unlinked:
            return document.linkedFinancialRecordId == nil
        }
    }
}

private typealias DocumentFinancialMatch = ProjectDocumentMatchSuggestion
