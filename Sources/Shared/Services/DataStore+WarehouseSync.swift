import Foundation

extension DataStore {
    /// 根据仓库流水自动更新 MaterialItem.quantity。
    /// 匹配规则：同一项目下（name + specification + unit）一致的材料。
    /// 入库为正，出库为负；对已有材料更新 quantity，不存在则自动创建。
    func syncWarehouseToMaterialQuantity(for projectIDs: Set<UUID>? = nil) {
        var updatedMaterialItems = materialItems
        let targetProjectIDs = projectIDs ?? Set(projectWarehouseMovements.map(\.projectId))
        for pid in targetProjectIDs {
            var materialIndexByIdentity: [String: Int] = [:]
            var existingMaterialNames = Set<String>()
            for index in updatedMaterialItems.indices where updatedMaterialItems[index].projectId == pid {
                materialIndexByIdentity[warehouseMaterialIdentity(
                    name: updatedMaterialItems[index].name,
                    specification: updatedMaterialItems[index].specification,
                    unit: updatedMaterialItems[index].unit
                )] = index
                existingMaterialNames.insert(updatedMaterialItems[index].name)
            }

            let lines = WarehouseStockCalculator.stockLines(for: pid, movements: projectWarehouseMovements)
            for line in lines {
                if line.quantity == 0 && !existingMaterialNames.contains(line.materialName) {
                    continue
                }
                let qtyStr = WarehouseStockCalculator.quantityText(line.quantity)
                let identity = warehouseMaterialIdentity(
                    name: line.materialName,
                    specification: line.specification,
                    unit: line.unit
                )
                if let idx = materialIndexByIdentity[identity] {
                    updatedMaterialItems[idx].quantity = qtyStr
                } else if line.quantity > 0 {
                    let newItem = MaterialItem(
                        name: line.materialName,
                        quantity: qtyStr,
                        unit: line.unit,
                        specification: line.specification,
                        projectId: pid
                    )
                    updatedMaterialItems.append(newItem)
                    materialIndexByIdentity[identity] = updatedMaterialItems.count - 1
                    existingMaterialNames.insert(newItem.name)
                }
            }
        }
        replaceMaterialItems(updatedMaterialItems)
    }

    private func warehouseMaterialIdentity(name: String, specification: String, unit: String) -> String {
        [name, specification, unit].joined(separator: "\u{1f}")
    }
}
