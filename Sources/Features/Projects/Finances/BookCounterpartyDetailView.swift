import SwiftUI

struct BookCounterpartyDetailView: View {
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

    private var receivableAmount: MoneyValue {
        unsettledRecords
            .filter { $0.normalizedDirection == .income }
            .reduce(MoneyValue.zero) { $0 + $1.amount }
    }

    private var payableAmount: MoneyValue {
        unsettledRecords
            .filter { $0.normalizedDirection == .expense }
            .reduce(MoneyValue.zero) { $0 + $1.amount }
    }

    private var missingReceiptCount: Int {
        missingReceiptRecords.count
    }

    private var recentProjectRollups: [BookCounterpartyProjectRollup] {
        let grouped = Dictionary(grouping: ProjectFinancialMetrics.businessRecords(records), by: \.projectId)
        return grouped.map { projectId, rows in
            let latestRecord = rows.max { lhs, rhs in
                dateSortKey(lhs.date) < dateSortKey(rhs.date)
            }
            let unsettled = rows.filter(isUnsettled)
            let receivable = unsettled
                .filter { $0.normalizedDirection == .income }
                .reduce(MoneyValue.zero) { $0 + $1.amount }
            let payable = unsettled
                .filter { $0.normalizedDirection == .expense }
                .reduce(MoneyValue.zero) { $0 + $1.amount }
            let missing = rows.filter(isMissingReceipt).count
            return BookCounterpartyProjectRollup(
                projectId: projectId,
                projectName: projectsByID[projectId] ?? AppLocalization.string("未知项目"),
                latestDate: latestRecord?.date ?? .empty,
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
                BookCounterpartyHeader(
                    summary: summary, projectCount: recentProjectRollups.count, contactCount: contacts.count,
                    unsettledCount: unsettledRecords.count, missingReceiptCount: missingReceiptRecords.count
                )
            }

            Section(AppLocalization.string("核心指标")) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.normal) {
                    BookCounterpartyMetricCard(
                        title: AppLocalization.string("应收"),
                        value: ReportBuilder.money(receivableAmount),
                        subtitle: String(format: AppLocalization.string("%lld 笔"), Int64(unsettledRecords.filter(\.isIncomeDirection).count)),
                        tint: .appSuccess
                    )
                    BookCounterpartyMetricCard(
                        title: AppLocalization.string("应付"),
                        value: ReportBuilder.money(payableAmount),
                        subtitle: String(format: AppLocalization.string("%lld 笔"), Int64(unsettledRecords.filter(\.isExpenseDirection).count)),
                        tint: .appRisk
                    )
                    BookCounterpartyMetricCard(
                        title: AppLocalization.string("未结清"),
                        value: String(format: AppLocalization.string("%lld 笔"), Int64(unsettledRecords.count)),
                        subtitle: String(format: AppLocalization.string("合计 %@"), ReportBuilder.money(receivableAmount + payableAmount)),
                        tint: .appWarning
                    )
                    BookCounterpartyMetricCard(
                        title: AppLocalization.string("缺票"),
                        value: String(format: AppLocalization.string("%lld 笔"), Int64(missingReceiptCount)),
                        subtitle: AppLocalization.string("需补票据/资料"),
                        tint: .appFinance
                    )
                }
                LabeledContent(AppLocalization.string("累计收入"), value: ReportBuilder.money(summary.incomeAmount))
                LabeledContent(AppLocalization.string("累计支出"), value: ReportBuilder.money(summary.expenseAmount))
            }

            Section(AppLocalization.string("关联项目")) {
                if recentProjectRollups.isEmpty {
                    Text(AppLocalization.string("暂无项目记录。"))
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
                                    Text(String(format: AppLocalization.string("应收 %@"), ReportBuilder.money(rollup.receivableAmount)))
                                        .foregroundStyle(Color.appSuccess)
                                    Text(String(format: AppLocalization.string("应付 %@"), ReportBuilder.money(rollup.payableAmount)))
                                        .foregroundStyle(Color.appRisk)
                                    if rollup.unsettledCount > 0 {
                                        Text(String(format: AppLocalization.string("未结清 %lld"), Int64(rollup.unsettledCount)))
                                            .foregroundStyle(Color.appWarning)
                                    }
                                    if rollup.missingReceiptCount > 0 {
                                        Text(String(format: AppLocalization.string("缺票 %lld"), Int64(rollup.missingReceiptCount)))
                                            .foregroundStyle(Color.appFinance)
                                    }
                                }
                                .font(.caption2)
                            }
                        }
                    }
                }
            }

            BookCounterpartyContactsSection(suppliers: suppliers, contacts: contacts)

            Section(AppLocalization.string("未结清账目")) {
                if unsettledRecords.isEmpty {
                    Text(AppLocalization.string("暂无未结清账目。"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(unsettledRecords) { record in
                        Button {
                            onEdit(record)
                        } label: {
                            BookCounterpartyRecordRow(
                                record: record, projectName: projectsByID[record.projectId] ?? AppLocalization.string("未知项目"),
                                showsDueDate: true, isUnsettled: isUnsettled(record), isMissingReceipt: isMissingReceipt(record)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section(AppLocalization.string("缺票记录")) {
                if missingReceiptRecords.isEmpty {
                    Text(AppLocalization.string("暂无缺票记录。"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(missingReceiptRecords) { record in
                        Button {
                            onEdit(record)
                        } label: {
                            BookCounterpartyRecordRow(
                                record: record, projectName: projectsByID[record.projectId] ?? AppLocalization.string("未知项目"),
                                showsDueDate: false, isUnsettled: isUnsettled(record), isMissingReceipt: isMissingReceipt(record)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section(AppLocalization.string("最近流水")) {
                if recentRecords.isEmpty {
                    Text(AppLocalization.string("暂无流水记录。"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentRecords.prefix(12)) { record in
                        Button {
                            onEdit(record)
                        } label: {
                            BookCounterpartyRecordRow(
                                record: record, projectName: projectsByID[record.projectId] ?? AppLocalization.string("未知项目"),
                                showsDueDate: false, isUnsettled: isUnsettled(record), isMissingReceipt: isMissingReceipt(record)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(summary.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isUnsettled(_ record: ProjectFinancialRecord) -> Bool {
        record.normalizedStatus == .active
            && !record.dueDate.isEmpty
    }

    private func isMissingReceipt(_ record: ProjectFinancialRecord) -> Bool {
        ProjectFinancialMetrics.missingReceiptRecords([record], hasLinkedDocument: hasLinkedDocument).isEmpty == false
    }

    private func dateSortKey(_ raw: BusinessDateValue) -> Date {
        Formatters.parseDateOrDateTime(raw) ?? Date.distantPast
    }
}

struct BookCounterpartyProjectRollup: Identifiable {
    let projectId: UUID
    let projectName: String
    let latestDate: BusinessDateValue
    let receivableAmount: MoneyValue
    let payableAmount: MoneyValue
    let unsettledCount: Int
    let missingReceiptCount: Int

    var id: UUID { projectId }
}
