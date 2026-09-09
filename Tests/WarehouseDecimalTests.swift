import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct WarehouseDecimalTests {
    @Test func decimalAggregationCancelsExactly() {
        let projectId = UUID()
        let movements = [
            ProjectWarehouseMovement(projectId: projectId, movementType: .inbound, materialName: "水泥", unit: "吨", quantity: "0.3"),
            ProjectWarehouseMovement(projectId: projectId, movementType: .outbound, materialName: "水泥", unit: "吨", quantity: "0.1"),
            ProjectWarehouseMovement(projectId: projectId, movementType: .outbound, materialName: "水泥", unit: "吨", quantity: "0.2")
        ]

        let line = WarehouseStockCalculator.stockLines(for: projectId, movements: movements).first
        #expect(line?.quantity == 0)
        #expect(line.map { WarehouseStockCalculator.quantityText($0.quantity) } == "0")
    }
}
