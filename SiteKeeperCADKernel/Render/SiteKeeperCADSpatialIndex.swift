extension SiteKeeperCADKernel {
    struct CADSpatialIndex {
        struct Entry: Equatable, Codable {
            var id: CADEntity.ID
            var bounds: CADBounds
            var layerID: String
            var layoutID: String
            var hasUsableBounds: Bool
        }

        private var entries: [Entry]

        init(database: CADDatabase) {
            self.init(entities: database.entities)
        }

        init(entities: [CADEntity]) {
            entries = entities.map { entity in
                let bounds = CADSpatialIndex.effectiveBounds(for: entity)
                return Entry(
                    id: entity.id,
                    bounds: bounds,
                    layerID: entity.layerID,
                    layoutID: entity.layoutID,
                    hasUsableBounds: !bounds.isEmpty
                )
            }
        }

        var entityCount: Int {
            entries.count
        }

        var missingBoundsCount: Int {
            entries.filter { !$0.hasUsableBounds }.count
        }

        func query(
            _ viewportBounds: CADBounds,
            layerIDs: Set<String>? = nil,
            layoutID: String? = nil
        ) -> [CADEntity.ID] {
            entries.compactMap { entry in
                guard layoutID == nil || entry.layoutID == layoutID else { return nil }
                guard layerIDs == nil || layerIDs?.contains(entry.layerID) == true else { return nil }
                guard viewportBounds.isEmpty || entry.bounds.intersects(viewportBounds) else { return nil }
                return entry.id
            }
        }

        func queryEntries(
            _ viewportBounds: CADBounds,
            layerIDs: Set<String>? = nil,
            layoutID: String? = nil
        ) -> [Entry] {
            let ids = Set(query(viewportBounds, layerIDs: layerIDs, layoutID: layoutID))
            return entries.filter { ids.contains($0.id) }
        }

        static func effectiveBounds(for entity: CADEntity) -> CADBounds {
            if !entity.bounds.isEmpty {
                return entity.bounds
            }
            if let path = entity.path, !path.bounds.isEmpty {
                return path.bounds
            }
            if let text = entity.text {
                return CADBounds(
                    minX: text.insertionPoint.x,
                    minY: text.insertionPoint.y,
                    maxX: text.insertionPoint.x,
                    maxY: text.insertionPoint.y
                )
            }
            return .empty
        }
    }
}
