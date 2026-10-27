import Foundation

struct RepositoryQuoteFields: Equatable, Sendable {
    let quantity: String
    let unitPrice: String
    let unit: String
    let taxRate: String
    let discountRate: String
    let versionName: String
    let status: QuoteStatus

    init(quantity: String, unitPrice: String, unit: String, taxRate: String, discountRate: String, versionName: String, status: QuoteStatus) {
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.unit = unit
        self.taxRate = taxRate
        self.discountRate = discountRate
        self.versionName = versionName
        self.status = status
    }

    init(object: [String: Any]) {
        self.init(quantity: object["quantity"] as? String ?? "", unitPrice: object["unitPrice"] as? String ?? "",
            unit: String((object["unit"] as? String ?? "").prefix(120)), taxRate: object["taxRate"] as? String ?? "0",
            discountRate: object["discountRate"] as? String ?? "0", versionName: object["versionName"] as? String ?? "V1",
            status: (object["status"] as? String).flatMap(QuoteStatus.init(rawValue:)) ?? .draft)
    }
}

struct RepositoryQuoteAmounts: Equatable, Sendable {
    let subtotal: Decimal
    let tax: Decimal
    let discount: Decimal
    let total: Decimal
}

struct RepositoryQuoteSummary: Equatable, Sendable {
    let count: Int
    let invalidValueCount: Int
    let hasPrecisionError: Bool
    let amounts: RepositoryQuoteAmounts?
}

struct RepositoryQuotePage: Sendable {
    let page: RepositoryPage
    let summary: RepositoryQuoteSummary
}

enum RepositoryQuoteCalculationError: Error { case invalidValue, precision }

enum RepositoryQuoteArithmetic {
    /// Same business formula as ReportBuilder: tax and discount both use the
    /// original line amount, with legacy discounts clamped to 100 percent.
    static func amounts(_ fields: RepositoryQuoteFields) throws -> RepositoryQuoteAmounts {
        guard let quantity = RepositoryMoney.parse(fields.quantity), let price = RepositoryMoney.parse(fields.unitPrice),
              let taxRate = rate(fields.taxRate), let discountRate = rate(fields.discountRate) else { throw RepositoryQuoteCalculationError.invalidValue }
        return try amounts(quantity: quantity, price: price, taxRate: taxRate, discountRate: discountRate)
    }

    static func amounts(quantity: Decimal, price: Decimal, taxRate: Decimal, discountRate: Decimal) throws -> RepositoryQuoteAmounts {
        let subtotal = try multiply(quantity, price)
        let tax = try multiply(subtotal, multiply(taxRate, Decimal(string: "0.01")!))
        let discount = try multiply(subtotal, multiply(min(discountRate, 100), Decimal(string: "0.01")!))
        return try amounts(subtotal: subtotal, tax: tax, discount: discount)
    }

    static func amounts(subtotal: Decimal, tax: Decimal, discount: Decimal) throws -> RepositoryQuoteAmounts {
        let gross = try add(subtotal, tax)
        let total = DecimalMath.subtract(gross, discount)
        guard !total.isNaN, total >= .zero else {
            throw RepositoryQuoteCalculationError.precision
        }
        return RepositoryQuoteAmounts(subtotal: subtotal, tax: tax, discount: discount, total: total)
    }

    static func add(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        let result = DecimalMath.add(lhs, rhs)
        guard !result.isNaN else { throw RepositoryQuoteCalculationError.precision }
        return result
    }

    private static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        guard let result = RepositoryMaterialArithmetic.product(lhs, rhs) else { throw RepositoryQuoteCalculationError.precision }
        return result
    }

    private static func rate(_ text: String) -> Decimal? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .zero : RepositoryMoney.parse(text)
    }
}

struct RepositoryQuoteAccumulator {
    private var count = 0
    private var invalidValueCount = 0
    private var hasPrecisionError = false
    private var subtotal = Decimal.zero
    private var tax = Decimal.zero
    private var discount = Decimal.zero

    mutating func add(_ fields: RepositoryQuoteFields) {
        count += 1
        do {
            let amounts = try RepositoryQuoteArithmetic.amounts(fields)
            subtotal = try RepositoryQuoteArithmetic.add(subtotal, amounts.subtotal)
            tax = try RepositoryQuoteArithmetic.add(tax, amounts.tax)
            discount = try RepositoryQuoteArithmetic.add(discount, amounts.discount)
        } catch RepositoryQuoteCalculationError.invalidValue {
            invalidValueCount += 1
        } catch {
            hasPrecisionError = true
        }
    }

    func result() -> RepositoryQuoteSummary {
        let amounts = try? RepositoryQuoteArithmetic.amounts(subtotal: subtotal, tax: tax, discount: discount)
        let precisionError = hasPrecisionError || amounts == nil
        return RepositoryQuoteSummary(count: count, invalidValueCount: invalidValueCount, hasPrecisionError: precisionError,
            amounts: invalidValueCount == 0 && !precisionError ? amounts : nil)
    }
}
