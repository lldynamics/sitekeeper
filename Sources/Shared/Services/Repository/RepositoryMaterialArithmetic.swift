import Foundation

/// The same checked arithmetic backs candidate SQL summaries and domain reports.
enum RepositoryMaterialArithmetic {
    static func product(_ quantity: Decimal, _ price: Decimal) -> Decimal? {
        guard !quantity.isNaN, !price.isNaN, quantity >= .zero, price >= .zero else { return nil }
        let result = DecimalMath.multiply(quantity, price)
        return result.isNaN ? nil : result
    }
}
