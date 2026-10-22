import SwiftUI

struct ProjectDocumentsView: View {
    @Environment(DataStore.self) var store
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
    @State var operationNotice: OperationToastNotice?
    @State var showSaveTemplatePrompt = false
    @State var templateName = ""

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

    var checklistSnapshot: DocumentArchiveChecklistSnapshot {
        DocumentArchiveChecklistSnapshot(
            documents: documents,
            requiredCategories: requiredCategories
        )
    }

    var recommendedStage: ProjectDocumentRecommendationStage {
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

    private var primaryDocumentCategoryForEmptyAction: ProjectDocumentCategory {
        missingRecommendedCategories.first
            ?? checklistSnapshot.items.first(where: { $0.documentCount == 0 })?.category
            ?? .receipt
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
                    AppActionableEmptyState(
                        title: documents.isEmpty ? String(localized: "还没有资料") : String(localized: "没有匹配资料"),
                        systemImage: "doc.viewfinder",
                        message: documents.isEmpty ? String(localized: "扫描票据或导入资料后可关联账目。") : String(localized: "调整筛选条件后再看。")
                    ) {
                        Button {
                            if documents.isEmpty {
                                onScanCategory(primaryDocumentCategoryForEmptyAction)
                            } else {
                                resetFilters()
                            }
                        } label: {
                            Label(
                                documents.isEmpty ? String(localized: "扫描/导入资料") : String(localized: "清除筛选"),
                                systemImage: documents.isEmpty ? "doc.viewfinder" : "line.3.horizontal.decrease.circle"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.appProminent())
                    }
                } else {
                    if !suggestedMatches.isEmpty {
                        ProjectDocumentMatchSuggestionsView(
                            matches: suggestedMatches,
                            onLink: onLink
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
                                    Text(Formatters.displayDateText(document.createdAt))
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
            AppBusinessFormSheet(
                title: String(localized: "资料筛选"),
                cancelTitle: String(localized: "重置"),
                primaryActionTitle: String(localized: "完成"),
                onCancel: { resetFilters() },
                onPrimaryAction: { showFilterSheet = false }
            ) {
                ProjectDocumentsFilterFormSection(
                    categoryFilter: $categoryFilter,
                    relationFilter: $relationFilter,
                    useDateRange: $useDateRange,
                    startDate: $startDate,
                    endDate: $endDate,
                    minAmount: $minAmount,
                    maxAmount: $maxAmount
                )
            }
            .appKeyboardToolbar {
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
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
                    ProjectDocumentStageRecommendationCard(
                        stageDisplayName: recommendedStage.displayName,
                        missingCategories: missingRecommendedCategories
                    ) {
                        applyStageRecommendation(missingRecommendedCategories)
                    }
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
                        ProjectDocumentChecklistRowView(item: item)
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
                        ProjectDocumentChecklistRowView(item: item)
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
        if let dt = Formatters.parseDateOrDateTime(text) {
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
}
