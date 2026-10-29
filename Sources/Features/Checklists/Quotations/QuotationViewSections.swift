import SwiftUI

struct QuotationScopeSection: View {
    let projects: [Project]
    @Binding var projectFilter: UUID?
    let statusChipBinding: Binding<QuoteStatusChip>
    let projectQuoteSummaries: [QuotationProjectReferenceSummary]

    var body: some View {
        Section(AppLocalization.string("范围")) {
            ProjectContextStrip(
                title: AppLocalization.string("当前工程"),
                projects: projects,
                selectedProjectId: $projectFilter,
                emptyText: AppLocalization.string("全部项目")
            )
            FilterChipBar(
                options: QuoteStatusChip.allCases,
                selection: statusChipBinding,
                title: { $0.title }
            )
            if projectFilter == nil {
                Text(AppLocalization.string("quote_reference_project_scope"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(projectQuoteSummaries) { row in
                    LabeledContent(row.name, value: row.summary.amounts.map { ReportBuilder.money($0.total) }
                        ?? AppLocalization.string("quote_reference_amount_review"))
                }
            }
        }
    }
}

struct QuotationItemsSection: View {
    let items: [QuoteItem]
    let projects: [Project]
    let statusColor: (QuoteStatus) -> Color
    let onEdit: (QuoteItem) -> Void
    let onDelete: (IndexSet) -> Void

    var body: some View {
        ForEach(items) { item in
            let total = ProjectBusinessQuoteMetrics.strictAmount(item)
            let projectText = item.projectId.flatMap { id in
                projects.first(where: { $0.id == id })?.name
            } ?? AppLocalization.string("未归属")
            let statusText = "\(item.versionName) · \(item.status.displayName)"
            let amountText = String(
                format: AppLocalization.string("单价 ¥%@ × %@%@"),
                item.unitPrice.wireText,
                item.quantity.wireText,
                item.unit
            )
            let extraText = item.customerConfirmedDate.isEmpty
                ? ""
                : String(format: AppLocalization.string("确认 %@"), item.customerConfirmedDate.storageText)
            Button {
                onEdit(item)
            } label: {
                BusinessRecordRow(
                    icon: "doc.text.fill",
                    iconColor: statusColor(item.status),
                    title: item.name,
                    meta: [amountText, projectText, statusText].joined(separator: " · "),
                    note: [extraText, item.notes].filter { !$0.isEmpty }.joined(separator: " · "),
                    trailing: total.map { ReportBuilder.money($0) } ?? AppLocalization.string("quote_reference_amount_review"),
                    trailingColor: Color.appPrimaryAction
                )
            }
        }
        .onDelete(perform: onDelete)
    }
}

struct QuotationTotalsSection: View {
    let summary: QuotationReferenceSummary

    var body: some View {
        Section(AppLocalization.string("quote_reference_filtered_title")) {
            if let amounts = summary.amounts {
                LabeledContent(AppLocalization.string("小计"), value: ReportBuilder.money(amounts.subtotal))
                if amounts.tax.isPositive {
                    LabeledContent(AppLocalization.string("税额"), value: ReportBuilder.money(amounts.tax))
                }
                if amounts.discount.isPositive {
                    LabeledContent(AppLocalization.string("折扣"), value: "-\(ReportBuilder.money(amounts.discount))")
                }
                LabeledContent(AppLocalization.string("quote_reference_total"), value: ReportBuilder.money(amounts.total))
                    .font(.headline)
                    .foregroundStyle(Color.appWarning)
            } else {
                LabeledContent(
                    AppLocalization.string("quote_reference_total"),
                    value: AppLocalization.string(summary.itemCount == 0
                        ? "quote_reference_no_matches" : "quote_reference_amount_review")
                )
            }
            Text(AppLocalization.string("quote_reference_filtered_rule"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct QuotationToolbarMenu: View {
    let materialItems: [MaterialItem]
    let onOpenGenerate: () -> Void
    let onOpenExport: () -> Void
    let onAppendFromMaterial: (MaterialItem) -> Void

    var body: some View {
        Menu {
            Button(action: onOpenGenerate) {
                Label(AppLocalization.string("从材料/人工生成报价"), systemImage: "wand.and.stars")
            }
            Button(action: onOpenExport) {
                Label(AppLocalization.string("导出当前报价"), systemImage: "doc.richtext")
            }
            Divider()
            ForEach(materialItems) { material in
                Button {
                    onAppendFromMaterial(material)
                } label: {
                    Text("\(material.name) (\(material.quantity) \(material.unit))")
                }
            }
            if materialItems.isEmpty {
                Text(AppLocalization.string("材料清单为空"))
                    .foregroundStyle(.secondary)
            }
        } label: {
            Image(systemName: "ellipsis.circle").visibleIconStyle()
        }
        .accessibilityLabel(AppLocalization.string("更多操作"))
        .buttonStyle(.appIcon())
    }
}
