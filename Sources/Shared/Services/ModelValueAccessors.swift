import Foundation

extension Project {
    var contractAmountValue: MoneyValue { MoneyValue(text: contractAmount) }
    var paidAmountValue: MoneyValue { MoneyValue(text: paidAmount) }
    var materialCostValue: MoneyValue { MoneyValue(text: materialCost) }
    var laborCostValue: MoneyValue { MoneyValue(text: laborCost) }
}

extension MaterialItem {
    var quantityValue: QuantityValue { QuantityValue(text: quantity) }
    var unitPriceValue: MoneyValue { MoneyValue(text: unitPrice) }
}

extension QuoteItem {
    var quantityValue: QuantityValue { QuantityValue(text: quantity) }
    var unitPriceValue: MoneyValue { MoneyValue(text: unitPrice) }
    var taxRateValue: QuantityValue { QuantityValue(text: taxRate) }
    var discountRateValue: QuantityValue { QuantityValue(text: discountRate) }
    var contractAmountValue: MoneyValue { MoneyValue(text: contractAmount) }
}

extension LaborRecord {
    var workersValue: QuantityValue { QuantityValue(text: workers) }
    var hoursValue: QuantityValue { QuantityValue(text: hours) }
    var unitRateValue: QuantityValue { QuantityValue(text: unitRate) }
}

extension LegacyPaymentRecord {
    var amountValue: MoneyValue { MoneyValue(text: amount) }

    func migratedFinancialRecord(counterparty: String = "") -> ProjectFinancialRecord {
        let noteParts = [
            normalizedMethodDisplayName,
            note.trimmingCharacters(in: .whitespacesAndNewlines)
        ].filter { !$0.isEmpty }

        return ProjectFinancialRecord(
            id: id,
            projectId: projectId,
            date: date,
            direction: .income,
            category: .collection,
            amount: amount,
            counterparty: counterparty,
            invoiceNumber: isInvoiced ? "已开票" : "",
            status: .active,
            note: noteParts.joined(separator: " · ")
        )
    }
}

extension ProjectFinancialRecord {
    var amountValue: MoneyValue { MoneyValue(text: amount) }
}

extension ProjectDocument {
    var amountValue: MoneyValue { MoneyValue(text: amount) }
}

extension ProjectWarehouseMovement {
    var quantityValue: QuantityValue { QuantityValue(text: quantity) }
}
