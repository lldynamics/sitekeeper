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

    /// 人数为空表示旧数据未记录人数；明确的 0 人必须保持为 0。
    var totalWorkloadValue: QuantityValue {
        let workload = hoursValue
        guard !workers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return workload
        }
        return workersValue * workload
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
