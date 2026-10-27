import SwiftUI

struct BookCounterpartyHeader: View {
    let summary: BookCounterpartySummary
    let projectCount: Int
    let contactCount: Int
    let unsettledCount: Int
    let missingReceiptCount: Int

    var body: some View {
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
                        String(format: AppLocalization.string("%lld 个关联项目"), Int64(projectCount)),
                        String(format: AppLocalization.string("%lld 位联系人"), Int64(contactCount))
                    ].joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: AppSpacing.tight) {
                if unsettledCount > 0 {
                    Text(String(format: AppLocalization.string("未结清 %lld"), Int64(unsettledCount)))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appWarning, in: Capsule())
                }
                if missingReceiptCount > 0 {
                    Text(String(format: AppLocalization.string("缺票 %lld"), Int64(missingReceiptCount)))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appFinance, in: Capsule())
                }
                if unsettledCount == 0 && missingReceiptCount == 0 {
                    Text(AppLocalization.string("账目状态良好"))
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
}

struct BookCounterpartyMetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let tint: Color

    var body: some View {
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
}

struct BookCounterpartyRecordRow: View {
    let record: ProjectFinancialRecord
    let projectName: String
    let showsDueDate: Bool
    let isUnsettled: Bool
    let isMissingReceipt: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Formatters.displayDateText(record.date))
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(record.normalizedDirection.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(record.normalizedDirection == .income ? Color.appSuccess : Color.appRisk)
                Text(ReportBuilder.money(record.amount))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(record.normalizedDirection == .income ? Color.appSuccess : Color.appRisk)
            }
            HStack(spacing: AppSpacing.tight) {
                Text(projectName)
                Text(record.normalizedCategory.displayName)
                Text(record.normalizedStatus.displayName)
                if showsDueDate, !record.dueDate.isEmpty {
                    Text(String(format: AppLocalization.string("到期 %@"), record.dueDate.storageText))
                        .foregroundStyle(Color.appWarning)
                } else if isUnsettled {
                    Text(AppLocalization.string("未结清"))
                        .foregroundStyle(Color.appWarning)
                }
                if isMissingReceipt {
                    Text(AppLocalization.string("缺票"))
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
}

struct BookCounterpartyContactsSection: View {
    let suppliers: [SupplierProfile]
    let contacts: [ProjectContact]

    var body: some View {
        Section(AppLocalization.string("关联联系人 / 供应商")) {
            if suppliers.isEmpty && contacts.isEmpty {
                Text(AppLocalization.string("暂无已关联联系人或供应商。"))
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
    }
}
