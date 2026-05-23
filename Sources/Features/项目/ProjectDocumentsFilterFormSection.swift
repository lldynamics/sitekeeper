import SwiftUI

struct ProjectDocumentsFilterFormSection: View {
    @Binding var categoryFilter: DocumentCategoryFilter
    @Binding var relationFilter: DocumentRelationFilter
    @Binding var useDateRange: Bool
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var minAmount: String
    @Binding var maxAmount: String

    var body: some View {
        Section(String(localized: "类型")) {
            Picker(String(localized: "资料类型"), selection: $categoryFilter) {
                ForEach(DocumentCategoryFilter.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
            Picker(String(localized: "关联状态"), selection: $relationFilter) {
                ForEach(DocumentRelationFilter.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
        }
        Section(String(localized: "日期")) {
            Toggle(String(localized: "限定日期范围"), isOn: $useDateRange)
            if useDateRange {
                DatePicker(String(localized: "开始"), selection: $startDate, displayedComponents: .date)
                DatePicker(String(localized: "结束"), selection: $endDate, displayedComponents: .date)
            }
        }
        Section(String(localized: "金额")) {
            LabeledContent(String(localized: "最小金额")) {
                TextField("0", text: $minAmount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent(String(localized: "最大金额")) {
                TextField(String(localized: "不限"), text: $maxAmount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
