import SwiftUI

struct QuotationEditSheetView: View {
    let isEditing: Bool
    let canSaveQuoteForm: Bool
    let validationMessages: [String]
    let templates: [ProjectTemplate]
    let projects: [Project]
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
    let focusedField: FocusState<QuoteFormField?>.Binding
    @Binding var showQuoteDeleteConfirm: Bool
    let onApplyTemplate: (ProjectTemplate) -> Void
    let onCancel: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        AppBusinessEditForm(
            title: isEditing ? String(localized: "编辑报价") : String(localized: "添加报价"),
            isPrimaryActionDisabled: !canSaveQuoteForm,
            onCancel: onCancel,
            onPrimaryAction: onSave
        ) {
            QuotationEditFormSections(
                templates: templates,
                projects: projects,
                isEditing: isEditing,
                validationMessages: validationMessages,
                formName: $formName,
                formUnit: $formUnit,
                formPrice: $formPrice,
                formQty: $formQty,
                formNotes: $formNotes,
                formTax: $formTax,
                formDiscount: $formDiscount,
                formVersionName: $formVersionName,
                formStatus: $formStatus,
                formCustomerConfirmedDate: $formCustomerConfirmedDate,
                formContractAmount: $formContractAmount,
                formProjectId: $formProjectId,
                focusedField: focusedField,
                onApplyTemplate: onApplyTemplate,
                onRequestDelete: {
                    showQuoteDeleteConfirm = true
                }
            )
        }
        .alert(String(localized: "删除这条报价？"), isPresented: $showQuoteDeleteConfirm) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "删除"), role: .destructive) {
                onDelete()
            }
        } message: {
            Text(String(localized: "删除后可在短时间内撤销。"))
        }
    }
}

struct QuotationGenerateSheetView: View {
    let projects: [Project]
    @Binding var generateProjectId: UUID?
    @Binding var defaultMaterialPrice: String
    @Binding var defaultLaborRate: String
    @Binding var generateTax: String
    @Binding var generateDiscount: String
    let focusedField: FocusState<GenerateQuoteField?>.Binding
    let canGenerateQuoteForm: Bool
    let unconfirmedLaborCount: Int
    let onCancel: () -> Void
    let onGenerate: () -> Void

    var body: some View {
        AppBusinessEditForm(
            title: String(localized: "生成报价"),
            primaryActionTitle: String(localized: "生成报价"),
            isPrimaryActionDisabled: !canGenerateQuoteForm,
            onCancel: onCancel,
            onPrimaryAction: onGenerate
        ) {
            QuotationGenerateFormSections(
                projects: projects,
                generateProjectId: $generateProjectId,
                defaultMaterialPrice: $defaultMaterialPrice,
                defaultLaborRate: $defaultLaborRate,
                generateTax: $generateTax,
                generateDiscount: $generateDiscount,
                unconfirmedLaborCount: unconfirmedLaborCount,
                focusedField: focusedField
            )
            .toolbar {
                KeyboardNavigationToolbar(
                    focusedField: focusedField,
                    fields: [.materialPrice, .laborRate, .taxRate, .discountRate]
                )
            }
        }
    }
}

struct QuotationExportSheetView: View {
    @Binding var quoteCustomerName: String
    @Binding var quoteProjectAddress: String
    @Binding var quoteSignerName: String
    @Binding var companyName: String
    @Binding var companyPhone: String
    @Binding var companyAddress: String
    let quoteValidityDays: Int
    let isCompanyProfileComplete: Bool
    let isPrimaryActionDisabled: Bool
    let onCancel: () -> Void
    let onExport: () -> Void

    var body: some View {
        AppBusinessEditForm(
            title: String(localized: "导出报价单"),
            primaryActionTitle: String(localized: "导出 PDF"),
            isPrimaryActionDisabled: isPrimaryActionDisabled,
            onCancel: onCancel,
            onPrimaryAction: onExport
        ) {
            QuotationExportFormSections(
                quoteCustomerName: $quoteCustomerName,
                quoteProjectAddress: $quoteProjectAddress,
                quoteSignerName: $quoteSignerName,
                companyName: $companyName,
                companyPhone: $companyPhone,
                companyAddress: $companyAddress,
                quoteValidityDays: quoteValidityDays,
                isCompanyProfileComplete: isCompanyProfileComplete
            )
        }
    }
}
