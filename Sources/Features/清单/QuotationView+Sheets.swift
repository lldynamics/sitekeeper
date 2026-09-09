import SwiftUI
import Foundation

extension QuotationView {
    var quoteForm: some View {
        QuotationEditSheetView(
            isEditing: editingId != nil,
            canSaveQuoteForm: canSaveQuoteForm,
            validationMessages: quoteFormValidationMessages,
            templates: store.templates,
            projects: store.projects,
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
            focusedField: $quoteFormFocusedField,
            showQuoteDeleteConfirm: $showQuoteDeleteConfirm,
            onApplyTemplate: applyQuotationTemplate(_:),
            onCancel: { activeSheet = nil },
            onSave: {
                saveItem()
                activeSheet = nil
            },
            onDelete: {
                if let editingId {
                    deleteQuotesWithUndo(ids: [editingId])
                    activeSheet = nil
                }
            }
        )
    }

    var generateQuoteForm: some View {
        QuotationGenerateSheetView(
            projects: store.projects,
            generateProjectId: $generateProjectId,
            defaultMaterialPrice: $defaultMaterialPrice,
            materialPriceMode: $materialQuotePriceMode,
            defaultLaborRate: $defaultLaborRate,
            generateTax: $generateTax,
            generateDiscount: $generateDiscount,
            focusedField: $generateQuoteFocusedField,
            canGenerateQuoteForm: canGenerateQuoteForm,
            unconfirmedLaborCount: unconfirmedLaborQuoteCount,
            onCancel: { activeSheet = nil },
            onGenerate: {
                generateQuoteItems()
                activeSheet = nil
            }
        )
    }

    var quotationExportForm: some View {
        QuotationExportSheetView(
            quoteCustomerName: $quoteCustomerName,
            quoteProjectAddress: $quoteProjectAddress,
            quoteSignerName: $quoteSignerName,
            companyName: $companyName,
            companyPhone: $companyPhone,
            companyAddress: $companyAddress,
            quoteValidityDays: quoteValidityDays,
            isCompanyProfileComplete: isCompanyProfileComplete,
            isPrimaryActionDisabled: filtered.isEmpty || !isCompanyProfileComplete,
            onCancel: { activeSheet = nil },
            onExport: {
                activeSheet = nil
                exportQuotationPDF()
            }
        )
    }

    var contractWriteForm: some View {
        QuotationContractWriteSheetView(
            project: projectFilter.flatMap { id in store.projects.first(where: { $0.id == id }) },
            versions: projectFilter.map {
                QuotationContractWritePlanner.confirmedVersions(projectId: $0, quotes: store.quoteItems)
            } ?? [],
            selectedVersion: $contractWriteVersion,
            plan: contractWritePlan,
            refreshMessage: contractWriteRefreshMessage,
            onCancel: { activeSheet = nil },
            onSelectVersion: refreshContractWritePlan(versionName:),
            onConfirm: {
                if applyContractWritePlan(versionName: contractWriteVersion) {
                    activeSheet = nil
                }
            }
        )
    }
}
