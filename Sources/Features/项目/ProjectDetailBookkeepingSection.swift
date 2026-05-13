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
            Section("账目操作") {
                Button {
                    onAddRecord()
                } label: {
                    Label("新增账目", systemImage: "plus.circle.fill")
                }
            }

            Section("项目财务汇总") {
                LabeledContent("收入", value: ReportBuilder.money(totalIncome))
                LabeledContent("支出", value: ReportBuilder.money(totalExpense))
                LabeledContent("净额", value: ReportBuilder.money(totalIncome - totalExpense))
                LabeledContent("未附票据", value: "\(unattachedCount) 笔")
            }

            Section("按单位汇总（供应商/班组/客户）") {
                if counterpartySummaries.isEmpty {
                    Text("暂无可汇总的对方单位。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(counterpartySummaries) { summary in
                        NavigationLink {
                            BookCounterpartyDetailView(
                                summary: summary,
                                records: counterpartyRecords(for: summary.name),
                                projectsByID: projectNameByID,
                                suppliers: matchingSuppliers(for: summary.name),
                                contacts: matchingContacts(for: summary.name),
                                hasLinkedDocument: hasLinkedDocument(_:)
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
                                    Text("净额 \(ReportBuilder.money(summary.netOutstandingAmount))")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(summary.netOutstandingAmount >= 0 ? Color.appSuccess : Color.appRisk)
                                }
                                HStack(spacing: AppSpacing.tight) {
                                    Text("应收 \(ReportBuilder.money(summary.receivableAmount))")
                                        .foregroundStyle(Color.appSuccess)
                                    Text("应付 \(ReportBuilder.money(summary.payableAmount))")
                                        .foregroundStyle(Color.appRisk)
                                    if summary.unsettledCount > 0 {
                                        Text("未结清 \(summary.unsettledCount) 笔")
                                            .foregroundStyle(Color.appWarning)
                                    }
                                    if summary.missingReceiptCount > 0 {
                                        Text("缺票 \(summary.missingReceiptCount) 笔")
                                            .foregroundStyle(Color.appFinance)
                                    }
                                }
                                .font(.caption2)
                                HStack(spacing: AppSpacing.tight) {
                                    Text("累计收入 \(ReportBuilder.money(summary.incomeAmount))")
                                        .foregroundStyle(.secondary)
                                    Text("累计支出 \(ReportBuilder.money(summary.expenseAmount))")
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

            Section("未结清清单 (\(unsettledRecords.count))") {
                if unsettledRecords.isEmpty {
                    Text("暂无未结清记录。")
                        .foregroundStyle(.secondary)
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
                Section("快速筛选") {
                    HStack {
                        Text("当前: \(quickFilterLabel)")
                        Spacer()
                        Button("清除") {
                            resetToDefaultFilters()
                            onResetQuickFilter()
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }

            Section("筛选") {
                Picker("收支", selection: $directionFilter) {
                    ForEach(BookDirectionFilter.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Picker("票据类型", selection: $categoryFilter) {
                    ForEach(BookCategoryFilter.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Picker("票据附件", selection: $attachmentFilter) {
                    ForEach(BookAttachmentFilter.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Picker("状态", selection: $outstandingFilter) {
                    ForEach(BookOutstandingFilter.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Toggle("限定日期范围", isOn: $useDateRange)
                if useDateRange {
                    DatePicker("开始", selection: $startDate, displayedComponents: .date)
                    DatePicker("结束", selection: $endDate, displayedComponents: .date)
                }
            }

            Section("项目财务流水 (\(filteredRecords.count))") {
                if filteredRecords.isEmpty {
                    ContentUnavailableView(
                        "当前筛选下暂无记录",
                        systemImage: "tray",
                        description: Text("调整筛选条件或新增一笔财务流水。")
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
                                    if !record.invoiceNumber.isEmpty { Text("票号 \(record.invoiceNumber)") }
                                    if !linkedDocuments(record).isEmpty { Text("已附票据\(linkedDocuments(record).count)") }
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
            return "应收付"
        case .missingReceipt:
            return "缺票"
        }
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
        return trimmed.isEmpty ? "未填写单位" : trimmed
    }

    private func counterpartyRecords(for name: String) -> [ProjectFinancialRecord] {
        allFinancialRecords.filter { counterpartyDisplayName($0.counterparty) == name }
    }

    private func matchingSuppliers(for name: String) -> [SupplierProfile] {
        let source = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, source != "未填写单位" else { return [] }
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
        guard !source.isEmpty, source != "未填写单位" else { return [] }
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
        guard !source.isEmpty, source != "未填写单位" else {
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
            return "供应商"
        case .team:
            return "班组"
        case .customer:
            return "客户"
        case .other:
            return "其他"
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
}

private struct BookCounterpartyDetailView: View {
    let summary: BookCounterpartySummary
    let records: [ProjectFinancialRecord]
    let projectsByID: [UUID: String]
    let suppliers: [SupplierProfile]
    let contacts: [ProjectContact]
    let hasLinkedDocument: (ProjectFinancialRecord) -> Bool

    private var unsettledRecords: [ProjectFinancialRecord] {
        records.filter {
            $0.normalizedStatus == .active
                && !$0.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        records.filter { $0.requiresAttachment && !hasLinkedDocument($0) }.count
    }

    private var recentProjectRollups: [BookCounterpartyProjectRollup] {
        let grouped = Dictionary(grouping: records, by: \.projectId)
        return grouped.map { projectId, rows in
            let latestRecord = rows.max { lhs, rhs in
                dateSortKey(lhs.date) < dateSortKey(rhs.date)
            }
            let unsettled = rows.filter {
                $0.normalizedStatus == .active
                    && !$0.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let receivable = unsettled
                .filter { $0.normalizedDirection == .income }
                .reduce(MoneyValue.zero) { $0 + $1.amountValue }
                .doubleValue
            let payable = unsettled
                .filter { $0.normalizedDirection == .expense }
                .reduce(MoneyValue.zero) { $0 + $1.amountValue }
                .doubleValue
            let missing = rows.filter { $0.requiresAttachment && !hasLinkedDocument($0) }.count
            return BookCounterpartyProjectRollup(
                projectId: projectId,
                projectName: projectsByID[projectId] ?? "未知项目",
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
            Section("核心指标") {
                LabeledContent("累计收入", value: ReportBuilder.money(summary.incomeAmount))
                LabeledContent("累计支出", value: ReportBuilder.money(summary.expenseAmount))
                LabeledContent("应收", value: ReportBuilder.money(receivableAmount))
                LabeledContent("应付", value: ReportBuilder.money(payableAmount))
                LabeledContent("未结清", value: "\(unsettledRecords.count) 笔")
                LabeledContent("缺票", value: "\(missingReceiptCount) 笔")
            }

            Section("最近项目") {
                if recentProjectRollups.isEmpty {
                    Text("暂无项目记录。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentProjectRollups.prefix(6)) { rollup in
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
                                    Text("应收 \(ReportBuilder.money(rollup.receivableAmount))")
                                        .foregroundStyle(Color.appSuccess)
                                    Text("应付 \(ReportBuilder.money(rollup.payableAmount))")
                                        .foregroundStyle(Color.appRisk)
                                    if rollup.unsettledCount > 0 {
                                        Text("未结清 \(rollup.unsettledCount)")
                                            .foregroundStyle(Color.appWarning)
                                    }
                                    if rollup.missingReceiptCount > 0 {
                                        Text("缺票 \(rollup.missingReceiptCount)")
                                            .foregroundStyle(Color.appFinance)
                                    }
                                }
                                .font(.caption2)
                            }
                        }
                    }
                }
            }

            Section("关联联系人 / 供应商") {
                if suppliers.isEmpty && contacts.isEmpty {
                    Text("暂无已关联联系人或供应商。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(suppliers.prefix(3)) { supplier in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(supplier.name)
                                .font(.callout.weight(.medium))
                            Text([supplier.contact, supplier.phone].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(contacts.prefix(5)) { contact in
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

            Section("最近流水") {
                if recentRecords.isEmpty {
                    Text("暂无流水记录。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentRecords.prefix(12)) { record in
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
                                Text(projectsByID[record.projectId] ?? "未知项目")
                                Text(record.normalizedCategory.displayName)
                                if record.normalizedStatus == .active,
                                   !record.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("未结清")
                                        .foregroundStyle(Color.appWarning)
                                }
                                if record.requiresAttachment && !hasLinkedDocument(record) {
                                    Text("缺票")
                                        .foregroundStyle(Color.appFinance)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(summary.name)
        .navigationBarTitleDisplayMode(.inline)
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

private enum BookDirectionFilter: String, CaseIterable {
    case all = "全部"
    case income = "收入"
    case expense = "支出"

    var displayName: String { rawValue }

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

private enum BookCategoryFilter: String, CaseIterable {
    case all = "全部"
    case invoice = "发票"
    case receipt = "收据"

    var displayName: String { rawValue }

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

private enum BookAttachmentFilter: String, CaseIterable {
    case all = "全部"
    case attached = "已附票据"
    case unattached = "未附票据"

    var displayName: String { rawValue }

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

private enum BookOutstandingFilter: String, CaseIterable {
    case all = "全部"
    case activeWithDueDate = "应收付"

    var displayName: String { rawValue }

    func matches(_ record: ProjectFinancialRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .activeWithDueDate:
            return record.normalizedStatus == .active && !record.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
