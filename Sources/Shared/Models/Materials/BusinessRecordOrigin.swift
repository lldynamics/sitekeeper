import Foundation

/// Historical provenance survives deletion of the originating business record.
struct BusinessRecordOrigin: Codable, Equatable, Sendable {
    var materialItemID: UUID?
    var warehouseMovementID: UUID?
    var unitPrice: MoneyValue?
}
