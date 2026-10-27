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
        Section(AppLocalization.string("类型")) {
            Picker(AppLocalization.string("资料类型"), selection: $categoryFilter) {
                ForEach(DocumentCategoryFilter.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
            Picker(AppLocalization.string("关联状态"), selection: $relationFilter) {
                ForEach(DocumentRelationFilter.allCases, id: \.self) { item in
                    Text(item.displayName).tag(item)
                }
            }
        }
        Section(AppLocalization.string("日期")) {
            Toggle(AppLocalization.string("限定日期范围"), isOn: $useDateRange)
            if useDateRange {
                DatePicker(AppLocalization.string("开始"), selection: $startDate, displayedComponents: .date)
                DatePicker(AppLocalization.string("结束"), selection: $endDate, displayedComponents: .date)
            }
        }
        Section(AppLocalization.string("金额")) {
            LabeledContent(AppLocalization.string("最小金额")) {
                TextField("0", text: $minAmount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent(AppLocalization.string("最大金额")) {
                TextField(AppLocalization.string("不限"), text: $maxAmount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
