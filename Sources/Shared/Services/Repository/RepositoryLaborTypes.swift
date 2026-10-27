import Foundation

struct RepositoryLaborFields: Equatable, Sendable {
    let workers: String
    let hours: String
    let unitRate: String
    let workloadUnit: LaborWorkloadUnit
    let teamName: String
    let workType: String
    let isSettled: Bool

    init(workers: String, hours: String, unitRate: String, workloadUnit: LaborWorkloadUnit, teamName: String, workType: String, isSettled: Bool) {
        self.workers = workers
        self.hours = hours
        self.unitRate = unitRate
        self.workloadUnit = workloadUnit
        self.teamName = teamName
        self.workType = workType
        self.isSettled = isSettled
    }

    init(object: [String: Any]) throws {
        guard object["date"] is String else { throw RepositoryError.invalidRecord("labor date") }
        for key in ["workers", "hours", "unitRate", "teamName", "workType", "workloadUnit"] {
            if let value = object[key], !(value is String) { throw RepositoryError.invalidRecord("labor " + key) }
        }
        if let value = object["isSettled"], !(value is Bool) { throw RepositoryError.invalidRecord("labor settlement") }
        let rawUnit = object["workloadUnit"] as? String ?? LaborWorkloadUnit.legacyUnspecified.rawValue
        guard let unit = LaborWorkloadUnit(rawValue: rawUnit) else { throw RepositoryError.invalidRecord("labor unit") }
        self.init(workers: object["workers"] as? String ?? "", hours: object["hours"] as? String ?? "",
            unitRate: object["unitRate"] as? String ?? "", workloadUnit: unit,
            teamName: String((object["teamName"] as? String ?? "").prefix(120)),
            workType: String((object["workType"] as? String ?? "").prefix(120)), isSettled: object["isSettled"] as? Bool ?? false)
    }

    /// Missing workers means legacy total workload, not zero workers. Units are
    /// never converted: the rate is interpreted in the record's original unit.
    var workload: Decimal? {
        guard let hours = RepositoryMoney.parse(hours),
              let workers = workers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Decimal(1) : RepositoryMoney.parse(workers) else { return nil }
        return RepositoryMaterialArithmetic.product(workers, hours)
    }

    var amount: Decimal? {
        guard let workload, let rate = RepositoryMoney.parse(unitRate) else { return nil }
        return RepositoryMaterialArithmetic.product(workload, rate)
    }
}

struct RepositoryLaborSummary: Equatable, Sendable {
    let count: Int
    let unconfirmedUnitCount: Int
    let unpricedCount: Int
    let invalidValueCount: Int
    let hasPrecisionError: Bool
    let knownSubtotal: Decimal?
    let knownUnsettledSubtotal: Decimal?
    var total: Decimal? { unpricedCount == 0 && invalidValueCount == 0 ? knownSubtotal : nil }
    var unsettled: Decimal? { unpricedCount == 0 && invalidValueCount == 0 ? knownUnsettledSubtotal : nil }
}

struct RepositoryLaborPage: Sendable {
    let page: RepositoryPage
    let summary: RepositoryLaborSummary
}

struct RepositoryLaborAccumulator {
    private var count = 0
    private var unconfirmed = 0
    private var unpriced = 0
    private var invalid = 0
    private var precisionError = false
    private var subtotal = Decimal.zero
    private var unsettled = Decimal.zero

    mutating func add(_ fields: RepositoryLaborFields) {
        count += 1
        if fields.workloadUnit == .legacyUnspecified { unconfirmed += 1 }
        let workersText = fields.workers.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let workers = workersText.isEmpty ? Decimal(1) : RepositoryMoney.parse(workersText),
              let hours = RepositoryMoney.parse(fields.hours) else { invalid += 1
              return }
        guard let workload = RepositoryMaterialArithmetic.product(workers, hours) else { precisionError = true
        return }
        guard !fields.unitRate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { unpriced += 1
        return }
        guard let rate = RepositoryMoney.parse(fields.unitRate) else { invalid += 1
        return }
        guard let amount = RepositoryMaterialArithmetic.product(workload, rate) else { precisionError = true
        return }
        let total = DecimalMath.add(subtotal, amount)
        let pending = fields.isSettled ? unsettled : DecimalMath.add(unsettled, amount)
        if total.isNaN || pending.isNaN { precisionError = true } else { subtotal = total
        unsettled = pending }
    }

    func result() -> RepositoryLaborSummary {
        RepositoryLaborSummary(count: count, unconfirmedUnitCount: unconfirmed, unpricedCount: unpriced, invalidValueCount: invalid,
            hasPrecisionError: precisionError, knownSubtotal: precisionError ? nil : subtotal, knownUnsettledSubtotal: precisionError ? nil : unsettled)
    }
}
