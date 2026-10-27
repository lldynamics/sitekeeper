import Foundation

/// Raw numeric edits stay independent from the model wrappers, including the
/// optional contract amount. A malformed edit cannot save a previous value.
struct RepositoryQuoteDraft: Codable, Sendable {
    var record: QuoteItem
    var quantityText: String
    var unitPriceText: String
    var taxRateText: String
    var discountRateText: String
    var contractAmountText: String

    init(record: QuoteItem) {
        self.record = record
        quantityText = record.quantity.wireText
        unitPriceText = record.unitPrice.wireText
        taxRateText = record.taxRate.wireText
        discountRateText = record.discountRate.wireText
        contractAmountText = record.contractAmount.wireText
    }

    init(from decoder: Decoder) throws { self.init(record: try QuoteItem(from: decoder)) }
    func encode(to encoder: Encoder) throws { try record.encode(to: encoder) }

    static func validate(_ record: QuoteItem) throws {
        guard !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !record.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              RepositoryMoney.parse(record.taxRate.wireText) != nil,
              let discount = RepositoryMoney.parse(record.discountRate.wireText), discount <= 100,
              record.contractAmount.isEmpty || RepositoryMoney.parse(record.contractAmount.wireText) != nil else { throw RepositoryError.invalidQuoteValues }
        guard let quantity = record.quantity.optionalDecimal, let price = record.unitPrice.optionalDecimal,
              let tax = record.taxRate.optionalDecimal else {
            throw RepositoryError.invalidQuoteValues
        }
        do { _ = try RepositoryQuoteArithmetic.amounts(quantity: quantity, price: price, taxRate: tax, discountRate: discount) } catch { throw RepositoryError.invalidQuoteValues }
    }

    func command() throws -> RepositoryCommand {
        let quantity = try Self.input(quantityText)
        let price = try Self.input(unitPriceText)
        let tax = try Self.input(taxRateText)
        let discount = try Self.input(discountRateText)
        let contract = contractAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : try Self.input(contractAmountText)
        var value = record
        value.quantity = QuantityValue(quantity)
        value.unitPrice = MoneyValue(price)
        value.taxRate = QuantityValue(tax)
        value.discountRate = QuantityValue(discount)
        value.contractAmount = contract.map { MoneyValue($0) } ?? .empty
        guard RepositoryMoney.parse(value.quantity.wireText) == quantity, RepositoryMoney.parse(value.unitPrice.wireText) == price,
              RepositoryMoney.parse(value.taxRate.wireText) == tax, RepositoryMoney.parse(value.discountRate.wireText) == discount,
              contract == nil ? value.contractAmount.isEmpty : RepositoryMoney.parse(value.contractAmount.wireText) == contract else {
            throw RepositoryError.invalidQuoteValues
        }
        try Self.validate(value)
        return .putQuoteItem(value)
    }

    private static func input(_ text: String) throws -> Decimal {
        guard let value = RepositoryMaterialDraft.priceInput(text) else { throw RepositoryError.invalidQuoteValues }
        return value
    }
}
