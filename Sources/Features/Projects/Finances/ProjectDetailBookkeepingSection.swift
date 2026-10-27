import SwiftUI

struct ProjectBookkeepingView: View {
    let projectID: UUID
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
    @State private var ledgerPageIndex = 0
    @State private var unsettledPageIndex = 0
    @State private var counterpartyPageIndex = 0
    @State private var categoryFilter: BookCategoryFilter = .all
    @State private var attachmentFilter: BookAttachmentFilter = .all
    @State private var outstandingFilter: BookOutstandingFilter = .all
    @State private var useDateRange = false
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()

    var body: some View {
        let matching = filteredRecords
        let ledgerPage = RecordPage(matching, index: ledgerPageIndex)
        let unsettledPage = RecordPage(unsettledRecords, index: unsettledPageIndex)
        let counterpartyPage = RecordPage(counterpartySummaries, index: counterpartyPageIndex)
        Group {
            ProjectDetailAnchoredSection(AppLocalization.string("成本汇总"), anchor: .finance) {
                NavigationLink { ProjectPaymentPlanView(projectID: projectID) } label: {
                    Label(AppLocalization.string("分期收付款"), systemImage: "calendar.badge.clock")
                }
                .accessibilityIdentifier("project.payment-plans")
                if let project = projects.first(where: { $0.id == projectID }) {
                    NavigationLink { ProjectWarehouseView(project: project) } label: {
                        Label(AppLocalization.string("项目仓库"), systemImage: "shippingbox")
                    }
                    .accessibilityIdentifier("project.warehouse")
                }
                Button {
                    onAddRecord()
                } label: {
                    Label(AppLocalization.string("记账"), systemImage: "plus.circle.fill")
                }
                LabeledContent(AppLocalization.string("正式收入"), value: ReportBuilder.money(totalIncome))
                LabeledContent(AppLocalization.string("正式支出"), value: ReportBuilder.money(totalExpense))
                LabeledContent(AppLocalization.string("正式净额"), value: ReportBuilder.money(totalIncome - totalExpense))
                LabeledContent(AppLocalization.string("未附票据"), value: String(format: AppLocalization.string("%lld 笔"), Int64(unattachedCount)))
                Text(AppLocalization.string("汇总、往来与缺票统计仅计入正式账目。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(AppLocalization.string("往来单位")) {
                if counterpartySummaries.isEmpty {
                    ProjectInlineEmptyState(AppLocalization.string("还没有往来单位"), systemImage: "person.2")
                } else {
                    ForEach(counterpartyPage.items) { summary in
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
                            BookCounterpartySummaryRow(summary: summary)
                        }
                        .buttonStyle(.plain)
                    }
                    RecordPageControls(index: counterpartyPage.index, count: counterpartyPage.count, selection: $counterpartyPageIndex)
                }
            }

            Section(String(format: AppLocalization.string("未结清 (%lld)"), Int64(unsettledRecords.count))) {
                if unsettledRecords.isEmpty {
                    ProjectInlineEmptyState(AppLocalization.string("没有未结清记录"), systemImage: "checkmark.seal")
                } else {
                    ForEach(unsettledPage.items) { record in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(Formatters.displayDateText(record.date))
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
                                Text(ReportBuilder.money(record.amount))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            BookCounterpartyMatchStrip(match: counterpartyMatch(for: record.counterparty))
                        }
                    }
                    RecordPageControls(index: unsettledPage.index, count: unsettledPage.count, selection: $unsettledPageIndex)
                }
            }

            if let quickFilterLabel {
                Section(AppLocalization.string("快速筛选")) {
                    HStack {
                        Text(String(format: AppLocalization.string("当前: %@"), quickFilterLabel))
                        Spacer()
                        Button(AppLocalization.string("清除")) {
                            resetToDefaultFilters()
                            onResetQuickFilter()
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }

            if !records.isEmpty {
                Section(AppLocalization.string("筛选")) {
                    Picker(AppLocalization.string("收支"), selection: $directionFilter) {
                        ForEach(BookDirectionFilter.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker(AppLocalization.string("票据类型"), selection: $categoryFilter) {
                        ForEach(BookCategoryFilter.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Picker(AppLocalization.string("票据附件"), selection: $attachmentFilter) {
                        ForEach(BookAttachmentFilter.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Picker(AppLocalization.string("状态"), selection: $outstandingFilter) {
                        ForEach(BookOutstandingFilter.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    Toggle(AppLocalization.string("限定日期范围"), isOn: $useDateRange)
                    if useDateRange {
                        DatePicker(AppLocalization.string("开始"), selection: $startDate, displayedComponents: .date)
                        DatePicker(AppLocalization.string("结束"), selection: $endDate, displayedComponents: .date)
                    }
                }
            }

            Section(String(format: AppLocalization.string("流水 (%lld)"), Int64(filteredRecords.count))) {
                if filteredRecords.isEmpty {
                    ProjectInlineEmptyState(
                        records.isEmpty ? AppLocalization.string("还没有账目") : AppLocalization.string("没有匹配账目"),
                        systemImage: "tray",
                        detail: records.isEmpty ? AppLocalization.string("先记一笔收入或支出。") : AppLocalization.string("调整筛选条件或新增一笔。")
                    )
                } else {
                    ForEach(ledgerPage.items) { record in
                        Button {
                            onEdit(record)
                        } label: {
                            ProjectFinancialLedgerRow(record: record, linkedAttachmentCount: linkedDocuments(record).count)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let ids = offsets.compactMap { ledgerPage.items.indices.contains($0) ? ledgerPage.items[$0].id : nil }
                        onDelete(Set(ids))
                    }
                    RecordPageControls(index: ledgerPage.index, count: ledgerPage.count, selection: $ledgerPageIndex)
                }
            }
        }
        .onAppear {
            applyQuickFilter(quickFilter)
        }
        .onChange(of: quickFilter) { _, newValue in
            applyQuickFilter(newValue)
        }
        .onChange(of: directionFilter) { _, _ in ledgerPageIndex = 0 }
        .onChange(of: categoryFilter) { _, _ in ledgerPageIndex = 0 }
        .onChange(of: attachmentFilter) { _, _ in ledgerPageIndex = 0 }
        .onChange(of: outstandingFilter) { _, _ in ledgerPageIndex = 0 }
        .onChange(of: useDateRange) { _, _ in ledgerPageIndex = 0 }
        .onChange(of: startDate) { _, _ in ledgerPageIndex = 0 }
        .onChange(of: endDate) { _, _ in ledgerPageIndex = 0 }
    }
}

private extension ProjectBookkeepingView {
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

    private var totalIncome: MoneyValue {
        ProjectFinancialMetrics.businessRecords(records)
            .filter(\.isIncomeDirection)
            .reduce(MoneyValue.zero) { $0 + $1.amount }
    }

    private var totalExpense: MoneyValue {
        ProjectFinancialMetrics.businessRecords(records)
            .filter(\.isExpenseDirection)
            .reduce(MoneyValue.zero) { $0 + $1.amount }
    }

    private var unattachedCount: Int {
        ProjectFinancialMetrics.missingReceiptRecords(records) { linkedDocuments($0).isEmpty == false }.count
    }

    private var projectNameByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
    }

    private var counterpartySummaries: [BookCounterpartySummary] {
        let grouped = Dictionary(grouping: ProjectFinancialMetrics.businessRecords(records)) { record in
            counterpartyDisplayName(record.counterparty)
        }
        let matchLookup = grouped.keys.reduce(into: [String: BookCounterpartyMatch]()) { result, name in
            result[name] = counterpartyMatch(for: name)
        }
        return grouped.map { name, rows in
            let income = rows
                .filter { $0.normalizedDirection == .income }
                .reduce(MoneyValue.zero) { $0 + $1.amount }
            let expense = rows
                .filter { $0.normalizedDirection == .expense }
                .reduce(MoneyValue.zero) { $0 + $1.amount }
            let unsettledRows = rows.filter(isUnsettled)
            let unsettled = unsettledRows.count
            let receivable = unsettledRows
                .filter { $0.normalizedDirection == .income }
                .reduce(MoneyValue.zero) { $0 + $1.amount }
            let payable = unsettledRows
                .filter { $0.normalizedDirection == .expense }
                .reduce(MoneyValue.zero) { $0 + $1.amount }
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
            return AppLocalization.string("应收付")
        case .missingReceipt:
            return AppLocalization.string("缺票")
        }
    }

    private var unfilledCounterpartyName: String {
        AppLocalization.string("未填写单位")
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
            && !record.dueDate.isEmpty
    }

    private func isMissingReceipt(_ record: ProjectFinancialRecord) -> Bool {
        record.countsInBusinessMetrics && record.requiresAttachment && linkedDocuments(record).isEmpty
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
}
