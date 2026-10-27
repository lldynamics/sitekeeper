import Foundation

struct RepositoryFinancialFields: Equatable, Sendable {
    let amount: String
    let direction: ProjectFinancialDirection
    let category: ProjectFinancialCategory
    let status: ProjectFinancialStatus
    let counterparty: String
}

struct RepositoryFinancialSummary: Equatable, Sendable {
    let count: Int
    let activeCount: Int
    let invalidAmountCount: Int
    let hasPrecisionError: Bool
    let income: Decimal?
    let expense: Decimal?
    let balance: Decimal?
}

struct RepositoryFinancialPage: Sendable {
    let page: RepositoryPage
    let summary: RepositoryFinancialSummary
}

/// Streams metadata only. Draft/archived rows are counted but never included in totals.
struct RepositoryFinancialAccumulator {
    private var count = 0
    private var activeCount = 0
    private var invalidAmountCount = 0
    private var hasPrecisionError = false
    private var income = Decimal.zero
    private var expense = Decimal.zero

    mutating func add(amount: String?, direction: String?, status: String?) throws {
        guard let status, let status = ProjectFinancialStatus(rawValue: status),
              let direction, let direction = ProjectFinancialDirection(rawValue: direction) else { throw RepositoryError.integrityFailure }
        count += 1
        guard status == .active else { return }
        activeCount += 1
        guard let amount, let value = RepositoryMoney.parse(amount) else {
            invalidAmountCount += 1
            return
        }
        let result = DecimalMath.add(direction == .income ? income : expense, value)
        if result.isNaN { hasPrecisionError = true }
        else if direction == .income { income = result }
        else { expense = result }
    }

    func result() -> RepositoryFinancialSummary {
        let balance = DecimalMath.subtract(income, expense)
        let precisionError = hasPrecisionError || balance.isNaN
        let valid = invalidAmountCount == 0 && !precisionError
        return RepositoryFinancialSummary(count: count, activeCount: activeCount, invalidAmountCount: invalidAmountCount,
            hasPrecisionError: precisionError, income: valid ? income : nil, expense: valid ? expense : nil, balance: valid ? balance : nil)
    }
}

enum RepositoryMoney {
    /// No partial parses, negative amounts, binary floats, or silent precision loss.
    static func parse(_ text: String) -> Decimal? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        let coefficient = value.lowercased().split(separator: "e")[0].filter { $0 != "." }
        let digits = coefficient.drop(while: { $0 == "0" }).reversed().drop(while: { $0 == "0" })
        guard digits.count <= 38, let number = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
              !number.isNaN, number >= .zero else { return nil }
        // A nonzero coefficient underflowing to zero is not a valid zero amount.
        guard number != .zero || digits.isEmpty else { return nil }
        return number
    }

    static func input(_ text: String) -> Decimal? {
        let value = NumericInputSupport.normalizeSeparators(in: text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.lowercased().contains("e"), let amount = parse(value), amount > .zero else { return nil }
        return amount
    }

    static func display(_ amount: Decimal) -> String {
        let text = NSDecimalNumber(decimal: amount).stringValue
        guard !text.lowercased().contains("e") else { return text }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        if pieces.count == 1 { return text + ".00" }
        if pieces[1].count == 1 { return text + "0" }
        return text
    }
}

/// Raw input is separate from the model's normalizing property wrapper. Invalid
/// edits must remain visible and must never save the previous amount by accident.
struct RepositoryFinancialDraft: Codable, Sendable {
    var record: ProjectFinancialRecord
    var amountText: String

    init(record: ProjectFinancialRecord) {
        self.record = record
        amountText = record.amount.wireText
    }

    init(from decoder: Decoder) throws {
        self.init(record: try ProjectFinancialRecord(from: decoder))
    }

    func encode(to encoder: Encoder) throws { try record.encode(to: encoder) }

    func command() throws -> RepositoryCommand {
        guard let amount = RepositoryMoney.input(amountText) else { throw RepositoryError.invalidAmount }
        var value = record
        value.amount = MoneyValue(amount)
        guard value.amount.optionalDecimal == amount else { throw RepositoryError.invalidAmount }
        return .putFinancialRecord(value)
    }
}
