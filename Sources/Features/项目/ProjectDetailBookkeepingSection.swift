import SwiftUI

struct ProjectBookkeepingView: View {
    let records: [ProjectFinancialRecord]
    let supplierProfiles: [SupplierProfile]
    let projectContacts: [ProjectContact]
    let projects: [Project]
    let allFinancialRecords: [ProjectFinancialRecord]
    let allProjectDocuments: [ProjectDocument]
    let projectCustomerName: String
    let linkedDocuments: (ProjectFinancialRecord) -> [ProjectDocument]
    let onEdit: (ProjectFinancialRecord) -> Void
    let onDelete: (Set<UUID>) -> Void
    let onAddRecord: () -> Void
    let quickFilter: ProjectFinanceJumpFilter
    let onResetQuickFilter: () -> Void

    @State private var directionFilter: BookDirectionFilter = .all
    @State private var categoryFilter: BookCategoryFilter = .all
    @State private var attachmentFilter: BookAttachmentFilter = .all
    @State private var outstandingFilter: BookOutstandingFilter = .all
    @State private var useDateRange = false
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()

    var body: some View {
        Group {
            Section(String(localized: "成本汇总")) {
                Button {
                    onAddRecord()
                } label: {
                    Label(String(localized: "记账"), systemImage: "plus.circle.fill")
                }
                LabeledContent(String(localized: "收入"), value: ReportBuilder.money(totalIncome))
                LabeledContent(String(localized: "支出"), value: ReportBuilder.money(totalExpense))
                LabeledContent(String(localized: "净额"), value: ReportBuilder.money(totalIncome - totalExpense))
                LabeledContent(String(localized: "未附票据"), value: String(format: String(localized: "%lld 笔"), Int64(unattachedCount)))
            }

            Section(String(localized: "往来单位")) {
                if counterpartySummaries.isEmpty {
                    ProjectInlineEmptyState(String(localized: "还没有往来单位"), systemImage: "person.2")
                } else {
                    ForEach(counterpartySummaries) { summary in
                        NavigationLink {
                            BookCounterpartyDetailView(
                                summary: summary,
                                records: counterpartyRecords(for: summary.name),
                                projectsByID: projectNameByID,
                                suppliers: matchingSuppliers(for: summary.name),
                                contacts: matchingContacts(for: summary.name),
                                hasLinkedDocument: hasLinkedDocument(_:),
                                onEdit: onEdit
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: AppSpacing.tight) {
                                    Text(summary.name)
                                        .font(.callout.weight(.medium))
                                    Text(summary.kind.displayName)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(summary.kind.tint)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(summary.kind.tint.opacity(0.14), in: Capsule())
                                    Spacer()
                                    Text(String(format: String(localized: "净额 %@"), ReportBuilder.money(summary.netOutstandingAmount)))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(summary.netOutstandingAmount >= 0 ? Color.appSuccess : Color.appRisk)
                                }
                                HStack(spacing: AppSpacing.tight) {
                                    Text(String(format: String(localized: "应收 %@"), ReportBuilder.money(summary.receivableAmount)))
                                        .foregroundStyle(Color.appSuccess)
                                    Text(String(format: String(localized: "应付 %@"), ReportBuilder.money(summary.payableAmount)))
                                        .foregroundStyle(Color.appRisk)
                                    if summary.unsettledCount > 0 {
                                        Text(String(format: String(localized: "未结清 %lld 笔"), Int64(summary.unsettledCount)))
                                            .foregroundStyle(Color.appWarning)
                                    }
                                    if summary.missingReceiptCount > 0 {
                                        Text(String(format: String(localized: "缺票 %lld 笔"), Int64(summary.missingReceiptCount)))
                                            .foregroundStyle(Color.appFinance)
                                    }
                                }
                                .font(.caption2)
                                HStack(spacing: AppSpacing.tight) {
                                    Text(String(format: String(localized: "累计收入 %@"), ReportBuilder.money(summary.incomeAmount)))
                                        .foregroundStyle(.secondary)
                                    Text(String(format: String(localized: "累计支出 %@"), ReportBuilder.money(summary.expenseAmount)))
                                        .foregroundStyle(.secondary)
                                }
                                .font(.caption2)
                                counterpartyMatchStrip(match: summary.match)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section(String(format: String(localized: "未结清 (%lld)"), Int64(unsettledRecords.count))) {
                if unsettledRecords.isEmpty {
                    ProjectInlineEmptyState(String(localized: "没有未结清记录"), systemImage: "checkmark.seal")
                } else {
                    ForEach(unsettledRecords) { record in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(record.date)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(record.dueDate)
                                    .font(.caption2)
                                    .foregroundStyle(Color.appWarning)
                            }
                            HStack(spacing: AppSpacing.tight) {
                                Text(counterpartyDisplayName(record.counterparty))
                                Text(record.normalizedDirection.displayName)
                                    .foregroundStyle(record.normalizedDirection == .income ? Color.appSuccess : .appRisk)
                                Text(ReportBuilder.money(record.amountValue.doubleValue))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            counterpartyMatchStrip(match: counterpartyMatch(for: record.counterparty))
                        }
                    }
                }
            }

            if let quickFilterLabel {
                Section(String(localized: "快速筛选")) {
                    HStack {
                        Text(String(format: String(localized: "当前: %@"), quickFilterLabel))
                        Spacer()
                        Button(String(localized: "清除")) {
                            resetToDefaultFilters()
                            onResetQuickFilter()
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }

            if !records.isEmpty {
                Section(String(localized: "筛选")) {
                    Picker(String(localized: "收支"), selection: $directionFilter) {
                        ForEach(BookDirectionFilter.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker(String(localized: "票据类型"), selection: $categoryFilter) {
                        ForEach(BookCategoryFilter.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Picker(String(localized: "票据附件"), selection: $attachmentFilter) {
                        ForEach(BookAttachmentFilter.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Picker(String(localized: "状态"), selection: $outstandingFilter) {
                        ForEach(BookOutstandingFilter.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Toggle(String(localized: "限定日期范围"), isOn: $useDateRange)
                    if useDateRange {
                        DatePicker(String(localized: "开始"), selection: $startDate, displayedComponents: .date)
                        DatePicker(String(localized: "结束"), selection: $endDate, displayedComponents: .date)
                    }
                }
            }

            Section(String(format: String(localized: "流水 (%lld)"), Int64(filteredRecords.count))) {
                if filteredRecords.isEmpty {
                    ProjectInlineEmptyState(
                        records.isEmpty ? String(localized: "还没有账目") : String(localized: "没有匹配账目"),
                        systemImage: "tray",
                        detail: records.isEmpty ? String(localized: "先记一笔收入或支出。") : String(localized: "调整筛选条件或新增一笔。")
                    )
                } else {
                    ForEach(filteredRecords) { record in
                        Button {
                            onEdit(record)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(record.date).font(.callout.weight(.medium))
                                    Text(record.category.displayName)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(record.direction.displayName) \(ReportBuilder.money(record.amountValue.doubleValue))")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(record.isIncomeDirection ? Color.appSuccess : .appRisk)
                                }
                                HStack(spacing: AppSpacing.tight) {
                                    if !record.counterparty.isEmpty { Text(record.counterparty) }
                                    if !record.invoiceNumber.isEmpty {
                                        Text(String(format: String(localized: "票号 %@"), record.invoiceNumber))
                                    }
                                    if !linkedDocuments(record).isEmpty {
                                        Text(String(format: String(localized: "已附票据%lld"), Int64(linkedDocuments(record).count)))
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                if !record.note.isEmpty {
                                    Text(record.note).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let ids = offsets.compactMap { filteredRecords.indices.contains($0) ? filteredRecords[$0].id : nil }
                        onDelete(Set(ids))
                    }
                }
            }
        }
        .onAppear {
            applyQuickFilter(quickFilter)
        }
        .onChange(of: quickFilter) { _, newValue in
            applyQuickFilter(newValue)
        }
    }

    private var filteredRecords: [ProjectFinancialRecord] {
        records.filter { record in
            if !directionFilter.matches(record) { return false }
            if !categoryFilter.matches(record) { return false }
            if !attachmentFilter.matches(record, linkedDocuments: linkedDocuments) { return false }
            if !outstandingFilter.matches(record) { return false }
            if useDateRange {
                guard let date = Formatters.date.date(from: record.date) else { return false }
                let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
                if date < startDate || date > endOfDay { return false }
            }
            return true
        }
    }

    private var totalIncome: Double {
        records
            .filter(\.isIncomeDirection)
            .reduce(MoneyValue.zero) { $0 + $1.amountValue }
            .doubleValue
    }

    private var totalExpense: Double {
        records
            .filter(\.isExpenseDirection)
            .reduce(MoneyValue.zero) { $0 + $1.amountValue }
            .doubleValue
    }

    private var unattachedCount: Int {
        records.filter { $0.requiresAttachment && linkedDocuments($0).isEmpty }.count
    }

    private var projectNameByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
    }

    private var counterpartySummaries: [BookCounterpartySummary] {
        let grouped = Dictionary(grouping: records) { record in
            counterpartyDisplayName(record.counterparty)
        }
        let matchLookup = grouped.keys.reduce(into: [String: BookCounterpartyMatch]()) { result, name in
            result[name] = counterpartyMatch(for: name)
        }
        return grouped.map { name, rows in
            let income = rows
                .filter { $0.normalizedDirection == .income }
                .reduce(MoneyValue.zero) { $0 + $1.amountValue }
                .doubleValue
            let expense = rows
                .filter { $0.normalizedDirection == .expense }
                .reduce(MoneyValue.zero) { $0 + $1.amountValue }
                .doubleValue
            let unsettledRows = rows.filter(isUnsettled)
            let unsettled = unsettledRows.count
            let receivable = unsettledRows
                .filter { $0.normalizedDirection == .income }
                .reduce(MoneyValue.zero) { $0 + $1.amountValue }
                .doubleValue
            let payable = unsettledRows
                .filter { $0.normalizedDirection == .expense }
                .reduce(MoneyValue.zero) { $0 + $1.amountValue }
                .doubleValue
            let missingReceipts = rows.filter(isMissingReceipt).count
            let match = matchLookup[name] ?? .none
            return BookCounterpartySummary(
                name: name,
                incomeAmount: income,
                expenseAmount: expense,
                receivableAmount: receivable,
                payableAmount: payable,
                unsettledCount: unsettled,
                missingReceiptCount: missingReceipts,
                match: match,
                kind: counterpartyKind(for: name, match: match)
            )
        }
        .sorted { lhs, rhs in
            if lhs.unsettledCount != rhs.unsettledCount {
                return lhs.unsettledCount > rhs.unsettledCount
            }
            if lhs.missingReceiptCount != rhs.missingReceiptCount {
                return lhs.missingReceiptCount > rhs.missingReceiptCount
            }
            if lhs.totalOutstandingAmount != rhs.totalOutstandingAmount {
                return lhs.totalOutstandingAmount > rhs.totalOutstandingAmount
            }
            if lhs.turnoverAmount != rhs.turnoverAmount {
                return lhs.turnoverAmount > rhs.turnoverAmount
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var unsettledRecords: [ProjectFinancialRecord] {
        records
            .filter(isUnsettled)
            .sorted {
                if $0.dueDate != $1.dueDate { return $0.dueDate < $1.dueDate }
                return $0.date > $1.date
            }
    }

    private var quickFilterLabel: String? {
        switch quickFilter {
        case .none:
            return nil
        case .unsettled:
            return String(localized: "应收付")
        case .missingReceipt:
            return String(localized: "缺票")
        }
    }

    private var unfilledCounterpartyName: String {
        String(localized: "未填写单位")
    }

    private func resetToDefaultFilters() {
        directionFilter = .all
        categoryFilter = .all
        attachmentFilter = .all
        outstandingFilter = .all
        useDateRange = false
    }

    private func applyQuickFilter(_ filter: ProjectFinanceJumpFilter) {
        switch filter {
        case .none:
            return
        case .unsettled:
            directionFilter = .all
            categoryFilter = .all
            attachmentFilter = .all
            outstandingFilter = .activeWithDueDate
            useDateRange = false
        case .missingReceipt:
            directionFilter = .all
            categoryFilter = .all
            attachmentFilter = .unattached
            outstandingFilter = .all
            useDateRange = false
        }
    }

    private func isUnsettled(_ record: ProjectFinancialRecord) -> Bool {
        record.normalizedStatus == .active
            && !record.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isMissingReceipt(_ record: ProjectFinancialRecord) -> Bool {
        record.requiresAttachment && linkedDocuments(record).isEmpty
    }

    private func hasLinkedDocument(_ record: ProjectFinancialRecord) -> Bool {
        if !record.linkedDocumentIds.isEmpty {
            return true
        }
        return allProjectDocuments.contains { $0.linkedFinancialRecordId == record.id }
    }

    private func counterpartyDisplayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? unfilledCounterpartyName : trimmed
    }

    private func counterpartyRecords(for name: String) -> [ProjectFinancialRecord] {
        allFinancialRecords.filter { counterpartyDisplayName($0.counterparty) == name }
    }

    private func matchingSuppliers(for name: String) -> [SupplierProfile] {
        let source = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, source != unfilledCounterpartyName else { return [] }
        return supplierProfiles
            .filter { supplier in
                isLooseCounterpartyMatch(source, supplier.name)
                    || isLooseCounterpartyMatch(source, supplier.contact)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func matchingContacts(for name: String) -> [ProjectContact] {
        let source = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, source != unfilledCounterpartyName else { return [] }
        return projectContacts
            .filter { contact in
                isLooseCounterpartyMatch(source, contact.company)
                    || isLooseCounterpartyMatch(source, contact.name)
            }
            .sorted { lhs, rhs in
                if lhs.role != rhs.role {
                    return lhs.roleDisplayName.localizedStandardCompare(rhs.roleDisplayName) == .orderedAscending
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func counterpartyMatch(for rawName: String) -> BookCounterpartyMatch {
        let source = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, source != unfilledCounterpartyName else {
            return .none
        }
        let supplier = supplierProfiles.first { supplier in
            isLooseCounterpartyMatch(source, supplier.name)
        }
        let contact = projectContacts.first { contact in
            isLooseCounterpartyMatch(source, contact.company)
                || isLooseCounterpartyMatch(source, contact.name)
        }
        return BookCounterpartyMatch(supplier: supplier, contact: contact)
    }

    private func counterpartyKind(for name: String, match: BookCounterpartyMatch) -> BookCounterpartyKind {
        if match.supplier != nil {
            return .supplier
        }
        if let contact = match.contact {
            switch contact.normalizedRole {
            case .supplier:
                return .supplier
            case .team:
                return .team
            case .customer, .owner:
                return .customer
            case .supervisor, .other:
                return .other
            }
        }
        let customer = projectCustomerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customer.isEmpty, isLooseCounterpartyMatch(name, customer) {
            return .customer
        }
        return .other
    }

    private func isLooseCounterpartyMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right || left.contains(right) || right.contains(left)
    }

    @ViewBuilder
    private func counterpartyMatchStrip(match: BookCounterpartyMatch) -> some View {
        if !match.isEmpty {
            HStack(spacing: AppSpacing.tight) {
                if let supplier = match.supplier {
                    Label(supplier.name, systemImage: "building.2.fill")
                        .foregroundStyle(Color.appWarning)
                }
                if let contact = match.contact {
                    NavigationLink {
                        ProjectContactDatabaseView(focusedContactId: contact.id)
                    } label: {
                        Label(
                            contact.company.isEmpty ? contact.name : "\(contact.company) · \(contact.name)",
                            systemImage: "person.crop.circle.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appDoc)
                }
            }
            .font(.caption2)
        }
    }
}

private struct BookCounterpartySummary: Identifiable {
    var id: String { name }
    let name: String
    let incomeAmount: Double
    let expenseAmount: Double
    let receivableAmount: Double
    let payableAmount: Double
    let unsettledCount: Int
    let missingReceiptCount: Int
    let match: BookCounterpartyMatch
    let kind: BookCounterpartyKind

    var netOutstandingAmount: Double { receivableAmount - payableAmount }
    var totalOutstandingAmount: Double { receivableAmount + payableAmount }
    var turnoverAmount: Double { incomeAmount + expenseAmount }
}

private struct BookCounterpartyMatch {
    let supplier: SupplierProfile?
    let contact: ProjectContact?

    static let none = BookCounterpartyMatch(supplier: nil, contact: nil)

    var isEmpty: Bool {
        supplier == nil && contact == nil
    }
}

private enum BookCounterpartyKind {
    case supplier
    case team
    case customer
    case other

    var displayName: String {
        switch self {
        case .supplier:
            return String(localized: "供应商")
        case .team:
            return String(localized: "班组")
        case .customer:
            return String(localized: "客户")
        case .other:
            return String(localized: "其他")
        }
    }

    var tint: Color {
        switch self {
        case .supplier:
            return .appWarning
        case .team:
            return .appSuccess
        case .customer:
            return .appDoc
        case .other:
            return .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .supplier:
            return "building.2.fill"
        case .team:
            return "person.3.fill"
        case .customer:
            return "person.text.rectangle.fill"
        case .other:
            return "person.crop.circle.fill"
        }
    }
}

private struct BookCounterpartyDetailView: View {
    let summary: BookCounterpartySummary
    let records: [ProjectFinancialRecord]
    let projectsByID: [UUID: String]
    let suppliers: [SupplierProfile]
    let contacts: [ProjectContact]
    let hasLinkedDocument: (ProjectFinancialRecord) -> Bool
    let onEdit: (ProjectFinancialRecord) -> Void

    private var unsettledRecords: [ProjectFinancialRecord] {
        records.filter(isUnsettled)
            .sorted { lhs, rhs in
                if lhs.dueDate != rhs.dueDate {
                    return lhs.dueDate < rhs.dueDate
                }
                return dateSortKey(lhs.date) > dateSortKey(rhs.date)
            }
    }

    private var missingReceiptRecords: [ProjectFinancialRecord] {
        records.filter(isMissingReceipt)
            .sorted { lhs, rhs in
                dateSortKey(lhs.date) > dateSortKey(rhs.date)
            }
    }

    private var receivableAmount: Double {
        unsettledRecords
            .filter { $0.normalizedDirection == .income }
            .reduce(MoneyValue.zero) { $0 + $1.amountValue }
            .doubleValue
    }

    private var payableAmount: Double {
        unsettledRecords
            .filter { $0.normalizedDirection == .expense }
            .reduce(MoneyValue.zero) { $0 + $1.amountValue }
            .doubleValue
    }

    private var missingReceiptCount: Int {
        missingReceiptRecords.count
    }

    private var recentProjectRollups: [BookCounterpartyProjectRollup] {
        let grouped = Dictionary(grouping: records, by: \.projectId)
        return grouped.map { projectId, rows in
            let latestRecord = rows.max { lhs, rhs in
                dateSortKey(lhs.date) < dateSortKey(rhs.date)
            }
            let unsettled = rows.filter(isUnsettled)
            let receivable = unsettled
                .filter { $0.normalizedDirection == .income }
                .reduce(MoneyValue.zero) { $0 + $1.amountValue }
                .doubleValue
            let payable = unsettled
                .filter { $0.normalizedDirection == .expense }
                .reduce(MoneyValue.zero) { $0 + $1.amountValue }
                .doubleValue
            let missing = rows.filter(isMissingReceipt).count
            return BookCounterpartyProjectRollup(
                projectId: projectId,
                projectName: projectsByID[projectId] ?? String(localized: "未知项目"),
                latestDate: latestRecord?.date ?? "",
                receivableAmount: receivable,
                payableAmount: payable,
                unsettledCount: unsettled.count,
                missingReceiptCount: missing
            )
        }
        .sorted { lhs, rhs in
            let lhsDate = dateSortKey(lhs.latestDate)
            let rhsDate = dateSortKey(rhs.latestDate)
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            if lhs.unsettledCount != rhs.unsettledCount {
                return lhs.unsettledCount > rhs.unsettledCount
            }
            return lhs.projectName.localizedStandardCompare(rhs.projectName) == .orderedAscending
        }
    }

    private var recentRecords: [ProjectFinancialRecord] {
        records.sorted { lhs, rhs in
            let lhsDate = dateSortKey(lhs.date)
            let rhsDate = dateSortKey(rhs.date)
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    var body: some View {
        List {
            Section {
                counterpartyHeader
            }

            Section(String(localized: "核心指标")) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.normal) {
                    counterpartyMetricCard(
                        title: String(localized: "应收"),
                        value: ReportBuilder.money(receivableAmount),
                        subtitle: String(format: String(localized: "%lld 笔"), Int64(unsettledRecords.filter(\.isIncomeDirection).count)),
                        tint: .appSuccess
                    )
                    counterpartyMetricCard(
                        title: String(localized: "应付"),
                        value: ReportBuilder.money(payableAmount),
                        subtitle: String(format: String(localized: "%lld 笔"), Int64(unsettledRecords.filter(\.isExpenseDirection).count)),
                        tint: .appRisk
                    )
                    counterpartyMetricCard(
                        title: String(localized: "未结清"),
                        value: String(format: String(localized: "%lld 笔"), Int64(unsettledRecords.count)),
                        subtitle: String(format: String(localized: "合计 %@"), ReportBuilder.money(receivableAmount + payableAmount)),
                        tint: .appWarning
                    )
                    counterpartyMetricCard(
                        title: String(localized: "缺票"),
                        value: String(format: String(localized: "%lld 笔"), Int64(missingReceiptCount)),
                        subtitle: String(localized: "需补票据/资料"),
                        tint: .appFinance
                    )
                }
                LabeledContent(String(localized: "累计收入"), value: ReportBuilder.money(summary.incomeAmount))
                LabeledContent(String(localized: "累计支出"), value: ReportBuilder.money(summary.expenseAmount))
            }

            Section(String(localized: "关联项目")) {
                if recentProjectRollups.isEmpty {
                    Text(String(localized: "暂无项目记录。"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentProjectRollups) { rollup in
                        NavigationLink {
                            ProjectDetailView(projectId: rollup.projectId, initialMode: .finance)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(rollup.projectName)
                                        .font(.callout.weight(.medium))
                                    Spacer()
                                    if !rollup.latestDate.isEmpty {
                                        Text(rollup.latestDate)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                HStack(spacing: AppSpacing.tight) {
                                    Text(String(format: String(localized: "应收 %@"), ReportBuilder.money(rollup.receivableAmount)))
                                        .foregroundStyle(Color.appSuccess)
                                    Text(String(format: String(localized: "应付 %@"), ReportBuilder.money(rollup.payableAmount)))
                                        .foregroundStyle(Color.appRisk)
                                    if rollup.unsettledCount > 0 {
                                        Text(String(format: String(localized: "未结清 %lld"), Int64(rollup.unsettledCount)))
                                            .foregroundStyle(Color.appWarning)
                                    }
                                    if rollup.missingReceiptCount > 0 {
                                        Text(String(format: String(localized: "缺票 %lld"), Int64(rollup.missingReceiptCount)))
                                            .foregroundStyle(Color.appFinance)
                                    }
                                }
                                .font(.caption2)
                            }
                        }
                    }
                }
            }

            Section(String(localized: "关联联系人 / 供应商")) {
                if suppliers.isEmpty && contacts.isEmpty {
                    Text(String(localized: "暂无已关联联系人或供应商。"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(suppliers) { supplier in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(supplier.name)
                                .font(.callout.weight(.medium))
                            Text([supplier.contact, supplier.phone].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(contacts) { contact in
                        NavigationLink {
                            ProjectContactDatabaseView(focusedContactId: contact.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.company.isEmpty ? contact.name : "\(contact.company) · \(contact.name)")
                                    .font(.callout.weight(.medium))
                                Text([contact.roleDisplayName, contact.phone].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section(String(localized: "未结清账目")) {
                if unsettledRecords.isEmpty {
                    Text(String(localized: "暂无未结清账目。"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(unsettledRecords) { record in
                        Button {
                            onEdit(record)
                        } label: {
                            counterpartyRecordRow(record, showsDueDate: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section(String(localized: "缺票记录")) {
                if missingReceiptRecords.isEmpty {
                    Text(String(localized: "暂无缺票记录。"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(missingReceiptRecords) { record in
                        Button {
                            onEdit(record)
                        } label: {
                            counterpartyRecordRow(record, showsDueDate: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section(String(localized: "最近流水")) {
                if recentRecords.isEmpty {
                    Text(String(localized: "暂无流水记录。"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentRecords.prefix(12)) { record in
                        Button {
                            onEdit(record)
                        } label: {
                            counterpartyRecordRow(record, showsDueDate: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(summary.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var counterpartyHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.normal) {
            HStack(spacing: AppSpacing.tight) {
                Image(systemName: summary.kind.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(summary.kind.tint)
                    .frame(width: 34, height: 34)
                    .background(summary.kind.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.name)
                        .font(.headline)
                    Text([
                        summary.kind.displayName,
                        String(format: String(localized: "%lld 个关联项目"), Int64(recentProjectRollups.count)),
                        String(format: String(localized: "%lld 位联系人"), Int64(contacts.count))
                    ].joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: AppSpacing.tight) {
                if !unsettledRecords.isEmpty {
                    Text(String(format: String(localized: "未结清 %lld"), Int64(unsettledRecords.count)))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appWarning, in: Capsule())
                }
                if !missingReceiptRecords.isEmpty {
                    Text(String(format: String(localized: "缺票 %lld"), Int64(missingReceiptRecords.count)))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appFinance, in: Capsule())
                }
                if unsettledRecords.isEmpty && missingReceiptRecords.isEmpty {
                    Text(String(localized: "账目状态良好"))
                        .foregroundStyle(Color.appSuccess)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appSuccess.opacity(0.12), in: Capsule())
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 4)
    }

    private func counterpartyMetricCard(title: String, value: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.normal)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func counterpartyRecordRow(_ record: ProjectFinancialRecord, showsDueDate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.date)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(record.normalizedDirection.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(record.normalizedDirection == .income ? Color.appSuccess : Color.appRisk)
                Text(ReportBuilder.money(record.amountValue.doubleValue))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(record.normalizedDirection == .income ? Color.appSuccess : Color.appRisk)
            }
            HStack(spacing: AppSpacing.tight) {
                Text(projectsByID[record.projectId] ?? String(localized: "未知项目"))
                Text(record.normalizedCategory.displayName)
                if showsDueDate, !record.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(String(format: String(localized: "到期 %@"), record.dueDate))
                        .foregroundStyle(Color.appWarning)
                } else if isUnsettled(record) {
                    Text(String(localized: "未结清"))
                        .foregroundStyle(Color.appWarning)
                }
                if isMissingReceipt(record) {
                    Text(String(localized: "缺票"))
                        .foregroundStyle(Color.appFinance)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if !record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(record.note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func isUnsettled(_ record: ProjectFinancialRecord) -> Bool {
        record.normalizedStatus == .active
            && !record.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isMissingReceipt(_ record: ProjectFinancialRecord) -> Bool {
        record.requiresAttachment && !hasLinkedDocument(record)
    }

    private func dateSortKey(_ raw: String) -> Date {
        Formatters.parseDateOrDateTime(raw) ?? Date.distantPast
    }
}

private struct BookCounterpartyProjectRollup: Identifiable {
    let projectId: UUID
    let projectName: String
    let latestDate: String
    let receivableAmount: Double
    let payableAmount: Double
    let unsettledCount: Int
    let missingReceiptCount: Int

    var id: UUID { projectId }
}

private enum BookDirectionFilter: CaseIterable {
    case all
    case income
    case expense

    var displayName: String {
        switch self {
        case .all:
            return String(localized: "全部")
        case .income:
            return String(localized: "收入")
        case .expense:
            return String(localized: "支出")
        }
    }

    func matches(_ record: ProjectFinancialRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .income:
            return record.isIncomeDirection
        case .expense:
            return record.isExpenseDirection
        }
    }
}

private enum BookCategoryFilter: CaseIterable {
    case all
    case invoice
    case receipt

    var displayName: String {
        switch self {
        case .all:
            return String(localized: "全部")
        case .invoice:
            return String(localized: "发票")
        case .receipt:
            return String(localized: "收据")
        }
    }

    func matches(_ record: ProjectFinancialRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .invoice:
            return record.category == .invoice
        case .receipt:
            return record.category == .receipt
        }
    }
}

private enum BookAttachmentFilter: CaseIterable {
    case all
    case attached
    case unattached

    var displayName: String {
        switch self {
        case .all:
            return String(localized: "全部")
        case .attached:
            return String(localized: "已附票据")
        case .unattached:
            return String(localized: "未附票据")
        }
    }

    func matches(
        _ record: ProjectFinancialRecord,
        linkedDocuments: (ProjectFinancialRecord) -> [ProjectDocument]
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .attached:
            return !linkedDocuments(record).isEmpty
        case .unattached:
            return record.requiresAttachment && linkedDocuments(record).isEmpty
        }
    }
}

private enum BookOutstandingFilter: CaseIterable {
    case all
    case activeWithDueDate

    var displayName: String {
        switch self {
        case .all:
            return String(localized: "全部")
        case .activeWithDueDate:
            return String(localized: "应收付")
        }
    }

    func matches(_ record: ProjectFinancialRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .activeWithDueDate:
            return record.normalizedStatus == .active && !record.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
