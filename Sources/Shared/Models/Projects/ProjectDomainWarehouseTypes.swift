import Foundation

enum WarehouseMovementType: String, CaseIterable, Codable, Sendable {
    case inbound = "入库"
    case outbound = "出库"

    var displayName: String {
        switch self {
        case .inbound:
            return AppLocalization.string("warehouse_movement_type_inbound")
        case .outbound:
            return AppLocalization.string("warehouse_movement_type_outbound")
        }
    }

    var sign: Decimal {
        switch self {
        case .inbound: return 1
        case .outbound: return -1
        }
    }

    var systemImage: String {
        switch self {
        case .inbound: return "tray.and.arrow.down.fill"
        case .outbound: return "tray.and.arrow.up.fill"
        }
    }
}

struct ProjectWarehouseMovement: Identifiable, Codable, Sendable {
    var id = UUID()
    var projectId: UUID
    var date: BusinessDateValue
    var movementType: WarehouseMovementType
    var materialName: String
    var specification: String
    var unit: String
    @NonNegativeDecimal var quantity: QuantityValue
    var counterparty: String
    var handler: String
    var note: String
    var linkedDocumentIds: [UUID]
    var createdAt: BusinessDateValue
    var origin: BusinessRecordOrigin?

    init(
        id: UUID = UUID(),
        projectId: UUID,
        date: BusinessDateValue = .today(),
        movementType: WarehouseMovementType = .inbound,
        materialName: String = "",
        specification: String = "",
        unit: String = "",
        quantity: QuantityValue = .empty,
        counterparty: String = "",
        handler: String = "",
        note: String = "",
        linkedDocumentIds: [UUID] = [],
        createdAt: BusinessDateValue = .now(),
        origin: BusinessRecordOrigin? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.date = date
        self.movementType = movementType
        self.materialName = materialName
        self.specification = specification
        self.unit = unit
        self.quantity = quantity
        self.counterparty = counterparty
        self.handler = handler
        self.note = note
        self.linkedDocumentIds = linkedDocumentIds
        self.createdAt = createdAt
        self.origin = origin
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, date, movementType, materialName, specification, unit, quantity, counterparty, handler, note, linkedDocumentIds, createdAt, origin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        date = try container.decodeIfPresent(BusinessDateValue.self, forKey: .date) ?? .empty
        movementType = try container.decodeStringEnum(
            WarehouseMovementType.self,
            forKey: .movementType,
            default: .inbound
        )
        materialName = try container.decodeIfPresent(String.self, forKey: .materialName) ?? ""
        specification = try container.decodeIfPresent(String.self, forKey: .specification) ?? ""
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        quantity = try container.decodeIfPresent(QuantityValue.self, forKey: .quantity) ?? .empty
        counterparty = try container.decodeIfPresent(String.self, forKey: .counterparty) ?? ""
        handler = try container.decodeIfPresent(String.self, forKey: .handler) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        linkedDocumentIds = try container.decodeIfPresent([UUID].self, forKey: .linkedDocumentIds) ?? []
        createdAt = try container.decodeIfPresent(BusinessDateValue.self, forKey: .createdAt) ?? .empty
        origin = try container.decodeIfPresent(BusinessRecordOrigin.self, forKey: .origin)
    }

    var normalizedMovementType: WarehouseMovementType {
        movementType
    }
}
