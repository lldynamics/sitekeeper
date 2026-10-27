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
    @Binding var formCustomerConfirmedDate: BusinessDateValue
    @Binding var formContractAmount: String
    @Binding var formProjectId: UUID?
    @Binding var showQuoteDeleteConfirm: Bool
    let onApplyTemplate: (ProjectTemplate) -> Void
    let onCancel: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        AppBusinessEditForm(
            title: isEditing ? AppLocalization.string("编辑报价") : AppLocalization.string("添加报价"),
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
                onApplyTemplate: onApplyTemplate,
                onRequestDelete: {
                    showQuoteDeleteConfirm = true
                }
            )
        }
        .alert(AppLocalization.string("删除这条报价？"), isPresented: $showQuoteDeleteConfirm) {
            Button(AppLocalization.string("取消"), role: .cancel) {}
            Button(AppLocalization.string("删除"), role: .destructive) {
                onDelete()
            }
        } message: {
            Text(AppLocalization.string("删除后可在短时间内撤销。"))
        }
    }
}

struct QuotationGenerateSheetView: View {
    let projects: [Project]
    @Binding var generateProjectId: UUID?
    @Binding var defaultMaterialPrice: String
    @Binding var materialPriceMode: MaterialQuotePriceMode?
    @Binding var defaultLaborRate: String
    @Binding var generateTax: String
    @Binding var generateDiscount: String
    let canGenerateQuoteForm: Bool
    let unconfirmedLaborCount: Int
    let onCancel: () -> Void
    let onGenerate: () -> Void

    var body: some View {
        AppBusinessEditForm(
            title: AppLocalization.string("生成报价"),
            primaryActionTitle: AppLocalization.string("生成报价"),
            isPrimaryActionDisabled: !canGenerateQuoteForm,
            onCancel: onCancel,
            onPrimaryAction: onGenerate
        ) {
            QuotationGenerateFormSections(
                projects: projects,
                generateProjectId: $generateProjectId,
                defaultMaterialPrice: $defaultMaterialPrice,
                materialPriceMode: $materialPriceMode,
                defaultLaborRate: $defaultLaborRate,
                generateTax: $generateTax,
                generateDiscount: $generateDiscount,
                unconfirmedLaborCount: unconfirmedLaborCount
            )
        }
    }
}

struct QuotationContractWriteSheetView: View {
    let project: Project?
    let versions: [String]
    @Binding var selectedVersion: String
    let plan: QuotationContractWritePlan?
    let refreshMessage: String
    let onCancel: () -> Void
    let onSelectVersion: (String) -> Void
    let onConfirm: () -> Void

    var body: some View {
        AppBusinessEditForm(
            title: AppLocalization.string("确认写入合同"),
            primaryActionTitle: AppLocalization.string("确认覆盖合同金额"),
            isPrimaryActionDisabled: plan?.canApply != true,
            onCancel: onCancel,
            onPrimaryAction: onConfirm
        ) {
            Form {
                if let project {
                    Section(AppLocalization.string("写入范围")) {
                        LabeledContent(AppLocalization.string("工程"), value: project.name)
                        Picker(AppLocalization.string("报价版本"), selection: $selectedVersion) {
                            ForEach(versions, id: \.self) { version in
                                Text(version).tag(version)
                            }
                        }
                        .accessibilityIdentifier("quotation-contract-version-picker")
                        .onChange(of: selectedVersion) { _, version in
                            onSelectVersion(version)
                        }
                        LabeledContent(AppLocalization.string("报价状态"), value: QuoteStatus.confirmed.displayName)
                        if let plan {
                            LabeledContent(
                                AppLocalization.string("纳入报价"),
                                value: String(format: AppLocalization.string("%lld 项"), Int64(plan.itemCount))
                            )
                            Text(String(
                                format: AppLocalization.string("已选择：%@"),
                                plan.itemNames.joined(separator: AppLocalization.string("、"))
                            ))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Section(AppLocalization.string("金额预览")) {
                        LabeledContent(
                            AppLocalization.string("原合同金额"),
                            value: ReportBuilder.money(plan?.oldAmount ?? project.contractAmount)
                        )
                        LabeledContent(
                            AppLocalization.string("新合同金额"),
                            value: ReportBuilder.money(plan?.newAmount ?? 0)
                        )
                        Text(AppLocalization.string("逐项优先采用转合同金额；未填写时采用含税折后报价金额。搜索条件不会影响本次写入。"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let plan, plan.incompleteItemCount > 0 {
                            Text(String(
                                format: AppLocalization.string("有 %lld 项缺少有效的转合同金额或计价信息，请先补齐金额、单价、数量和费率。"),
                                Int64(plan.incompleteItemCount)
                            ))
                            .font(.footnote)
                            .foregroundStyle(Color.appRisk)
                        }
                        if !refreshMessage.isEmpty {
                            Text(refreshMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.appWarning)
                        }
                    }
                } else {
                    ContentUnavailableView(AppLocalization.string("未找到工程"), systemImage: "exclamationmark.triangle")
                }
            }
        }
        .accessibilityIdentifier("quotation-contract-confirm-sheet")
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
            title: AppLocalization.string("导出报价单"),
            primaryActionTitle: AppLocalization.string("导出 PDF"),
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
