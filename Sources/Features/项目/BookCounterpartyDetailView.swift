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

struct BookCounterpartyProjectRollup: Identifiable {
    let projectId: UUID
    let projectName: String
    let latestDate: String
    let receivableAmount: Double
    let payableAmount: Double
    let unsettledCount: Int
    let missingReceiptCount: Int

    var id: UUID { projectId }
}
