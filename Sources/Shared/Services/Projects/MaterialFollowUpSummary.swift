import Foundation

enum MaterialFollowUpFilter: String, CaseIterable, Identifiable {
    case allPending
    case notPurchased
    case awaitingArrival

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allPending: AppLocalization.string("material_follow_up_all_pending")
        case .notPurchased: AppLocalization.string("未采购")
        case .awaitingArrival: AppLocalization.string("material_follow_up_awaiting_arrival")
        }
    }
}

/// Only fields appropriate for a supplier follow-up are copied into this row.
/// Prices, costs, financial records, contacts and free-form notes are excluded.
struct MaterialFollowUpRow: Identifiable {
    let id: UUID
    let name: String
    let specification: String
    let unit: String
    let supplier: String
    let purchaseStatus: MaterialPurchaseStatus
    let planned: QuantityValue
    let received: QuantityValue
    let remaining: QuantityValue

    var followUpStatus: MaterialFollowUpFilter {
        purchaseStatus == .notPurchased ? .notPurchased : .awaitingArrival
    }
}

enum MaterialFollowUpSummary {
    static func rows(
        projectID: UUID,
        materials: [MaterialItem],
        movements: [ProjectWarehouseMovement],
        supplier: String? = nil,
        filter: MaterialFollowUpFilter = .allPending
    ) -> [MaterialFollowUpRow] {
        let linkedInbound = movements.reduce(into: [UUID: [ProjectWarehouseMovement]]()) { result, movement in
            guard movement.projectId == projectID, movement.movementType == .inbound,
                  let materialID = movement.origin?.materialItemID else { return }
            result[materialID, default: []].append(movement)
        }

        return materials.compactMap { material -> MaterialFollowUpRow? in
            guard material.projectId == projectID,
                  material.purchaseStatus == .notPurchased || material.purchaseStatus == .purchased else { return nil }
            let supplierName = normalizedSupplier(material.supplier)
            if let supplier, supplierName != supplier { return nil }
            let inbound = linkedInbound[material.id] ?? []
            // Unlinked movements cannot be assigned by name: two plans may have
            // the same name, specification and unit but represent separate orders.
            // A plan's unit may have been edited after receipt. Never sum across
            // unlike units or infer a conversion from a historical movement.
            let materialUnit = material.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            let received: QuantityValue = inbound.allSatisfy({
                $0.quantity.isValid && !$0.quantity.isNegative
                    && $0.unit.trimmingCharacters(in: .whitespacesAndNewlines) == materialUnit
            })
                ? inbound.reduce(.zero) { $0 + $1.quantity }
                : .empty
            let remaining: QuantityValue
            if material.quantity.isValid, received.isValid,
               let difference = (material.quantity - received).optionalDecimal {
                remaining = QuantityValue(max(.zero, difference))
            } else {
                remaining = .empty
            }
            // Unknown quantities stay visible for review instead of implying
            // that the order has been completely received.
            guard !remaining.isZero else { return nil }
            let row = MaterialFollowUpRow(
                id: material.id, name: material.name, specification: material.specification,
                unit: material.unit, supplier: supplierName, purchaseStatus: material.purchaseStatus,
                planned: material.quantity, received: received, remaining: remaining
            )
            guard filter == .allPending || row.followUpStatus == filter else { return nil }
            return row
        }
        .sorted {
            let left = [$0.supplier, $0.name, $0.specification, $0.unit]
            let right = [$1.supplier, $1.name, $1.specification, $1.unit]
            for (lhs, rhs) in zip(left, right) where lhs != rhs {
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func suppliers(in rows: [MaterialFollowUpRow]) -> [String] {
        Set(rows.map(\.supplier)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func supplierDisplayName(_ supplier: String) -> String {
        supplier.isEmpty ? AppLocalization.string("material_follow_up_supplier_unassigned") : supplier
    }

    static func quantityText(_ quantity: QuantityValue, unit: String) -> String {
        guard quantity.isValid else { return AppLocalization.string("material_follow_up_quantity_review") }
        return [quantity.wireText, unit].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func exportText(
        projectName: String,
        rows: [MaterialFollowUpRow],
        supplier: String?,
        filter: MaterialFollowUpFilter
    ) -> String {
        var lines = [
            AppLocalization.string("material_follow_up_title"),
            String(format: AppLocalization.string("material_follow_up_project_format"), singleLine(projectName)),
            String(format: AppLocalization.string("material_follow_up_supplier_format"), singleLine(supplier.map(supplierDisplayName) ?? AppLocalization.string("material_follow_up_all_suppliers"))),
            String(format: AppLocalization.string("material_follow_up_filter_format"), filter.displayName),
            AppLocalization.string("material_follow_up_scope_note"),
            AppLocalization.string("material_follow_up_receipt_note"),
            ""
        ]
        for (index, row) in rows.enumerated() {
            lines.append("\(index + 1). \(singleLine(row.name))")
            lines.append(String(format: AppLocalization.string("material_follow_up_specification_format"), singleLine(row.specification.isEmpty ? AppLocalization.string("material_follow_up_unspecified") : row.specification)))
            lines.append(String(format: AppLocalization.string("material_follow_up_supplier_format"), singleLine(supplierDisplayName(row.supplier))))
            lines.append(String(format: AppLocalization.string("material_follow_up_filter_format"), row.followUpStatus.displayName))
            lines.append(String(format: AppLocalization.string("material_follow_up_quantities_format"),
                                quantityText(row.planned, unit: singleLine(row.unit)),
                                quantityText(row.received, unit: singleLine(row.unit)),
                                quantityText(row.remaining, unit: singleLine(row.unit))))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func normalizedSupplier(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
    }
}
