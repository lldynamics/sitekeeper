import SwiftUI

struct QuickAddMaterialFields: View {
    @Binding var name: String
    @Binding var quantity: String
    @Binding var unit: String
    @Binding var unitPrice: String
    @Binding var specification: String
    @Binding var brand: String
    @Binding var supplier: String
    @Binding var purchaseStatus: MaterialPurchaseStatus
    @Binding var arrivalDate: BusinessDateValue

    var body: some View {
        Group {
            TextField(AppLocalization.string("材料名称"), text: $name)
            LabeledContent(AppLocalization.string("数量")) {
                TextField("0", text: $quantity.numericInput(.quantity))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent(AppLocalization.string("单位")) {
                TextField(AppLocalization.string("米 / 卷 / 个"), text: $unit)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent(AppLocalization.string("单价")) {
                TextField("0", text: $unitPrice.numericInput(.amount))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            TextField(AppLocalization.string("规格型号"), text: $specification)
            TextField(AppLocalization.string("品牌"), text: $brand)
            TextField(AppLocalization.string("供应商"), text: $supplier)
            Picker(AppLocalization.string("采购状态"), selection: $purchaseStatus) {
                ForEach(MaterialPurchaseStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            OptionalProjectDatePicker(AppLocalization.string("进场日期"), value: $arrivalDate)
        }
    }
}

struct QuickAddQuoteFields: View {
    @Binding var name: String
    @Binding var price: String
    @Binding var quantity: String
    @Binding var unit: String
    @Binding var versionName: String
    @Binding var status: QuoteStatus
    @Binding var confirmedDate: BusinessDateValue
    @Binding var contractAmount: String

    var body: some View {
        Group {
            TextField(AppLocalization.string("项目名称"), text: $name)
            LabeledContent(AppLocalization.string("单价 ¥")) {
                TextField("0", text: $price.numericInput(.amount))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent(AppLocalization.string("数量")) {
                TextField("0", text: $quantity.numericInput(.quantity))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent(AppLocalization.string("单位")) {
                TextField(AppLocalization.string("项 / 米 / 台"), text: $unit)
                    .multilineTextAlignment(.trailing)
            }
            TextField(AppLocalization.string("版本"), text: $versionName)
            Picker(AppLocalization.string("状态"), selection: $status) {
                ForEach(QuoteStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }
            OptionalProjectDatePicker(AppLocalization.string("客户确认日期"), value: $confirmedDate)
            TextField(AppLocalization.string("转合同金额"), text: $contractAmount.numericInput(.amount))
                .keyboardType(.decimalPad)
        }
    }
}
