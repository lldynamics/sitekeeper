import Foundation

struct RepositoryLaborDraft: Codable, Sendable {
    var record: LaborRecord
    var workersText: String
    var hoursText: String
    var unitRateText: String

    init(record: LaborRecord) {
        self.record = record
        workersText = record.workers.wireText
        hoursText = record.hours.wireText
        unitRateText = record.unitRate.wireText
    }

    init(from decoder: Decoder) throws { self.init(record: try LaborRecord(from: decoder)) }
    func encode(to encoder: Encoder) throws { try record.encode(to: encoder) }

    static func validate(_ value: LaborRecord) throws {
        guard value.workloadUnit != .legacyUnspecified,
              let workers = value.workers.optionalDecimal, workers >= 0,
              let hours = value.hours.optionalDecimal, hours >= 0,
              let workload = RepositoryMaterialArithmetic.product(workers, hours) else { throw RepositoryError.invalidLaborValues }
        if !value.unitRate.isEmpty {
            guard let rate = value.unitRate.optionalDecimal, rate >= 0,
                  RepositoryMaterialArithmetic.product(workload, rate) != nil else { throw RepositoryError.invalidLaborValues }
        }
    }

    func command() throws -> RepositoryCommand {
        guard let workers = RepositoryMaterialDraft.priceInput(workersText),
              let hours = RepositoryMaterialDraft.priceInput(hoursText) else { throw RepositoryError.invalidLaborValues }
        let rate: Decimal?
        if unitRateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { rate = nil } else {
            guard let value = RepositoryMaterialDraft.priceInput(unitRateText) else { throw RepositoryError.invalidLaborValues }
            rate = value
        }
        var value = record
        value.workers = QuantityValue(workers)
        value.hours = QuantityValue(hours)
        value.unitRate = rate.map { MoneyValue($0) } ?? .empty
        guard value.workers.optionalDecimal == workers, value.hours.optionalDecimal == hours,
              value.unitRate.optionalDecimal == rate else { throw RepositoryError.invalidLaborValues }
        try Self.validate(value)
        return .putLaborRecord(value)
    }
}
