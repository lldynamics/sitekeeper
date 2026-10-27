import SwiftUI

struct MaterialSheetMoreMenu: View {
    let isExporting: Bool
    let onExportPDF: () -> Void
    let onExportCSV: () -> Void
    let onExportImage: () -> Void
    let onSaveToMaterialList: () -> Void
    let onClearSheet: () -> Void

    var body: some View {
        Menu {
            Section(AppLocalization.string("导出")) {
                Button(action: onExportPDF) {
                    Label(AppLocalization.string("导出 PDF"), systemImage: "doc.richtext.fill")
                }
                Button(action: onExportCSV) {
                    Label(AppLocalization.string("导出 CSV"), systemImage: "tablecells.fill")
                }
                Button(action: onExportImage) {
                    Label(AppLocalization.string("导出图片"), systemImage: "photo")
                }
            }

            Section(AppLocalization.string("材料单操作")) {
                Button(action: onSaveToMaterialList) {
                    Label(AppLocalization.string("保存到材料清单"), systemImage: "shippingbox.fill")
                }
                Button(role: .destructive, action: onClearSheet) {
                    Label(AppLocalization.string("清空材料单"), systemImage: "trash")
                }
            }
        } label: {
            Label(AppLocalization.string("更多操作"), systemImage: isExporting ? "hourglass" : "ellipsis.circle")
        }
        .labelStyle(.iconOnly)
        .disabled(isExporting)
        .accessibilityLabel(AppLocalization.string("更多操作"))
    }
}

struct MaterialSheetCurrentHeader: View {
    let itemCountText: String?

    var body: some View {
        HStack {
            Text(AppLocalization.string("当前材料单"))
            Spacer()
            if let itemCountText {
                Text(itemCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MaterialSheetExportHeaderSection: View {
    @Binding var exportProjectName: String
    @Binding var exportPreparer: String
    let exportDateLabelText: String

    var body: some View {
        Section(AppLocalization.string("导出表头信息")) {
            TextField(AppLocalization.string("项目名称"), text: $exportProjectName)
            TextField(AppLocalization.string("编制人"), text: $exportPreparer)
            Text(exportDateLabelText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct MaterialSheetExportColumnToggleSection: View {
    @Binding var exportOptions: MaterialSheetExportOptions

    var body: some View {
        Section(AppLocalization.string("导出列设置")) {
            Toggle(AppLocalization.string("估价"), isOn: $exportOptions.showPrice)
            Toggle(AppLocalization.string("人工费"), isOn: $exportOptions.showLabor)
            Toggle(AppLocalization.string("使用部位"), isOn: $exportOptions.showLocation)
            Toggle(AppLocalization.string("供应商"), isOn: $exportOptions.showSupplier)
            Toggle(AppLocalization.string("备注"), isOn: $exportOptions.showNote)
        }
    }
}

struct MaterialSheetSummarySection: View {
    let totalEstimateValue: MoneyValue
    let totalLaborValue: MoneyValue
    let totalEstimateText: String
    let totalLaborText: String
    let grandTotalText: String

    var body: some View {
        Section(AppLocalization.string("合计")) {
            if totalEstimateValue.isPositive {
                HStack {
                    Text(AppLocalization.string("材料估价")).font(.callout)
                    Spacer()
                    Text(totalEstimateText).font(.body.weight(.semibold)).foregroundStyle(Color.appPrimaryAction)
                }
            }
            if totalLaborValue.isPositive {
                HStack {
                    Text(AppLocalization.string("人工费")).font(.callout)
                    Spacer()
                    Text(totalLaborText).font(.body.weight(.semibold)).foregroundStyle(Color.appSuccess)
                }
            }
            if totalEstimateValue.isPositive, totalLaborValue.isPositive {
                HStack {
                    Text(AppLocalization.string("总计")).font(.body.weight(.bold))
                    Spacer()
                    Text(grandTotalText).font(.title3.weight(.bold)).foregroundStyle(Color.appPrimaryAction)
                }
            }
        }
    }
}
