import SwiftUI

struct ProjectBookkeepingView: View {
    let records: [ProjectFinancialRecord]
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

            Section("按对方单位汇总") {
                if counterpartySummaries.isEmpty {
                    Text("暂无可汇总的对方单位。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(counterpartySummaries) { summary in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(summary.name)
                                    .font(.callout.weight(.medium))
                                Spacer()
                                Text(ReportBuilder.money(summary.netAmount))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(summary.netAmount >= 0 ? .green : .red)
                            }
                            HStack(spacing: AppSpacing.tight) {
                                Text("收入 \(ReportBuilder.money(summary.incomeAmount))")
                                    .foregroundStyle(.green)
                                Text("支出 \(ReportBuilder.money(summary.expenseAmount))")
                                    .foregroundStyle(.red)
                                if summary.unsettledCount > 0 {
                                    Text("未结清 \(summary.unsettledCount) 笔")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .font(.caption2)
                        }
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
                                    .foregroundStyle(.orange)
                            }
                            HStack(spacing: AppSpacing.tight) {
                                Text(record.counterparty.isEmpty ? "未填写单位" : record.counterparty)
                                Text(record.normalizedDirection.displayName)
                                    .foregroundStyle(record.normalizedDirection == .income ? .green : .red)
                                Text(ReportBuilder.money(record.amountValue.doubleValue))
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                                        .foregroundStyle(record.isIncomeDirection ? .green : .red)
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

    private var counterpartySummaries: [BookCounterpartySummary] {
        let grouped = Dictionary(grouping: records) { record in
            let name = record.counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "未填写单位" : name
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
            let unsettled = rows.filter {
                $0.normalizedStatus == .active
                    && !$0.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
            return BookCounterpartySummary(
                name: name,
                incomeAmount: income,
                expenseAmount: expense,
                unsettledCount: unsettled
            )
        }
        .sorted { lhs, rhs in
            if lhs.unsettledCount != rhs.unsettledCount {
                return lhs.unsettledCount > rhs.unsettledCount
            }
            if lhs.turnoverAmount != rhs.turnoverAmount {
                return lhs.turnoverAmount > rhs.turnoverAmount
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var unsettledRecords: [ProjectFinancialRecord] {
        records
            .filter {
                $0.normalizedStatus == .active
                    && !$0.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
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
}

private struct BookCounterpartySummary: Identifiable {
    let id = UUID()
    let name: String
    let incomeAmount: Double
    let expenseAmount: Double
    let unsettledCount: Int

    var netAmount: Double { incomeAmount - expenseAmount }
    var turnoverAmount: Double { incomeAmount + expenseAmount }
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
