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
