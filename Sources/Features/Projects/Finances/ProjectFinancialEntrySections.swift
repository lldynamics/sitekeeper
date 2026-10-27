import SwiftUI

/// Input storage and focus remain owned by the presenting add/edit sheet.
struct ProjectFinancialEntrySections: View {
    @Binding var date: BusinessDateValue
    @Binding var direction: ProjectFinancialDirection
    @Binding var category: ProjectFinancialCategory
    @Binding var amount: String
    @Binding var counterparty: String
    @Binding var invoiceNumber: String
    @Binding var note: String
    @Binding var hasDueDate: Bool
    @Binding var dueDate: BusinessDateValue
    @Binding var reminderStatus: ProjectFinancialReminderStatus
    var focused: FocusState<Bool>.Binding

    private var availableCategories: [ProjectFinancialCategory] {
        ProjectFinancialCategory.allowed(for: direction)
    }

    var body: some View {
        Group {
            Section(AppLocalization.string("账目")) {
                DatePicker(AppLocalization.string("日期时间"), selection: $date.instantSelection, displayedComponents: [.date, .hourAndMinute])
                Picker(AppLocalization.string("类型"), selection: $direction) {
                    ForEach(ProjectFinancialDirection.allCases, id: \.self) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                Picker(AppLocalization.string("分类"), selection: $category) {
                    ForEach(availableCategories, id: \.self) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                TextField(AppLocalization.string("金额（元）"), text: $amount.numericInput(.amount))
                    .accessibilityIdentifier("finance-draft-amount")
                    .keyboardType(.decimalPad)
                    .focused(focused)
                NumericInputValidationHint(
                    validation: InputValidator.validate(
                        amount,
                        kind: .amount,
                        requirement: .requiredPositive
                    ),
                    alignment: .leading
                )
                TextField(AppLocalization.string("对方单位/个人"), text: $counterparty)
                    .focused(focused)
                TextField(AppLocalization.string("发票号/收据号"), text: $invoiceNumber)
                    .focused(focused)
                TextField(AppLocalization.string("备注"), text: $note, axis: .vertical)
                    .accessibilityIdentifier("finance-draft-note")
                    .lineLimit(2...4)
                    .focused(focused)
            }
            Section(AppLocalization.string("应收/应付提醒")) {
                Toggle(AppLocalization.string("设置到期提醒"), isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker(AppLocalization.string("到期日"), selection: $dueDate.daySelection, displayedComponents: .date)
                    Picker(AppLocalization.string("提醒状态"), selection: $reminderStatus) {
                        ForEach(ProjectFinancialReminderStatus.allCases.filter { $0 != .none }, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                }
            }
        }
    }
}
