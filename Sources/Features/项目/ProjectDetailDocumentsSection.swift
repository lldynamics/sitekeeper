import SwiftUI

struct ProjectDocumentsView: View {
    let documents: [ProjectDocument]
    let requiredCategories: [ProjectDocumentCategory]
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

    var body: some View {
        Group {
            checklistSection

            if !documents.isEmpty || hasActiveFilters {
                Section {
                    Button {
                        showFilterSheet = true
                    } label: {
                        HStack {
                            Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                            Spacer()
                            Text(filterSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if hasActiveFilters {
                        Button("清除筛选") {
                            resetFilters()
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }

            Section("资料 (\(filteredDocuments.count))") {
                if filteredDocuments.isEmpty {
                    ProjectInlineEmptyState(
                        documents.isEmpty ? "还没有资料" : "没有匹配资料",
                        systemImage: "doc.viewfinder",
                        detail: documents.isEmpty ? "扫描票据或导入资料后可关联账目。" : "调整筛选条件后再看。"
                    )
                } else {
                    if !suggestedMatches.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.tight) {
                            Label("缺票自动匹配建议", systemImage: "wand.and.stars")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.appWarning)
                            ForEach(suggestedMatches) { match in
                                HStack(alignment: .top, spacing: AppSpacing.tight) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(match.document.title)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        Text("\(match.record.date) · \(match.record.counterparty.isEmpty ? "未填写单位" : match.record.counterparty)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text("建议关联 \(ReportBuilder.money(match.record.amountValue.doubleValue))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("关联") {
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
                                        Text("\(document.pageCount) 页")
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
                                        Text("工艺: \(linkedTitles.joined(separator: "、"))")
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
                .navigationTitle("资料筛选")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("重置") {
                            resetFilters()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            showFilterSheet = false
                        }
                    }
                    KeyboardDismissToolbar {
                        AppKeyboard.dismiss()
                    }
                }
            }
        }
    }

    @State private var showFilterSheet = false

    private var checklistSection: some View {
        let snapshot = checklistSnapshot
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
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                if snapshot.legacyDocumentCount > 0 {
                    Text(String(format: String(localized: "旧类资料 %lld 份待细分"), Int64(snapshot.legacyDocumentCount)))
                        .font(.caption2)
                        .foregroundStyle(Color.appWarning)
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
        }
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
        Section("类型") {
            Picker("资料类型", selection: $categoryFilter) {
                ForEach(DocumentCategoryFilter.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
            Picker("关联状态", selection: $relationFilter) {
                ForEach(DocumentRelationFilter.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
        }
        Section("日期") {
            Toggle("限定日期范围", isOn: $useDateRange)
            if useDateRange {
                DatePicker("开始", selection: $startDate, displayedComponents: .date)
                DatePicker("结束", selection: $endDate, displayedComponents: .date)
            }
        }
        Section("金额") {
            LabeledContent("最小金额") {
                TextField("0", text: $minAmount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("最大金额") {
                TextField("不限", text: $maxAmount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var hasActiveFilters: Bool {
        categoryFilter != .all || relationFilter != .all || useDateRange || !minAmount.isEmpty || !maxAmount.isEmpty
    }

    private var filterSummary: String {
        guard hasActiveFilters else { return "全部资料" }
        var parts: [String] = []
        if categoryFilter != .all { parts.append(categoryFilter.displayName) }
        if relationFilter != .all { parts.append(relationFilter.displayName) }
        if useDateRange { parts.append("日期") }
        if !minAmount.isEmpty || !maxAmount.isEmpty { parts.append("金额") }
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

    private func linkedMethodTitles(for document: ProjectDocument) -> [String] {
        guard !document.linkedConstructionMethodIDs.isEmpty else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: constructionMethods.map { method in
            (method.id, methodTitle(method))
        })
        return document.linkedConstructionMethodIDs.compactMap { lookup[$0] }
    }

    private func documentRegisterSummary(for document: ProjectDocument) -> String {
        [
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
        let displayTitle = title.isEmpty ? "未命名工艺" : title
        return trade.isEmpty ? displayTitle : "\(trade) · \(displayTitle)"
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
    case all = "全部"
    case constructionArchive = "全部施工资料"
    case constructionTechnical = "施工技术"
    case constructionMaterial = "施工物资"
    case constructionSurvey = "施工测量"
    case constructionRecord = "施工记录"
    case constructionTest = "施工试验"
    case constructionManagement = "施工管理"
    case processAcceptance = "过程验收"
    case completionAcceptance = "竣工验收"
    case businessArchive = "商务/财务"
    case invoice = "发票"
    case receipt = "收据"
    case legacyConstruction = "施工资料"

    var displayName: String { rawValue }

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
        case .construction:
            self = .legacyConstruction
        case .paymentRequest, .contract, .acceptance, .other:
            self = .all
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
        case .invoice:
            return document.category == .invoice
        case .receipt:
            return document.category == .receipt
        case .legacyConstruction:
            return document.category == .construction
        }
    }
}

private enum DocumentRelationFilter: String, CaseIterable {
    case all = "全部"
    case linked = "已关联账目"
    case unlinked = "未关联账目"

    var displayName: String { rawValue }

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
