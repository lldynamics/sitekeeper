import SwiftUI

struct QuotationScopeSection: View {
    let projects: [Project]
    @Binding var projectFilter: UUID?
    let statusChipBinding: Binding<QuoteStatusChip>
    let projectQuoteSummaries: [(name: String, total: Double)]

    var body: some View {
        Section(String(localized: "范围")) {
            ProjectContextStrip(
                title: String(localized: "当前工程"),
                projects: projects,
                selectedProjectId: $projectFilter,
                emptyText: String(localized: "全部项目")
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
            } ?? String(localized: "未归属")
            let statusText = "\(item.versionName) · \(item.status.displayName)"
            let amountText = String(
                format: String(localized: "单价 ¥%@ × %@%@"),
                item.unitPrice,
                item.quantity,
                item.unit
            )
            let extraText = item.customerConfirmedDate.isEmpty
                ? ""
                : String(format: String(localized: "确认 %@"), item.customerConfirmedDate)
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
                    Text(String(localized: "小计")).foregroundStyle(.secondary)
                    Spacer()
                    Text(ReportBuilder.money(subtotalBeforeValue.doubleValue))
                }
                if totalTaxValue.isPositive {
                    HStack {
                        Text(String(localized: "税额")).foregroundStyle(.appRisk)
                        Spacer()
                        Text(ReportBuilder.money(totalTaxValue.doubleValue)).foregroundStyle(.appRisk)
                    }
                }
                if totalDiscountValue.isPositive {
                    HStack {
                        Text(String(localized: "折扣")).foregroundStyle(.appSuccess)
                        Spacer()
                        Text("-\(ReportBuilder.money(totalDiscountValue.doubleValue))").foregroundStyle(.appSuccess)
                    }
                }
                Divider()
                HStack {
                    Text(String(localized: "合计")).font(.title3.weight(.bold))
                    Spacer()
                    Text(ReportBuilder.money(grandTotalValue.doubleValue))
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
                Label(String(localized: "从材料/人工生成报价"), systemImage: "wand.and.stars")
            }
            Button(action: onOpenExport) {
                Label(String(localized: "导出当前报价"), systemImage: "doc.richtext")
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
                Text(String(localized: "材料清单为空"))
                    .foregroundStyle(.secondary)
            }
        } label: {
            Image(systemName: "ellipsis.circle").visibleIconStyle()
        }
        .accessibilityLabel(String(localized: "更多操作"))
        .buttonStyle(.appIcon())
    }
}
