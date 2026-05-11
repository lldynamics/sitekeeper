import SwiftUI

struct ProjectDocumentsView: View {
    let documents: [ProjectDocument]
    let financialRecords: [ProjectFinancialRecord]
    let icon: (ProjectDocumentCategory) -> String
    let onOpen: (ProjectDocument) -> Void
    let onLink: (UUID, UUID) -> Void
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
            guard document.linkedFinancialRecordId == nil,
                  let record = bestMatch(for: document) else { return nil }
            return DocumentFinancialMatch(document: document, record: record)
        }
    }

    var body: some View {
        Group {
            Section("资料筛选") {
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

            Section("票据与项目资料 (\(filteredDocuments.count))") {
                if filteredDocuments.isEmpty {
                    ContentUnavailableView(
                        "暂无扫描件",
                        systemImage: "doc.viewfinder",
                        description: Text("扫描票据或导入资料后可与财务流水关联。")
                    )
                } else {
                    if !suggestedMatches.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.tight) {
                            Label("缺票自动匹配建议", systemImage: "wand.and.stars")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
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
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange)
                                    .font(.caption2.weight(.semibold))
                                }
                            }
                        }
                        .padding(AppSpacing.tight)
                        .background(
                            RoundedRectangle(cornerRadius: AppSpacing.tight, style: .continuous)
                                .fill(Color.orange.opacity(0.08))
                        )
                    }
                    ForEach(filteredDocuments) { document in
                        Button {
                            onOpen(document)
                        } label: {
                            HStack(spacing: AppSpacing.normal) {
                                Image(systemName: icon(document.category))
                                    .foregroundStyle(.indigo)
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

    private func bestMatch(for document: ProjectDocument) -> ProjectFinancialRecord? {
        let docAmount = document.amountValue.doubleValue
        let docDate = parseDate(document.createdAt)
        let docCategory = document.category
        let docText = [document.title, document.note]
            .joined(separator: " ")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let candidates = financialRecords.compactMap { record -> (ProjectFinancialRecord, Int)? in
            var score = 0
            let recordAmount = record.amountValue.doubleValue
            let amountDelta = abs(recordAmount - docAmount)
            if docAmount > 0 {
                if amountDelta <= 1 {
                    score += 4
                } else if amountDelta <= max(1, docAmount * 0.02) {
                    score += 3
                } else if amountDelta <= max(2, docAmount * 0.05) {
                    score += 1
                }
            }

            if let docDate, let recordDate = parseDate(record.date) {
                let dayDelta = abs(Calendar.current.dateComponents([.day], from: docDate, to: recordDate).day ?? 99)
                if dayDelta <= 3 {
                    score += 2
                } else if dayDelta <= 7 {
                    score += 1
                }
            }

            let counterparty = record.counterparty.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !counterparty.isEmpty && docText.contains(counterparty) {
                score += 2
            }

            if docCategory.matchesFinancialCategory(record.category) {
                score += 1
            }

            return score >= 3 ? (record, score) : nil
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.date > rhs.0.date
        }
        return candidates.first?.0
    }
}

private enum DocumentCategoryFilter: String, CaseIterable {
    case all = "全部"
    case invoice = "发票"
    case receipt = "收据"
    case construction = "施工资料"

    var displayName: String { rawValue }

    func matches(_ document: ProjectDocument) -> Bool {
        switch self {
        case .all:
            return true
        case .invoice:
            return document.category == .invoice
        case .receipt:
            return document.category == .receipt
        case .construction:
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

private struct DocumentFinancialMatch: Identifiable {
    let id = UUID()
    let document: ProjectDocument
    let record: ProjectFinancialRecord
}

private extension ProjectDocumentCategory {
    func matchesFinancialCategory(_ category: ProjectFinancialCategory) -> Bool {
        switch self {
        case .invoice:
            return category == .invoice
        case .receipt:
            return category == .receipt
        case .paymentRequest:
            return category == .paymentRequest
        case .construction:
            return category == .material
                || category == .labor
        case .contract, .acceptance, .other:
            return false
        }
    }
}
