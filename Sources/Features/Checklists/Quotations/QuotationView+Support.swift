import SwiftUI
import Foundation

extension QuotationView {
    var filtered: [QuoteItem] {
        var result = store.quoteItems
        if let projectFilter {
            result = result.filter { $0.projectId == projectFilter }
        }
        if let businessVersionFilter {
            let project = projectFilter.flatMap { id in store.projects.first { $0.id == id } }
            result = businessVersionFilter.applying(to: result, project: project)
        }
        result = SearchMatcher.filter(result, keyword: searchText)
        if let statusFilter {
            result = result.filter { $0.status == statusFilter }
        }
        return result
    }

    var filteredReferenceSummary: QuotationReferenceSummary {
        QuotationReferenceSummary(items: filtered)
    }

    var businessVersionFilterIsValid: Bool {
        guard let businessVersionFilter else { return true }
        let project = projectFilter.flatMap { id in store.projects.first { $0.id == id } }
        return businessVersionFilter.isValid(project: project, quotes: store.quoteItems)
    }

    var statusChipBinding: Binding<QuoteStatusChip> {
        Binding(
            get: { QuoteStatusChip(status: statusFilter) },
            set: { statusFilter = $0.status }
        )
    }

    var projectQuoteSummaries: [QuotationProjectReferenceSummary] {
        var rows = store.projects.compactMap { project -> QuotationProjectReferenceSummary? in
            let items = store.quoteItems.filter { $0.projectId == project.id }
            guard !items.isEmpty else { return nil }
            return QuotationProjectReferenceSummary(projectID: project.id, name: project.name,
                summary: QuotationReferenceSummary(items: items))
        }
        let unassigned = store.quoteItems.filter { $0.projectId == nil }
        if !unassigned.isEmpty {
            rows.append(QuotationProjectReferenceSummary(projectID: nil, name: AppLocalization.string("未归属"),
                summary: QuotationReferenceSummary(items: unassigned)))
        }
        return rows
    }

    var canSaveQuoteForm: Bool {
        !formName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !formUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        InputValidator.validate(formPrice, kind: .amount, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(formQty, kind: .quantity, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(formTax, kind: .taxRate, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(formDiscount, kind: .discountRate, requirement: .requiredNonNegative).isValid &&
        discountRateIsWithinBounds(formDiscount) &&
        InputValidator.validate(formContractAmount, kind: .amount, requirement: .optionalNonNegative).isValid
    }

    var quoteFormValidationMessages: [String] {
        var messages: [String] = []
        if formName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(AppLocalization.string("请填写报价名称"))
        }
        if formUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(AppLocalization.string("请填写报价单位"))
        }
        return messages
    }

    var canGenerateQuoteForm: Bool {
        (!hasMaterialQuoteSources || materialQuotePriceMode != nil) &&
        (materialQuotePriceMode != .overrideAll ||
            InputValidator.validate(defaultMaterialPrice, kind: .amount, requirement: .requiredNonNegative).isValid) &&
        InputValidator.validate(defaultLaborRate, kind: .laborRate, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(generateTax, kind: .taxRate, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(generateDiscount, kind: .discountRate, requirement: .requiredNonNegative).isValid &&
        discountRateIsWithinBounds(generateDiscount) &&
            unconfirmedLaborQuoteCount == 0
    }

    var hasMaterialQuoteSources: Bool {
        store.materialItems.contains { $0.projectId == generateProjectId }
    }

    var unconfirmedLaborQuoteCount: Int {
        store.laborRecords.filter {
            $0.projectId == generateProjectId && $0.workloadUnit == .legacyUnspecified
        }.count
    }

    func statusColor(_ status: QuoteStatus) -> Color {
        switch status {
        case .draft: return .secondary
        case .sent: return .appWarning
        case .confirmed: return .appSuccess
        }
    }

    private func discountRateIsWithinBounds(_ rawValue: String) -> Bool {
        guard let value = DataValueParser.decimalValueIfPresent(from: rawValue, requiresEntireString: true) else {
            return false
        }
        return value >= .zero && value <= 100
    }

    var isCompanyProfileComplete: Bool {
        !companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !companyPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !companyAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func singleProjectInFiltered() -> Project? {
        let ids = Set(filtered.compactMap(\.projectId))
        guard ids.count == 1, let id = ids.first else { return nil }
        return store.projects.first(where: { $0.id == id })
    }
}
