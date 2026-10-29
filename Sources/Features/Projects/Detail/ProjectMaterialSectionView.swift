import SwiftUI

struct ProjectMaterialSectionView: View {
    @State private var pageIndex = 0
    let items: [MaterialItem]
    let useMetric: Bool
    let onAdd: () -> Void
    let onEdit: (MaterialItem) -> Void
    let onReceive: (MaterialItem) -> Void

    var body: some View {
        let page = RecordPage(items, index: pageIndex)
        Section(String(format: AppLocalization.string("材料 (%lld)"), Int64(items.count))) {
            if items.isEmpty {
                ProjectInlineEmptyState(
                    AppLocalization.string("还没有材料"),
                    systemImage: "shippingbox",
                    detail: AppLocalization.string("记录规格、供应商和进场状态。")
                )
                Button(action: onAdd) {
                    Label(AppLocalization.string("加材料"), systemImage: "shippingbox.fill")
                }
                .buttonStyle(.appProminent())
            } else {
                Button(action: onAdd) {
                    Label(AppLocalization.string("加材料"), systemImage: "shippingbox.fill")
                }
                RecordPageControls(index: page.index, count: page.count, selection: $pageIndex)
                ForEach(page.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                    Button {
                        onEdit(item)
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name).font(.callout.weight(.medium))
                                Text(
                                    "\(UnitDisplay.quantityWithUnit(item.quantity, unit: item.unit, useMetric: useMetric)) × \(ReportBuilder.money(UnitDisplay.displayedUnitPrice(item.unitPrice, unit: item.unit, useMetric: useMetric)))/\(UnitDisplay.translatedUnit(item.unit, useMetric: useMetric))"
                                )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                FlowTagLine(tags: materialTags(for: item))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 5) {
                                Text(ReportBuilder.money(ReportBuilder.materialLineTotal(item)))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.appFinance)
                                Text(item.purchaseStatus.displayName)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(materialStatusColor(item.purchaseStatus))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(materialStatusColor(item.purchaseStatus).opacity(0.12), in: Capsule())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Button(AppLocalization.string("到货入库"), systemImage: "shippingbox.and.arrow.backward") { onReceive(item) }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("material.receive.\(item.id)")
                    }
                }
            }
        }
    }

    private func materialTags(for item: MaterialItem) -> [String] {
        [item.specification, item.brand, item.supplier, item.arrivalDate.isEmpty ? "" : String(format: AppLocalization.string("进场 %@"), item.arrivalDate.storageText)]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func materialStatusColor(_ status: MaterialPurchaseStatus) -> Color {
        switch status {
        case .notPurchased: return .appMuted
        case .purchased: return .appDoc
        case .arrived: return .appSuccess
        case .used: return .appWarning
        }
    }
}
