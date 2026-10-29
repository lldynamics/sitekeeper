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

    static func visibleFields(for mode: MaterialQuotePriceMode?) -> [Self] {
        let shared: [Self] = [.laborRate, .taxRate, .discountRate]
        return mode == .overrideAll ? [.materialPrice] + shared : shared
    }
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
    @Binding var formCustomerConfirmedDate: BusinessDateValue
    @Binding var formContractAmount: String
    @Binding var formProjectId: UUID?
    @FocusState private var focusedField: QuoteFormField?
    let onApplyTemplate: (ProjectTemplate) -> Void
    let onRequestDelete: () -> Void

    private var quotationTemplates: [ProjectTemplate] {
        templates.filter { $0.category == .quotation }
    }

    var body: some View {
        Form {
            AppBusinessFormValidationSection(messages: validationMessages)
            Section(AppLocalization.string("必填信息")) {
                if !quotationTemplates.isEmpty {
                    Menu(AppLocalization.string("套用报价模板")) {
                        ForEach(quotationTemplates) { template in
                            Button(template.name) {
                                onApplyTemplate(template)
                            }
                        }
                    }
                }
                TextField(AppLocalization.string("项目名称"), text: $formName)
                LabeledContent(AppLocalization.string("单价 ¥")) {
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
                LabeledContent(AppLocalization.string("数量")) {
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
                LabeledContent(AppLocalization.string("单位")) {
                    TextField(AppLocalization.string("项 / 米 / 台"), text: $formUnit)
                        .multilineTextAlignment(.trailing)
                }
                TextField(AppLocalization.string("版本（如 V1）"), text: $formVersionName)
                Picker(AppLocalization.string("状态"), selection: $formStatus) {
                    ForEach(QuoteStatus.allCases, id: \.self) { item in
                        Text(item.displayName).tag(item)
                    }
                }
            }
            Section(AppLocalization.string("商务信息")) {
                OptionalProjectDatePicker(AppLocalization.string("客户确认日期"), value: $formCustomerConfirmedDate)
                LabeledContent(AppLocalization.string("合同金额")) {
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
            Section(AppLocalization.string("归属项目")) {
                Picker(AppLocalization.string("选择工程"), selection: $formProjectId) {
                    Text(AppLocalization.string("无归属")).tag(nil as UUID?)
                    ForEach(projects) { project in
                        Text(project.name).tag(project.id as UUID?)
                    }
                }
            }
            Section(AppLocalization.string("费率")) {
                HStack {
                    Text(AppLocalization.string("税率 (%)"))
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
                    Text(AppLocalization.string("折扣 (%)"))
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
            Section(AppLocalization.string("备注")) {
                TextField(AppLocalization.string("备注"), text: $formNotes)
            }
            if isEditing {
                AppBusinessFormDestructiveActionSection(title: AppLocalization.string("删除报价")) {
                    onRequestDelete()
                }
            }
        }
        .appKeyboardToolbar {
            KeyboardNavigationToolbar(
                focusedField: $focusedField,
                currentField: focusedField,
                fields: [.price, .quantity, .contractAmount, .taxRate, .discountRate]
            )
        }
    }
}

struct QuotationGenerateFormSections: View {
    let projects: [Project]
    @Binding var generateProjectId: UUID?
    @Binding var defaultMaterialPrice: String
    @Binding var materialPriceMode: MaterialQuotePriceMode?
    @Binding var defaultLaborRate: String
    @Binding var generateTax: String
    @Binding var generateDiscount: String
    let unconfirmedLaborCount: Int
    @FocusState private var focusedField: GenerateQuoteField?

    var body: some View {
        Form {
            Section(AppLocalization.string("范围")) {
                Picker(AppLocalization.string("选择工程"), selection: $generateProjectId) {
                    Text(AppLocalization.string("全部未分项目")).tag(nil as UUID?)
                    ForEach(projects) { project in
                        Text(project.name).tag(project.id as UUID?)
                    }
                }
                if unconfirmedLaborCount > 0 {
                    Text(String(
                        format: AppLocalization.string("有 %lld 条人工记录待确认计量单位，请先编辑确认后再生成报价。"),
                        Int64(unconfirmedLaborCount)
                    ))
                    .font(.footnote)
                    .foregroundStyle(Color.appWarning)
                }
            }
            Section(AppLocalization.string("默认价格")) {
                Picker(AppLocalization.string("材料报价方式"), selection: $materialPriceMode) {
                    Text(AppLocalization.string("请选择报价方式")).tag(nil as MaterialQuotePriceMode?)
                    ForEach(MaterialQuotePriceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode as MaterialQuotePriceMode?)
                    }
                }
                .accessibilityIdentifier("quotation-material-price-mode")
                Text(AppLocalization.string("材料单价通常是成本参考；选择统一设置时填写的是对外报价。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if materialPriceMode == .overrideAll {
                    LabeledContent(AppLocalization.string("统一对外单价")) {
                        VStack(alignment: .trailing, spacing: 2) {
                            TextField("0", text: $defaultMaterialPrice.numericInput(.amount))
                                .accessibilityIdentifier("quotation-generate-material-price")
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($focusedField, equals: .materialPrice)
                            NumericInputValidationHint(
                                validation: InputValidator.validate(
                                    defaultMaterialPrice,
                                    kind: .amount,
                                    requirement: .requiredNonNegative
                                )
                            )
                        }
                    }
                }
                LabeledContent(AppLocalization.string("人工默认单价（按记录单位）")) {
                    VStack(alignment: .trailing, spacing: 2) {
                        TextField("120", text: $defaultLaborRate.numericInput(.laborRate))
                            .accessibilityIdentifier("quotation-generate-labor-rate")
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
            Section(AppLocalization.string("费率")) {
                LabeledContent(AppLocalization.string("税率 %")) {
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
                LabeledContent(AppLocalization.string("折扣 %")) {
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
        .appKeyboardToolbar {
            KeyboardNavigationToolbar(
                focusedField: $focusedField,
                currentField: focusedField,
                fields: GenerateQuoteField.visibleFields(for: materialPriceMode)
            )
        }
        .onChange(of: materialPriceMode) { _, mode in
            if focusedField == .materialPrice, mode != .overrideAll {
                focusedField = .laborRate
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
            Section(AppLocalization.string("quote_reference_export_scope_title")) {
                Text(AppLocalization.string("quote_reference_export_scope_rule"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section(AppLocalization.string("客户信息")) {
                TextField(AppLocalization.string("客户名称"), text: $quoteCustomerName)
                TextField(AppLocalization.string("项目地址"), text: $quoteProjectAddress, axis: .vertical)
                    .lineLimit(2...4)
                TextField(AppLocalization.string("签字人"), text: $quoteSignerName)
            }
            Section(AppLocalization.string("公司信息")) {
                TextField(AppLocalization.string("公司名称"), text: $companyName)
                TextField(AppLocalization.string("公司电话"), text: $companyPhone)
                    .keyboardType(.phonePad)
                TextField(AppLocalization.string("公司地址"), text: $companyAddress, axis: .vertical)
                    .lineLimit(2...4)
                LabeledContent(AppLocalization.string("有效期"), value: String(format: AppLocalization.string("%lld 天"), Int64(quoteValidityDays)))
                if !isCompanyProfileComplete {
                    Text(AppLocalization.string("请补全公司信息后再导出。"))
                        .font(.caption)
                        .foregroundStyle(.appWarning)
                }
            }
        }
    }
}
