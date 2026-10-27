import Foundation

struct RepositoryMaterialFields: Equatable, Sendable {
    let quantity: String
    let unitPrice: String
    let unit: String
    let specification: String
    let brand: String
    let supplier: String
    let purchaseStatus: MaterialPurchaseStatus

    init(quantity: String, unitPrice: String, unit: String, specification: String, brand: String, supplier: String, purchaseStatus: MaterialPurchaseStatus) {
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.unit = unit
        self.specification = specification
        self.brand = brand
        self.supplier = supplier
        self.purchaseStatus = purchaseStatus
    }

    init(object: [String: Any]) throws {
        // Match the legacy model's default for absent fields, but do not rewrite payloads.
        guard object["name"] is String else { throw RepositoryError.invalidRecord("material name") }
        self.init(quantity: object["quantity"] as? String ?? "", unitPrice: object["unitPrice"] as? String ?? "",
            unit: String((object["unit"] as? String ?? "").prefix(120)),
            specification: String((object["specification"] as? String ?? "").prefix(120)),
            brand: String((object["brand"] as? String ?? "").prefix(120)),
            supplier: String((object["supplier"] as? String ?? "").prefix(120)),
            purchaseStatus: (object["purchaseStatus"] as? String).flatMap(MaterialPurchaseStatus.init(rawValue:)) ?? .notPurchased)
    }
}

struct RepositoryMaterialSummary: Equatable, Sendable {
    let count: Int
    let unpricedCount: Int
    let invalidValueCount: Int
    let hasPrecisionError: Bool
    let knownSubtotal: Decimal?
    var total: Decimal? { unpricedCount == 0 && invalidValueCount == 0 ? knownSubtotal : nil }
}

struct RepositoryMaterialPage: Sendable {
    let page: RepositoryPage
    let summary: RepositoryMaterialSummary
}

/// Streams quantity and price text only. Every matching status is included;
/// neither multiplication nor addition may silently round to a misleading total.
struct RepositoryMaterialAccumulator {
    private var count = 0
    private var unpricedCount = 0
    private var invalidValueCount = 0
    private var hasPrecisionError = false
    private var subtotal = Decimal.zero

    mutating func add(quantity: String, unitPrice: String) {
        count += 1
        guard let quantity = RepositoryMoney.parse(quantity) else {
            invalidValueCount += 1
            return
        }
        guard !unitPrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            unpricedCount += 1
            return
        }
        guard let price = RepositoryMoney.parse(unitPrice) else {
            invalidValueCount += 1
            return
        }
        guard let amount = Self.product(quantity, price) else {
            hasPrecisionError = true
            return
        }
        let result = DecimalMath.add(subtotal, amount)
        if result.isNaN { hasPrecisionError = true } else { subtotal = result }
    }

    static func product(_ quantity: Decimal, _ price: Decimal) -> Decimal? {
        RepositoryMaterialArithmetic.product(quantity, price)
    }

    func result() -> RepositoryMaterialSummary {
        RepositoryMaterialSummary(count: count, unpricedCount: unpricedCount, invalidValueCount: invalidValueCount,
            hasPrecisionError: hasPrecisionError, knownSubtotal: hasPrecisionError ? nil : subtotal)
    }
}

/// Keep raw edits outside normalizing property wrappers so an invalid edit never
/// silently saves the previous numeric value. Blank prices remain editable.
struct RepositoryMaterialDraft: Codable, Sendable {
    var record: MaterialItem
    var quantityText: String
    var unitPriceText: String

    init(record: MaterialItem) {
        self.record = record
        quantityText = record.quantity.wireText
        unitPriceText = record.unitPrice.wireText
    }

    init(from decoder: Decoder) throws { self.init(record: try MaterialItem(from: decoder)) }
    func encode(to encoder: Encoder) throws { try record.encode(to: encoder) }

    static func priceInput(_ text: String) -> Decimal? {
        let text = NumericInputSupport.normalizeSeparators(in: text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.lowercased().contains("e") else { return nil }
        return RepositoryMoney.parse(text)
    }

    static func validate(_ record: MaterialItem) throws {
        guard !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !record.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let quantity = record.quantity.optionalDecimal, quantity >= .zero else { throw RepositoryError.invalidMaterialValues }
        if !record.unitPrice.isEmpty {
            guard let price = record.unitPrice.optionalDecimal, RepositoryMaterialAccumulator.product(quantity, price) != nil else {
                throw RepositoryError.invalidMaterialValues
            }
        }
    }

    func command() throws -> RepositoryCommand {
        guard let quantity = Self.priceInput(quantityText) else { throw RepositoryError.invalidMaterialValues }
        let blankPrice = unitPriceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let price = Self.priceInput(unitPriceText)
        guard blankPrice || price != nil else { throw RepositoryError.invalidMaterialValues }
        var value = record
        value.quantity = QuantityValue(quantity)
        value.unitPrice = price.map(MoneyValue.init) ?? .empty
        guard value.quantity.optionalDecimal == quantity,
              blankPrice ? value.unitPrice.isEmpty : value.unitPrice.optionalDecimal == price else { throw RepositoryError.invalidMaterialValues }
        try Self.validate(value)
        return .putMaterialItem(value)
    }
}
