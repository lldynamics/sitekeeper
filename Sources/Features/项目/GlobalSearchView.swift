import SwiftUI

struct GlobalSearchView: View {
    @Environment(DataStore.self) private var store
    @State private var keyword: String
    @State private var results = GlobalSearchResults()
    @State private var selectedScope: GlobalSearchScope = .all
    @State private var indexCache: GlobalSearchIndexCache?
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false
    @AppStorage("recentGlobalSearchKeywords") private var recentKeywordsRaw = ""

    init(initialKeyword: String = "") {
        _keyword = State(initialValue: initialKeyword)
    }

    private var trimmedKeyword: String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recentKeywords: [String] {
        recentKeywordsRaw
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var scopedResults: GlobalSearchResults {
        results.filtered(by: selectedScope).limited(to: 20)
    }

    var body: some View {
        List {
            if trimmedKeyword.isEmpty {
                emptySearchContent
            } else {
                searchScopeSection
                if isSearching {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在搜索...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                resultSections(scopedResults)
            }
        }
        .navigationTitle("全局搜索")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $keyword, prompt: "例如：示例客户 / 发票号 / 布线")
        .onSubmit(of: .search) {
            rememberSearch()
            refreshSearchIndex()
            scheduleSearch(immediate: true)
        }
        .onChange(of: keyword) { _, _ in
            scheduleSearch()
        }
        .onChange(of: store.searchIndexVersion) { _, _ in
            guard indexCache != nil else { return }
            indexCache = GlobalSearchIndexCache(store: store)
            if !trimmedKeyword.isEmpty {
                scheduleSearch(immediate: true)
            }
        }
        .onAppear {
            refreshSearchIndex()
            scheduleSearch(immediate: true)
            rememberSearch()
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    @ViewBuilder
    private var emptySearchContent: some View {
        ContentUnavailableView(
            "输入关键词开始搜索",
            systemImage: "magnifyingglass",
            description: Text("支持项目、联系人、票号、日志、资料、待办、随手记和工程数据库")
        )
        if !recentKeywords.isEmpty {
            Section("最近搜索") {
                ForEach(recentKeywords, id: \.self) { term in
                    Button {
                        keyword = term
                    } label: {
                        Label(term, systemImage: "clock.arrow.circlepath")
                    }
                }
            }
        }
    }

    private var searchScopeSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GlobalSearchScope.allCases, id: \.self) { scope in
                        SearchScopeChip(
                            title: scope.title,
                            systemImage: scope.systemImage,
                            isSelected: selectedScope == scope
                        ) {
                            selectedScope = scope
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func resultSections(_ results: GlobalSearchResults) -> some View {
        if results.isEmpty {
            ContentUnavailableView(selectedScope == .all ? "无匹配结果" : "当前分类无匹配结果", systemImage: "doc.text.magnifyingglass")
        }

        if !results.projects.isEmpty {
            Section("项目 (\(results.projects.count))") {
                ForEach(results.projects) { project in
                    NavigationLink {
                        ProjectDetailView(projectId: project.id)
                    } label: {
                        searchRow(
                            title: project.name,
                            subtitle: [project.location, project.customerName].filter { !$0.isEmpty }.joined(separator: " · ")
                        )
                    }
                }
            }
        }

        if !results.contacts.isEmpty {
            Section(String(localized: "联系人 (\(results.contacts.count))")) {
                ForEach(results.contacts) { match in
                    NavigationLink {
                        ProjectContactDatabaseView(focusedContactId: match.contact.id)
                    } label: {
                        searchRow(
                            title: match.contact.name,
                            subtitle: [match.contact.role, match.contact.phone, match.project?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                        )
                    }
                }
            }
        }

        if !results.financialRecords.isEmpty {
            Section("项目财务 (\(results.financialRecords.count))") {
                ForEach(results.financialRecords) { match in
                    if let project = match.project {
                        NavigationLink {
                            ProjectDetailView(projectId: project.id, initialMode: .finance, focus: .financialRecord(match.record.id))
                        } label: {
                            searchRow(
                                title: "\(match.record.date) · \(match.record.direction) \(ReportBuilder.money(ReportBuilder.number(match.record.amount)))",
                                subtitle: [match.record.counterparty, match.record.invoiceNumber, project.name].filter { !$0.isEmpty }.joined(separator: " · ")
                            )
                        }
                    }
                }
            }
        }

        if !results.logs.isEmpty {
            Section("施工日志 (\(results.logs.count))") {
                ForEach(results.logs) { match in
                    NavigationLink {
                        if let project = match.project {
                            DailyLogView(initialProjectId: project.id, focusedLogId: match.log.id)
                        } else {
                            DailyLogView(focusedLogId: match.log.id)
                        }
                    } label: {
                        searchRow(
                            title: [match.log.date, match.project?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                            subtitle: match.log.content,
                            subtitleLineLimit: 2
                        )
                    }
                }
            }
        }

        if !results.documents.isEmpty {
            Section("票据与资料 (\(results.documents.count))") {
                ForEach(results.documents) { match in
                    NavigationLink {
                        if let project = match.project {
                            ProjectDetailView(projectId: project.id, initialMode: .assets, focus: .document(match.document.id))
                        } else {
                            ProjectListView()
                        }
                    } label: {
                        searchRow(
                            title: match.document.title,
                            subtitle: [match.document.category, match.project?.name ?? "未归属项目"].joined(separator: " · ")
                        )
                    }
                }
            }
        }

        if !results.todos.isEmpty {
            Section("现场待办 (\(results.todos.count))") {
                ForEach(results.todos) { match in
                    NavigationLink {
                        SiteTodoView(initialProjectId: match.todo.projectId, focusedTodoId: match.todo.id)
                    } label: {
                        searchRow(
                            title: match.todo.title,
                            subtitle: [match.todo.dueDate, match.todo.owner, match.project?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                        )
                    }
                }
            }
        }

        if !results.materials.isEmpty {
            Section("材料 (\(results.materials.count))") {
                ForEach(results.materials) { match in
                    NavigationLink {
                        MaterialListView(focusedMaterialId: match.item.id)
                    } label: {
                        searchRow(
                            title: match.item.name,
                            subtitle: [match.item.specification, match.item.brand, match.item.supplier, match.project?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                        )
                    }
                }
            }
        }

        if !results.quotes.isEmpty {
            Section("报价 (\(results.quotes.count))") {
                ForEach(results.quotes) { match in
                    NavigationLink {
                        QuotationView(focusedQuoteId: match.item.id)
                    } label: {
                        searchRow(
                            title: match.item.name,
                            subtitle: [match.item.versionName, match.item.status, match.project?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                        )
                    }
                }
            }
        }

        if !results.laborRecords.isEmpty {
            Section("人工 (\(results.laborRecords.count))") {
                ForEach(results.laborRecords) { match in
                    NavigationLink {
                        LaborRecordView(focusedLaborId: match.item.id)
                    } label: {
                        searchRow(
                            title: "\(match.item.date) · \(match.item.workType.isEmpty ? "人工记录" : match.item.workType)",
                            subtitle: [match.item.teamName, match.item.note, match.project?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
                        )
                    }
                }
            }
        }

        if !results.quickNotes.isEmpty {
            Section("随手记 (\(results.quickNotes.count))") {
                ForEach(results.quickNotes) { match in
                    NavigationLink {
                        QuickNoteView(focusedNoteId: match.note.id)
                    } label: {
                        searchRow(
                            title: match.note.title.isEmpty ? "未命名记录" : match.note.title,
                            subtitle: [match.note.content, match.project?.name ?? ""].filter { !$0.isEmpty }.joined(separator: " · "),
                            subtitleLineLimit: 2
                        )
                    }
                }
            }
        }

        if !results.materialPrices.isEmpty {
            Section("材料价格库 (\(results.materialPrices.count))") {
                ForEach(results.materialPrices) { item in
                    NavigationLink {
                        MaterialPriceDatabaseView(focusedEntryId: item.id)
                    } label: {
                        searchRow(
                            title: item.name.isEmpty ? "未命名材料" : item.name,
                            subtitle: [item.specification, item.brand, item.supplier, item.referencePrice.isEmpty ? "" : "¥\(item.referencePrice)"].filter { !$0.isEmpty }.joined(separator: " · ")
                        )
                    }
                }
            }
        }

        if !results.suppliers.isEmpty {
            Section("供应商库 (\(results.suppliers.count))") {
                ForEach(results.suppliers) { item in
                    NavigationLink {
                        SupplierDatabaseView(focusedSupplierId: item.id)
                    } label: {
                        searchRow(
                            title: item.name.isEmpty ? "未命名供应商" : item.name,
                            subtitle: [item.category, item.contact, item.phone].filter { !$0.isEmpty }.joined(separator: " · ")
                        )
                    }
                }
            }
        }

        if !results.constructionMethods.isEmpty {
            Section("施工工艺库 (\(results.constructionMethods.count))") {
                ForEach(results.constructionMethods) { item in
                    NavigationLink {
                        ConstructionMethodLibraryView(focusedMethodId: item.id)
                    } label: {
                        searchRow(
                            title: item.title.isEmpty ? "未命名工艺" : item.title,
                            subtitle: [item.trade, item.qualityStandard].filter { !$0.isEmpty }.joined(separator: " · "),
                            subtitleLineLimit: 2
                        )
                    }
                }
            }
        }

        if !results.quoteTemplates.isEmpty {
            Section("报价模板库 (\(results.quoteTemplates.count))") {
                ForEach(results.quoteTemplates) { item in
                    NavigationLink {
                        QuotationTemplateLibraryView(focusedTemplateId: item.id)
                    } label: {
                        searchRow(title: item.name, subtitle: item.content, subtitleLineLimit: 2)
                    }
                }
            }
        }
    }

    private func searchRow(title: String, subtitle: String, subtitleLineLimit: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HighlightedText(text: title, keyword: trimmedKeyword, font: .body.weight(.semibold), color: .primary)
            if !subtitle.isEmpty {
                HighlightedText(text: subtitle, keyword: trimmedKeyword, font: .caption, color: .secondary, lineLimit: subtitleLineLimit)
            }
        }
    }

    private func rememberSearch() {
        let term = trimmedKeyword
        guard !term.isEmpty else { return }
        var items = recentKeywords.filter { $0 != term }
        items.insert(term, at: 0)
        recentKeywordsRaw = items.prefix(8).joined(separator: "\n")
    }

    private func refreshSearchIndex() {
        indexCache = GlobalSearchIndexCache(store: store)
    }

    private func scheduleSearch(immediate: Bool = false) {
        let term = trimmedKeyword
        searchTask?.cancel()
        guard !term.isEmpty else {
            results = GlobalSearchResults()
            isSearching = false
            return
        }
        if indexCache == nil {
            refreshSearchIndex()
        }
        let cache = indexCache
        isSearching = true
        searchTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(180))
            }
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .userInitiated) {
                cache?.search(keyword: term) ?? GlobalSearchResults()
            }.value
            guard !Task.isCancelled else { return }
            // 如果用户已继续输入新关键词，丢弃旧结果，避免结果闪回。
            guard term == trimmedKeyword else { return }
            results = found
            isSearching = false
        }
    }
}

private struct GlobalSearchResults {
    var projects: [Project] = []
    var contacts: [ContactMatch] = []
    var financialRecords: [FinancialMatch] = []
    var logs: [LogMatch] = []
    var documents: [DocumentMatch] = []
    var todos: [TodoMatch] = []
    var materials: [MaterialMatch] = []
    var quotes: [QuoteMatch] = []
    var laborRecords: [LaborMatch] = []
    var quickNotes: [QuickNoteMatch] = []
    var materialPrices: [MaterialPriceEntry] = []
    var suppliers: [SupplierProfile] = []
    var constructionMethods: [ConstructionMethod] = []
    var quoteTemplates: [ProjectTemplate] = []

    var isEmpty: Bool {
        projects.isEmpty
            && contacts.isEmpty
            && financialRecords.isEmpty
            && logs.isEmpty
            && documents.isEmpty
            && todos.isEmpty
            && materials.isEmpty
            && quotes.isEmpty
            && laborRecords.isEmpty
            && quickNotes.isEmpty
            && materialPrices.isEmpty
            && suppliers.isEmpty
            && constructionMethods.isEmpty
            && quoteTemplates.isEmpty
    }

    func filtered(by scope: GlobalSearchScope) -> GlobalSearchResults {
        switch scope {
        case .all:
            return self
        case .projects:
            var scoped = GlobalSearchResults()
            scoped.projects = projects
            return scoped
        case .contacts:
            var scoped = GlobalSearchResults()
            scoped.contacts = contacts
            return scoped
        case .finance:
            var scoped = GlobalSearchResults()
            scoped.financialRecords = financialRecords
            return scoped
        case .documents:
            var scoped = GlobalSearchResults()
            scoped.documents = documents
            return scoped
        case .logs:
            var scoped = GlobalSearchResults()
            scoped.logs = logs
            return scoped
        case .todos:
            var scoped = GlobalSearchResults()
            scoped.todos = todos
            return scoped
        case .records:
            var scoped = GlobalSearchResults()
            scoped.materials = materials
            scoped.quotes = quotes
            scoped.laborRecords = laborRecords
            return scoped
        case .quickNotes:
            var scoped = GlobalSearchResults()
            scoped.quickNotes = quickNotes
            return scoped
        case .database:
            var scoped = GlobalSearchResults()
            scoped.materialPrices = materialPrices
            scoped.suppliers = suppliers
            scoped.constructionMethods = constructionMethods
            scoped.quoteTemplates = quoteTemplates
            return scoped
        }
    }

    func limited(to count: Int) -> GlobalSearchResults {
        var copy = self
        copy.projects = Array(projects.prefix(count))
        copy.contacts = Array(contacts.prefix(count))
        copy.financialRecords = Array(financialRecords.prefix(count))
        copy.logs = Array(logs.prefix(count))
        copy.documents = Array(documents.prefix(count))
        copy.todos = Array(todos.prefix(count))
        copy.materials = Array(materials.prefix(count))
        copy.quotes = Array(quotes.prefix(count))
        copy.laborRecords = Array(laborRecords.prefix(count))
        copy.quickNotes = Array(quickNotes.prefix(count))
        copy.materialPrices = Array(materialPrices.prefix(count))
        copy.suppliers = Array(suppliers.prefix(count))
        copy.constructionMethods = Array(constructionMethods.prefix(count))
        copy.quoteTemplates = Array(quoteTemplates.prefix(count))
        return copy
    }
}

private enum GlobalSearchScope: String, CaseIterable {
    case all
    case projects
    case contacts
    case finance
    case documents
    case logs
    case todos
    case records
    case quickNotes
    case database

    var title: String {
        switch self {
        case .all: return "全部"
        case .projects: return "项目"
        case .contacts: return "联系人"
        case .finance: return "财务"
        case .documents: return "资料"
        case .logs: return "日志"
        case .todos: return "待办"
        case .records: return "清单"
        case .quickNotes: return "随手记"
        case .database: return "数据库"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "line.3.horizontal.decrease.circle"
        case .projects: return "building.2"
        case .contacts: return "person.crop.rectangle.stack"
        case .finance: return "receipt"
        case .documents: return "doc.text"
        case .logs: return "book.pages"
        case .todos: return "checklist"
        case .records: return "list.bullet.rectangle"
        case .quickNotes: return "text.bubble"
        case .database: return "books.vertical"
        }
    }
}

private struct SearchScopeChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? .white : .primary)
                .background(Capsule().fill(isSelected ? Color.orange : Color(uiColor: .secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }
}

private struct GlobalSearchIndexCache {
    private let keywordProjectMap: [UUID: Project]
    private let projects: [Project]
    private let contacts: [ProjectContact]
    private let financialRecords: [ProjectFinancialRecord]
    private let logs: [DailyLog]
    private let documents: [ProjectDocument]
    private let todos: [SiteTodo]
    private let materials: [MaterialItem]
    private let quotes: [QuoteItem]
    private let laborRecords: [LaborRecord]
    private let quickNotes: [QuickNote]
    private let materialPrices: [MaterialPriceEntry]
    private let suppliers: [SupplierProfile]
    private let constructionMethods: [ConstructionMethod]
    private let quoteTemplates: [ProjectTemplate]

    @MainActor
    init(store: DataStore) {
        projects = store.projects
        keywordProjectMap = Dictionary(uniqueKeysWithValues: store.projects.map { ($0.id, $0) })
        contacts = store.projectContacts
        financialRecords = store.projectFinancialRecords
        logs = store.dailyLogs
        documents = store.projectDocuments
        todos = store.siteTodos
        materials = store.materialItems
        quotes = store.quoteItems
        laborRecords = store.laborRecords
        quickNotes = store.quickNotes
        materialPrices = store.materialPriceEntries
        suppliers = store.supplierProfiles
        constructionMethods = store.constructionMethods
        quoteTemplates = store.templates.filter { $0.category == .quotation }
    }

    func search(keyword rawKeyword: String) -> GlobalSearchResults {
        let keyword = rawKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return GlobalSearchResults() }

        return GlobalSearchResults(
            projects: sorted(projects.filter { project in
                matches([project.name, project.location, project.customerName, project.customerPhone, project.managerName, project.status, project.startDate, project.expectedEndDate], keyword: keyword)
            }, keyword: keyword) { [$0.name, $0.location, $0.customerName, $0.customerPhone] },
            contacts: sorted(contacts.compactMap { contact in
                let project = keywordProjectMap[contact.projectId]
                let fields = [contact.name, contact.role, contact.phone, contact.company, contact.note, project?.name ?? ""]
                guard matches(fields, keyword: keyword) else { return nil }
                return ContactMatch(contact: contact, project: project)
            }, keyword: keyword) { [$0.contact.name, $0.contact.phone, $0.contact.company, $0.project?.name ?? ""] },
            financialRecords: sorted(financialRecords.compactMap { record in
                let project = keywordProjectMap[record.projectId]
                let fields = [record.invoiceNumber, record.counterparty, record.note, record.category, record.direction, record.date, record.amount, project?.name ?? ""]
                guard matches(fields, keyword: keyword) else { return nil }
                return FinancialMatch(record: record, project: project)
            }, keyword: keyword, tieBreak: { lhs, rhs in
                lhs.record.date > rhs.record.date
            }) { [$0.record.invoiceNumber, $0.record.counterparty, $0.record.note, $0.project?.name ?? ""] },
            logs: sorted(logs.compactMap { log in
                let project = log.projectId.flatMap { keywordProjectMap[$0] }
                let fields = [log.date, log.weather, log.workers, log.content, log.safety, log.materials, log.qualityIssue, log.tomorrowPlan, log.rectification, log.confirmer, project?.name ?? ""]
                guard matches(fields, keyword: keyword) else { return nil }
                return LogMatch(log: log, project: project)
            }, keyword: keyword, tieBreak: { lhs, rhs in
                lhs.log.date > rhs.log.date
            }) { [$0.log.content, $0.log.date, $0.project?.name ?? ""] },
            documents: sorted(documents.compactMap { document in
                let project = keywordProjectMap[document.projectId]
                let fields = [document.title, document.category, document.amount, document.createdAt, document.note, project?.name ?? ""]
                guard matches(fields, keyword: keyword) else { return nil }
                return DocumentMatch(document: document, project: project)
            }, keyword: keyword, tieBreak: { lhs, rhs in
                lhs.document.createdAt > rhs.document.createdAt
            }) { [$0.document.title, $0.document.category, $0.project?.name ?? ""] },
            todos: sorted(todos.compactMap { todo in
                let project = todo.projectId.flatMap { keywordProjectMap[$0] }
                let fields = [todo.title, todo.owner, todo.dueDate, todo.completedAt ?? "", todo.priority, todo.issueType, todo.note, project?.name ?? ""]
                guard matches(fields, keyword: keyword) else { return nil }
                return TodoMatch(todo: todo, project: project)
            }, keyword: keyword, tieBreak: { lhs, rhs in
                lhs.todo.dueDate > rhs.todo.dueDate
            }) { [$0.todo.title, $0.todo.owner, $0.project?.name ?? ""] },
            materials: sorted(materials.compactMap { item in
                let project = item.projectId.flatMap { keywordProjectMap[$0] }
                let fields = [item.name, item.quantity, item.unit, item.unitPrice, item.specification, item.brand, item.supplier, item.purchaseStatus, item.arrivalDate, project?.name ?? ""]
                guard matches(fields, keyword: keyword) else { return nil }
                return MaterialMatch(item: item, project: project)
            }, keyword: keyword) { [$0.item.name, $0.item.specification, $0.item.brand, $0.item.supplier, $0.project?.name ?? ""] },
            quotes: sorted(quotes.compactMap { item in
                let project = item.projectId.flatMap { keywordProjectMap[$0] }
                let fields = [item.name, item.quantity, item.unit, item.unitPrice, item.notes, item.versionName, item.status, item.customerConfirmedDate, item.contractAmount, project?.name ?? ""]
                guard matches(fields, keyword: keyword) else { return nil }
                return QuoteMatch(item: item, project: project)
            }, keyword: keyword) { [$0.item.name, $0.item.versionName, $0.item.status, $0.project?.name ?? ""] },
            laborRecords: sorted(laborRecords.compactMap { item in
                let project = item.projectId.flatMap { keywordProjectMap[$0] }
                let fields = [item.date, item.workers, item.hours, item.unitRate, item.workType, item.teamName, item.note, project?.name ?? ""]
                guard matches(fields, keyword: keyword) else { return nil }
                return LaborMatch(item: item, project: project)
            }, keyword: keyword) { [$0.item.workType, $0.item.teamName, $0.item.date, $0.project?.name ?? ""] },
            quickNotes: sorted(quickNotes.compactMap { note in
                let project = note.projectId.flatMap { keywordProjectMap[$0] }
                let fields = [note.title, note.content, note.createdAt, note.updatedAt, QuickNoteText.attachmentSummary(note.attachments), project?.name ?? ""]
                guard matches(fields, keyword: keyword) else { return nil }
                return QuickNoteMatch(note: note, project: project)
            }, keyword: keyword, tieBreak: { lhs, rhs in
                lhs.note.createdAt > rhs.note.createdAt
            }) { [$0.note.title, $0.note.content, $0.project?.name ?? ""] },
            materialPrices: sorted(materialPrices.filter { item in
                matches([item.name, item.specification, item.brand, item.unit, item.referencePrice, item.supplier, item.category, item.note], keyword: keyword)
            }, keyword: keyword, tieBreak: { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }) { [$0.name, $0.specification, $0.brand, $0.supplier] },
            suppliers: sorted(suppliers.filter { item in
                matches([item.name, item.category, item.contact, item.phone, item.address, item.note], keyword: keyword)
            }, keyword: keyword, tieBreak: { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }) { [$0.name, $0.contact, $0.phone, $0.category] },
            constructionMethods: sorted(constructionMethods.filter { item in
                matches([item.title, item.trade, item.steps, item.qualityStandard, item.safetyNotes], keyword: keyword)
            }, keyword: keyword, tieBreak: { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }) { [$0.title, $0.trade, $0.qualityStandard] },
            quoteTemplates: sorted(quoteTemplates.filter { item in
                matches([item.name, item.content], keyword: keyword)
            }, keyword: keyword) { [$0.name, $0.content] }
        )
    }

    private func matches(_ fields: [String], keyword: String) -> Bool {
        fields.contains { $0.localizedStandardContains(keyword) }
    }

    private func sorted<T>(
        _ items: [T],
        keyword: String,
        tieBreak: ((T, T) -> Bool)? = nil,
        fields: (T) -> [String]
    ) -> [T] {
        items.sorted { lhs, rhs in
            let leftScore = score(fields(lhs), keyword: keyword)
            let rightScore = score(fields(rhs), keyword: keyword)
            if leftScore != rightScore { return leftScore < rightScore }
            if let tieBreak {
                let leftFirst = tieBreak(lhs, rhs)
                let rightFirst = tieBreak(rhs, lhs)
                if leftFirst != rightFirst {
                    return leftFirst
                }
            }
            return fields(lhs).joined(separator: " ") < fields(rhs).joined(separator: " ")
        }
    }

    private func score(_ fields: [String], keyword: String) -> Int {
        let q = keyword.lowercased()
        var best = Int.max
        for (index, field) in fields.enumerated() {
            let value = field.lowercased()
            if value == q {
                best = min(best, index)
            } else if value.hasPrefix(q) {
                best = min(best, 20 + index)
            } else if value.contains(q) {
                best = min(best, 60 + index)
            }
        }
        return best
    }
}

private struct HighlightedText: View {
    let text: String
    let keyword: String
    let font: Font
    let color: Color
    var lineLimit: Int? = nil

    var body: some View {
        highlighted
            .font(font)
            .foregroundStyle(color)
            .lineLimit(lineLimit)
    }

    private var highlighted: Text {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Text(text)
        }
        var remaining = text[...]
        var result = Text("")
        var matched = false

        while let range = remaining.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) {
            matched = true
            let prefix = String(remaining[..<range.lowerBound])
            let match = String(remaining[range])
            result = result + Text(prefix) + Text(match).foregroundColor(.orange).bold()
            remaining = remaining[range.upperBound...]
        }
        if !matched {
            return Text(text)
        }
        return result + Text(String(remaining))
    }
}

private struct ContactMatch: Identifiable {
    let contact: ProjectContact
    let project: Project?
    var id: UUID { contact.id }
}

private struct FinancialMatch: Identifiable {
    let record: ProjectFinancialRecord
    let project: Project?
    var id: UUID { record.id }
}

private struct LogMatch: Identifiable {
    let log: DailyLog
    let project: Project?
    var id: UUID { log.id }
}

private struct DocumentMatch: Identifiable {
    let document: ProjectDocument
    let project: Project?
    var id: UUID { document.id }
}

private struct TodoMatch: Identifiable {
    let todo: SiteTodo
    let project: Project?
    var id: UUID { todo.id }
}

private struct MaterialMatch: Identifiable {
    let item: MaterialItem
    let project: Project?
    var id: UUID { item.id }
}

private struct QuoteMatch: Identifiable {
    let item: QuoteItem
    let project: Project?
    var id: UUID { item.id }
}

private struct LaborMatch: Identifiable {
    let item: LaborRecord
    let project: Project?
    var id: UUID { item.id }
}

private struct QuickNoteMatch: Identifiable {
    let note: QuickNote
    let project: Project?
    var id: UUID { note.id }
}
