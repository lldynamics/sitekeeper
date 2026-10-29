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

    private var amountThemeColor: Color {
        direction == .income ? .appSuccess : .appFinance
    }

    private var spelloutText: String? {
        Formatters.chineseCurrencySpellout(amount)
    }

    private func addQuickAmount(_ increment: Int) {
        let current = Double(amount.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let newAmount = current + Double(increment)
        amount = String(format: "%.2f", newAmount)
            .replacingOccurrences(of: "\\.00$", with: "", options: .regularExpression)
        AppHaptics.impact(.light)
    }

    var body: some View {
        Group {
            Section {
                // 收支方向大胶囊切换
                Picker(AppLocalization.string("类型"), selection: $direction) {
                    ForEach(ProjectFinancialDirection.allCases, id: \.self) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                // 大字号 Hero 金额输入卡片
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("¥")
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .foregroundStyle(amountThemeColor)

                        TextField(AppLocalization.string("0.00"), text: $amount.numericInput(.amount))
                            .accessibilityIdentifier("finance-draft-amount")
                            .keyboardType(.decimalPad)
                            .focused(focused)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundStyle(amountThemeColor)
                            .multilineTextAlignment(.leading)

                        if !amount.isEmpty {
                            Button {
                                amount = ""
                                AppHaptics.impact(.light)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // 中文大写金额实时防错提示
                    if let spelloutText {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                            Text(String(format: AppLocalization.string("大写：%@"), spelloutText))
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(amountThemeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(amountThemeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        .transition(.opacity)
                    }

                    NumericInputValidationHint(
                        validation: InputValidator.validate(
                            amount,
                            kind: .amount,
                            requirement: .requiredPositive
                        ),
                        alignment: .leading
                    )

                    // 常用金额快选键
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach([500, 1000, 2000, 5000, 10000], id: \.self) { increment in
                                Button("+¥\(increment)") {
                                    addQuickAmount(increment)
                                }
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)

                Picker(AppLocalization.string("分类"), selection: $category) {
                    ForEach(availableCategories, id: \.self) { item in
                        Text(item.displayName).tag(item)
                    }
                }

                DatePicker(AppLocalization.string("日期时间"), selection: $date.instantSelection, displayedComponents: [.date, .hourAndMinute])
                TextField(AppLocalization.string("对方单位/个人"), text: $counterparty)
                    .focused(focused)
                TextField(AppLocalization.string("发票号/收据号"), text: $invoiceNumber)
                    .focused(focused)
                TextField(AppLocalization.string("备注"), text: $note, axis: .vertical)
                    .accessibilityIdentifier("finance-draft-note")
                    .lineLimit(2...4)
                    .focused(focused)
            } header: {
                Text(AppLocalization.string("账目信息"))
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
