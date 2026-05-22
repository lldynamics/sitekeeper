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
            Section(String(localized: "导出")) {
                Button(action: onExportPDF) {
                    Label(String(localized: "导出 PDF"), systemImage: "doc.richtext.fill")
                }
                Button(action: onExportCSV) {
                    Label(String(localized: "导出 CSV"), systemImage: "tablecells.fill")
                }
                Button(action: onExportImage) {
                    Label(String(localized: "导出图片"), systemImage: "photo")
                }
            }

            Section(String(localized: "材料单操作")) {
                Button(action: onSaveToMaterialList) {
                    Label(String(localized: "保存到材料清单"), systemImage: "shippingbox.fill")
                }
                Button(role: .destructive, action: onClearSheet) {
                    Label(String(localized: "清空材料单"), systemImage: "trash")
                }
            }
        } label: {
            if isExporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "ellipsis.circle").visibleIconStyle()
            }
        }
        .disabled(isExporting)
        .accessibilityLabel(String(localized: "更多操作"))
    }
}

struct MaterialSheetCurrentHeader: View {
    let itemCountText: String?

    var body: some View {
        HStack {
            Text(String(localized: "当前材料单"))
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
        Section(String(localized: "导出表头信息")) {
            TextField(String(localized: "项目名称"), text: $exportProjectName)
            TextField(String(localized: "编制人"), text: $exportPreparer)
            Text(exportDateLabelText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct MaterialSheetExportColumnToggleSection: View {
    @Binding var exportOptions: MaterialSheetExportOptions

    var body: some View {
        Section(String(localized: "导出列设置")) {
            Toggle(String(localized: "估价"), isOn: $exportOptions.showPrice)
            Toggle(String(localized: "人工费"), isOn: $exportOptions.showLabor)
            Toggle(String(localized: "使用部位"), isOn: $exportOptions.showLocation)
            Toggle(String(localized: "供应商"), isOn: $exportOptions.showSupplier)
            Toggle(String(localized: "备注"), isOn: $exportOptions.showNote)
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
        Section(String(localized: "合计")) {
            if totalEstimateValue.isPositive {
                HStack {
                    Text(String(localized: "材料估价")).font(.callout)
                    Spacer()
                    Text(totalEstimateText).font(.body.weight(.semibold)).foregroundStyle(Color.appPrimaryAction)
                }
            }
            if totalLaborValue.isPositive {
                HStack {
                    Text(String(localized: "人工费")).font(.callout)
                    Spacer()
                    Text(totalLaborText).font(.body.weight(.semibold)).foregroundStyle(Color.appSuccess)
                }
            }
            if totalEstimateValue.isPositive, totalLaborValue.isPositive {
                HStack {
                    Text(String(localized: "总计")).font(.body.weight(.bold))
                    Spacer()
                    Text(grandTotalText).font(.title3.weight(.bold)).foregroundStyle(Color.appPrimaryAction)
                }
            }
        }
    }
}
