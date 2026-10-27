import SwiftUI

struct BookCounterpartySummaryRow: View {
    let summary: BookCounterpartySummary

    var body: some View {
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
                Text(String(format: AppLocalization.string("净额 %@"), ReportBuilder.money(summary.netOutstandingAmount)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summary.netOutstandingAmount >= 0 ? Color.appSuccess : Color.appRisk)
            }
            HStack(spacing: AppSpacing.tight) {
                Text(String(format: AppLocalization.string("应收 %@"), ReportBuilder.money(summary.receivableAmount)))
                    .foregroundStyle(Color.appSuccess)
                Text(String(format: AppLocalization.string("应付 %@"), ReportBuilder.money(summary.payableAmount)))
                    .foregroundStyle(Color.appRisk)
                if summary.unsettledCount > 0 {
                    Text(String(format: AppLocalization.string("未结清 %lld 笔"), Int64(summary.unsettledCount)))
                        .foregroundStyle(Color.appWarning)
                }
                if summary.missingReceiptCount > 0 {
                    Text(String(format: AppLocalization.string("缺票 %lld 笔"), Int64(summary.missingReceiptCount)))
                        .foregroundStyle(Color.appFinance)
                }
            }
            .font(.caption2)
            HStack(spacing: AppSpacing.tight) {
                Text(String(format: AppLocalization.string("累计收入 %@"), ReportBuilder.money(summary.incomeAmount)))
                    .foregroundStyle(.secondary)
                Text(String(format: AppLocalization.string("累计支出 %@"), ReportBuilder.money(summary.expenseAmount)))
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
            BookCounterpartyMatchStrip(match: summary.match)
        }
    }
}

struct ProjectFinancialLedgerRow: View {
    let record: ProjectFinancialRecord
    let linkedAttachmentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Formatters.displayDateText(record.date)).font(.callout.weight(.medium))
                Text(record.category.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(record.normalizedStatus.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(record.direction.displayName) \(ReportBuilder.money(record.amount))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(record.isIncomeDirection ? Color.appSuccess : .appRisk)
            }
            HStack(spacing: AppSpacing.tight) {
                if !record.counterparty.isEmpty { Text(record.counterparty) }
                if !record.invoiceNumber.isEmpty {
                    Text(String(format: AppLocalization.string("票号 %@"), record.invoiceNumber))
                }
                if linkedAttachmentCount > 0 {
                    Text(String(format: AppLocalization.string("已附票据%lld"), Int64(linkedAttachmentCount)))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if !record.note.isEmpty {
                Text(record.note).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct BookCounterpartyMatchStrip: View {
    let match: BookCounterpartyMatch

    @ViewBuilder
    var body: some View {
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
