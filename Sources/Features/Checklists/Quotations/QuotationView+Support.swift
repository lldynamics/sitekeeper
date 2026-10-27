import SwiftUI
import Foundation

extension QuotationView {
    var filtered: [QuoteItem] {
        var result = store.quoteItems
        if let projectFilter {
            result = result.filter { $0.projectId == projectFilter }
        }
        result = SearchMatcher.filter(result, keyword: searchText)
        if let statusFilter {
            result = result.filter { $0.status == statusFilter }
        }
        return result
    }

    var subtotalBeforeValue: MoneyValue {
        filtered.reduce(MoneyValue.zero) { total, item in
            total + ReportBuilder.quoteLineTotal(item)
        }
    }

    var totalTaxValue: MoneyValue {
        filtered.reduce(MoneyValue.zero) { total, item in
            total + ReportBuilder.quoteTaxValue(item)
        }
    }

    var totalDiscountValue: MoneyValue {
        filtered.reduce(MoneyValue.zero) { total, item in
            total + ReportBuilder.quoteDiscountValue(item)
        }
    }

    var grandTotalValue: MoneyValue {
        subtotalBeforeValue + totalTaxValue - totalDiscountValue
    }

    var grandTotal: MoneyValue { grandTotalValue }

    var statusChipBinding: Binding<QuoteStatusChip> {
        Binding(
            get: { QuoteStatusChip(status: statusFilter) },
            set: { statusFilter = $0.status }
        )
    }

    var projectQuoteSummaries: [(name: String, total: MoneyValue)] {
        var rows: [(name: String, total: MoneyValue)] = []
        for project in store.projects {
            let total = store.quoteItems
                .filter { $0.projectId == project.id }
                .reduce(MoneyValue.zero) { $0 + ReportBuilder.quoteGrandTotal($1) }
            if total > 0 { rows.append((project.name, total)) }
        }
        let unassigned = store.quoteItems
            .filter { $0.projectId == nil }
            .reduce(MoneyValue.zero) { $0 + ReportBuilder.quoteGrandTotal($1) }
        if unassigned > 0 { rows.append((AppLocalization.string("未归属"), unassigned)) }
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
