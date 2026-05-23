import SwiftUI

enum QuoteFormField: Hashable {
    case price
    case quantity
    case contractAmount
    case taxRate
    case discountRate
}

enum GenerateQuoteField: Hashable {
    case materialPrice
    case laborRate
    case taxRate
    case discountRate
}

struct QuotationEditFormSections: View {
    let templates: [ProjectTemplate]
    let projects: [Project]
    let isEditing: Bool
    let validationMessages: [String]
    @Binding var formName: String
    @Binding var formUnit: String
    @Binding var formPrice: String
    @Binding var formQty: String
    @Binding var formNotes: String
    @Binding var formTax: String
    @Binding var formDiscount: String
    @Binding var formVersionName: String
    @Binding var formStatus: QuoteStatus
    @Binding var formCustomerConfirmedDate: String
    @Binding var formContractAmount: String
    @Binding var formProjectId: UUID?
    @FocusState.Binding var focusedField: QuoteFormField?
    let onApplyTemplate: (ProjectTemplate) -> Void
    let onRequestDelete: () -> Void

    private var quotationTemplates: [ProjectTemplate] {
        templates.filter { $0.category == .quotation }
    }

    var body: some View {
        Form {
            AppBusinessFormValidationSection(messages: validationMessages)
            Section(String(localized: "必填信息")) {
                if !quotationTemplates.isEmpty {
                    Menu(String(localized: "套用报价模板")) {
                        ForEach(quotationTemplates) { template in
                            Button(template.name) {
                                onApplyTemplate(template)
                            }
                        }
                    }
                }
                TextField(String(localized: "项目名称"), text: $formName)
                LabeledContent(String(localized: "单价 ¥")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("0", text: $formPrice.numericInput(.amount))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .price)
                        NumericInputValidationHint(
                            validation: InputValidator.validate(
                                formPrice,
                                kind: .amount,
                                requirement: .requiredNonNegative
                            )
                        )
                    }
                }
                LabeledContent(String(localized: "数量")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("0", text: $formQty.numericInput(.quantity))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .quantity)
                        NumericInputValidationHint(
                            validation: InputValidator.validate(
                                formQty,
                                kind: .quantity,
                                requirement: .requiredNonNegative
                            )
                        )
                    }
                }
                LabeledContent(String(localized: "单位")) {
                    TextField(String(localized: "项 / 米 / 台"), text: $formUnit)
                        .multilineTextAlignment(.trailing)
                }
                TextField(String(localized: "版本（如 V1）"), text: $formVersionName)
                Picker(String(localized: "状态"), selection: $formStatus) {
                    ForEach(QuoteStatus.allCases, id: \.self) { item in
                        Text(item.displayName).tag(item)
                    }
                }
            }
            Section(String(localized: "商务信息")) {
                OptionalProjectDatePicker(String(localized: "客户确认日期"), text: $formCustomerConfirmedDate)
                LabeledContent(String(localized: "合同金额")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("0", text: $formContractAmount.numericInput(.amount))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .contractAmount)
                        NumericInputValidationHint(
                            validation: InputValidator.validate(
                                formContractAmount,
                                kind: .amount,
                                requirement: .optionalNonNegative
                            )
                        )
                    }
                }
            }
            Section(String(localized: "归属项目")) {
                Picker(String(localized: "选择工程"), selection: $formProjectId) {
                    Text(String(localized: "无归属")).tag(nil as UUID?)
                    ForEach(projects) { project in
                        Text(project.name).tag(project.id as UUID?)
                    }
                }
            }
            Section(String(localized: "费率")) {
                HStack {
                    Text(String(localized: "税率 (%)"))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("0", text: $formTax.numericInput(.taxRate))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .focused($focusedField, equals: .taxRate)
                        NumericInputValidationHint(
                            validation: InputValidator.validate(
                                formTax,
                                kind: .taxRate,
                                requirement: .requiredNonNegative
                            )
                        )
                    }
                }
                HStack {
                    Text(String(localized: "折扣 (%)"))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("0", text: $formDiscount.numericInput(.discountRate))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .focused($focusedField, equals: .discountRate)
                        NumericInputValidationHint(
                            validation: InputValidator.validate(
                                formDiscount,
                                kind: .discountRate,
                                requirement: .requiredNonNegative
                            )
                        )
                    }
                }
            }
            Section(String(localized: "备注")) {
                TextField(String(localized: "备注"), text: $formNotes)
            }
            if isEditing {
                AppBusinessFormDestructiveActionSection(title: String(localized: "删除报价")) {
                    onRequestDelete()
                }
            }
        }
        .toolbar {
            KeyboardNavigationToolbar(
                focusedField: $focusedField,
                fields: [.price, .quantity, .contractAmount, .taxRate, .discountRate]
            )
        }
    }
}

