import SwiftUI

struct QuotationScopeSection: View {
    let projects: [Project]
    @Binding var projectFilter: UUID?
    let statusChipBinding: Binding<QuoteStatusChip>
    let projectQuoteSummaries: [(name: String, total: MoneyValue)]

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
                ForEach(projectQuoteSummaries, id: \.name) { summary in
                    LabeledContent(summary.name, value: ReportBuilder.money(summary.total))
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
            let total = ReportBuilder.quoteGrandTotal(item)
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
                    trailing: ReportBuilder.money(total),
                    trailingColor: Color.appPrimaryAction
                )
            }
        }
        .onDelete(perform: onDelete)
    }
}

struct QuotationTotalsSection: View {
    let subtotalBeforeValue: MoneyValue
    let totalTaxValue: MoneyValue
    let totalDiscountValue: MoneyValue
    let grandTotalValue: MoneyValue

    var body: some View {
        Section {
            VStack(spacing: 4) {
                HStack {
                    Text(AppLocalization.string("小计")).foregroundStyle(.secondary)
                    Spacer()
                    Text(ReportBuilder.money(subtotalBeforeValue))
                }
                if totalTaxValue.isPositive {
                    HStack {
                        Text(AppLocalization.string("税额")).foregroundStyle(.appRisk)
                        Spacer()
                        Text(ReportBuilder.money(totalTaxValue)).foregroundStyle(.appRisk)
                    }
                }
                if totalDiscountValue.isPositive {
                    HStack {
                        Text(AppLocalization.string("折扣")).foregroundStyle(.appSuccess)
                        Spacer()
                        Text("-\(ReportBuilder.money(totalDiscountValue))").foregroundStyle(.appSuccess)
                    }
                }
                Divider()
                HStack {
                    Text(AppLocalization.string("合计")).font(.title3.weight(.bold))
                    Spacer()
                    Text(ReportBuilder.money(grandTotalValue))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.appWarning)
                }
            }
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
