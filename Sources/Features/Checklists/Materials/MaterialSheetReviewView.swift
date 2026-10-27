import SwiftUI

struct MaterialSheetReviewView: View {
    let items: [MaterialSheetItem]

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView(AppLocalization.string("材料单为空"), systemImage: "checklist")
            }
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.name).font(.headline)
                    if !item.specification.isEmpty {
                        Text(item.specification).font(.subheadline).foregroundStyle(.secondary)
                    }
                    LabeledContent(AppLocalization.string("数量"), value: "\(item.quantity) \(item.unit)")
                    LabeledContent(AppLocalization.string("估价"), value: item.unitPrice.isEmpty ? AppLocalization.string("未填写") : item.unitPrice)
                    LabeledContent(AppLocalization.string("材料估价"), value: ReportBuilder.money(MaterialSheetLogicHelpers.lineTotalValue(for: item)))
                    if !item.laborCost.isEmpty {
                        LabeledContent(AppLocalization.string("人工费"), value: item.laborCost)
                    }
                    if !item.usageLocation.isEmpty {
                        LabeledContent(AppLocalization.string("使用部位"), value: item.usageLocation)
                    }
                }
                .font(.callout)
                .padding(.vertical, 4)
                .accessibilityIdentifier("material-review-\(item.id)")
            }
        }
        .accessibilityIdentifier("material-review-list")
    }
}

struct MaterialSheetReviewTotal: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let items: [MaterialSheetItem]

    var body: some View {
        let totals = MaterialSheetLogicHelpers.totals(for: items)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        layout {
            Text(AppLocalization.string("总计")).font(.headline)
            Text(totals.grandText).font(.headline).monospacedDigit()
                .foregroundStyle(Color.appPrimaryAction)
            Text(String(format: AppLocalization.string("%d 项"), items.count))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("material-review-total")
    }
}
