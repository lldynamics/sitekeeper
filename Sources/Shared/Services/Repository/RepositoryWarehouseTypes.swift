import Foundation

struct RepositoryWarehouseFields: Equatable, Sendable {
    let materialName: String
    let specification: String
    let unit: String
    let quantity: String
    let movementType: WarehouseMovementType
    let stockKey: String?
    let stockSearch: String

    init(object: [String: Any]) throws {
        guard let type = (object["movementType"] as? String).flatMap(WarehouseMovementType.init(rawValue:)) else { throw RepositoryError.invalidRecord("warehouse type") }
        materialName = object["materialName"] as? String ?? ""
        specification = object["specification"] as? String ?? ""
        unit = object["unit"] as? String ?? ""
        quantity = object["quantity"] as? String ?? ""
        movementType = type
        let components = [materialName, specification, unit].map { MaterialIdentity.normalizedComponent($0).precomposedStringWithCanonicalMapping }
        // Structured components avoid collisions when a name or specification contains '|'.
        stockKey = components[0].isEmpty ? nil : String(decoding: try JSONEncoder().encode(components), as: UTF8.self)
        stockSearch = RepositorySearch.normalize(components.joined(separator: "\n"))
    }
}

struct RepositoryStockQuery: Equatable, Sendable {
    let projectID: UUID
    var searchText = ""
    var normalizedSearch: String { RepositorySearch.normalize(MaterialIdentity.normalizedComponent(searchText)) }
}

struct RepositoryStockCursor: Equatable, Sendable {
    let query: RepositoryStockQuery
    let revision: Int
    let key: String
}

struct RepositoryStockLine: Equatable, Identifiable, Sendable {
    let id: String
    let materialName: String
    let specification: String
    let unit: String
    let movementCount: Int
    let invalidQuantityCount: Int
    let hasPrecisionError: Bool
    let inbound: Decimal?
    let outbound: Decimal?
    let balance: Decimal?
}

struct RepositoryStockPage: Sendable {
    let items: [RepositoryStockLine]
    let next: RepositoryStockCursor?
    let revision: Int
    let totalMaterials: Int
    let unnamedMovements: Int
}

struct RepositoryStockAccumulator {
    private var count = 0
    private var invalid = 0
    private var precisionError = false
    private var inbound = Decimal.zero
    private var outbound = Decimal.zero

    mutating func add(quantity: String?, type: String?) throws {
        guard let type, let type = WarehouseMovementType(rawValue: type) else { throw RepositoryError.integrityFailure }
        count += 1
        guard let quantity, let value = RepositoryMoney.parse(quantity) else { invalid += 1
        return }
        let result = DecimalMath.add(type == .inbound ? inbound : outbound, value)
        if result.isNaN { precisionError = true }
        else if type == .inbound { inbound = result }
        else { outbound = result }
    }

    func line(fields: RepositoryWarehouseFields) throws -> RepositoryStockLine {
        guard let key = fields.stockKey else { throw RepositoryError.integrityFailure }
        let balance = DecimalMath.subtract(inbound, outbound)
        let precisionError = precisionError || balance.isNaN
        let valid = invalid == 0 && !precisionError
        return RepositoryStockLine(id: key, materialName: fields.materialName.trimmingCharacters(in: .whitespacesAndNewlines),
            specification: fields.specification.trimmingCharacters(in: .whitespacesAndNewlines), unit: fields.unit.trimmingCharacters(in: .whitespacesAndNewlines),
            movementCount: count, invalidQuantityCount: invalid, hasPrecisionError: precisionError,
            inbound: valid ? inbound : nil, outbound: valid ? outbound : nil, balance: valid ? balance : nil)
    }
}

struct RepositoryWarehouseDraft: Codable, Sendable {
    var record: ProjectWarehouseMovement
    var quantityText: String

    init(record: ProjectWarehouseMovement) { self.record = record
    quantityText = record.quantity.wireText }
    init(from decoder: Decoder) throws { self.init(record: try ProjectWarehouseMovement(from: decoder)) }
    func encode(to encoder: Encoder) throws { try record.encode(to: encoder) }

    static func validate(_ value: ProjectWarehouseMovement) throws {
        guard let quantity = value.quantity.optionalDecimal, quantity > .zero else { throw RepositoryError.invalidQuantity }
        guard !MaterialIdentity.normalizedComponent(value.materialName).isEmpty, !value.date.isEmpty else { throw RepositoryError.invalidRecord("warehouse") }
    }

    func command() throws -> RepositoryCommand {
        guard let quantity = RepositoryMoney.input(quantityText) else { throw RepositoryError.invalidQuantity }
        var value = record
        value.quantity = QuantityValue(quantity)
        guard value.quantity.optionalDecimal == quantity else { throw RepositoryError.invalidQuantity }
        return .putWarehouseMovement(value)
    }
}

struct WarehouseRepository: Sendable {
    let repository: any BusinessRepository

    func stock(_ query: RepositoryStockQuery, after: RepositoryStockCursor? = nil, limit: Int = 50) async throws -> RepositoryStockPage {
        try await repository.stockPage(query, after: after, limit: limit)
    }
}