struct QuotationGenerateFormSections: View {
    let projects: [Project]
    @Binding var generateProjectId: UUID?
    @Binding var defaultMaterialPrice: String
    @Binding var defaultLaborRate: String
    @Binding var generateTax: String
    @Binding var generateDiscount: String
    @FocusState.Binding var focusedField: GenerateQuoteField?

    var body: some View {
        Form {
            Section(String(localized: "范围")) {
                Picker(String(localized: "选择工程"), selection: $generateProjectId) {
                    Text(String(localized: "全部未分项目")).tag(nil as UUID?)
                    ForEach(projects) { project in
                        Text(project.name).tag(project.id as UUID?)
                    }
                }
            }
            Section(String(localized: "默认价格")) {
                LabeledContent(String(localized: "材料默认单价")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField(String(localized: "留空表示待补"), text: $defaultMaterialPrice.numericInput(.amount))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .materialPrice)
                        NumericInputValidationHint(
                            validation: InputValidator.validate(
                                defaultMaterialPrice,
                                kind: .amount,
                                requirement: .optionalNonNegative
                            )
                        )
                    }
                }
                LabeledContent(String(localized: "人工单价 ¥/工时")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("120", text: $defaultLaborRate.numericInput(.laborRate))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .laborRate)
                        NumericInputValidationHint(
                            validation: InputValidator.validate(
                                defaultLaborRate,
                                kind: .laborRate,
                                requirement: .requiredNonNegative
                            )
                        )
                    }
                }
            }
            Section(String(localized: "费率")) {
                LabeledContent(String(localized: "税率 %")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("0", text: $generateTax.numericInput(.taxRate))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .taxRate)
                        NumericInputValidationHint(
                            validation: InputValidator.validate(
                                generateTax,
                                kind: .taxRate,
                                requirement: .requiredNonNegative
                            )
                        )
                    }
                }
                LabeledContent(String(localized: "折扣 %")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("0", text: $generateDiscount.numericInput(.discountRate))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .discountRate)
                        NumericInputValidationHint(
                            validation: InputValidator.validate(
                                generateDiscount,
                                kind: .discountRate,
                                requirement: .requiredNonNegative
                            )
                        )
                    }
                }
            }
        }
    }
}

struct QuotationExportFormSections: View {
    @Binding var quoteCustomerName: String
    @Binding var quoteProjectAddress: String
    @Binding var quoteSignerName: String
    @Binding var companyName: String
    @Binding var companyPhone: String
    @Binding var companyAddress: String
    let quoteValidityDays: Int
    let isCompanyProfileComplete: Bool

    var body: some View {
        Form {
            Section(String(localized: "客户信息")) {
                TextField(String(localized: "客户名称"), text: $quoteCustomerName)
                TextField(String(localized: "项目地址"), text: $quoteProjectAddress, axis: .vertical)
                    .lineLimit(2...4)
                TextField(String(localized: "签字人"), text: $quoteSignerName)
            }
            Section(String(localized: "公司信息")) {
                TextField(String(localized: "公司名称"), text: $companyName)
                TextField(String(localized: "公司电话"), text: $companyPhone)
                    .keyboardType(.phonePad)
                TextField(String(localized: "公司地址"), text: $companyAddress, axis: .vertical)
                    .lineLimit(2...4)
                LabeledContent(String(localized: "有效期"), value: String(format: String(localized: "%lld 天"), Int64(quoteValidityDays)))
                if !isCompanyProfileComplete {
                    Text(String(localized: "请补全公司信息后再导出。"))
                        .font(.caption)
                        .foregroundStyle(.appWarning)
                }
            }
        }
    }
}
