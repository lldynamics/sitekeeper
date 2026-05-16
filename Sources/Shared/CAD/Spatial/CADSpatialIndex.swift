extension CADPoC {
    struct CADSpatialIndex {
        typealias Kernel = SiteKeeperCADKernel

        struct Entry: Equatable {
            var id: Kernel.CADEntity.ID
            var bounds: Kernel.CADBounds
            var layerID: String
            var layoutID: String
        }

        private let entries: [Entry]
        private let entitiesByID: [Kernel.CADEntity.ID: Kernel.CADEntity]
        private let tree: CADQuadTree<Entry>

        init(entities: [Kernel.CADEntity] = []) {
            let renderableEntities = entities.filter { entity in
                entity.isRenderable && Self.effectiveBounds(for: entity).isFiniteForSpatialIndex
            }
            var rootBounds = renderableEntities.reduce(Kernel.CADBounds.empty) { partial, entity in
                partial.union(Self.effectiveBounds(for: entity))
            }
            if !rootBounds.isEmpty {
                let padding = max(max(rootBounds.width, rootBounds.height) * 0.001, 1)
                rootBounds = rootBounds.expanded(by: padding)
            }

            self.entries = renderableEntities.map { entity in
                Entry(
                    id: entity.id,
                    bounds: Self.effectiveBounds(for: entity),
                    layerID: entity.layerID,
                    layoutID: entity.layoutID
                )
            }
            self.entitiesByID = Dictionary(uniqueKeysWithValues: renderableEntities.map { ($0.id, $0) })

            var tree = CADQuadTree<Entry>(bounds: rootBounds)
            for entry in entries where !entry.bounds.isEmpty {
                tree.insert(entry, bounds: entry.bounds)
            }
            self.tree = tree
        }

        var entityCount: Int {
            entries.count
        }

        var indexedEntityCount: Int {
            tree.count
        }

        func query(
            _ viewportBounds: Kernel.CADBounds,
            layerIDs: Set<String>? = nil,
            layoutID: String? = nil
        ) -> [Kernel.CADEntity] {
            let candidateEntries = viewportBounds.isEmpty ? entries : tree.query(viewportBounds)
            return candidateEntries.compactMap { entry in
                guard layerIDs == nil || layerIDs?.contains(entry.layerID) == true else { return nil }
                guard layoutID == nil || entry.layoutID == layoutID else { return nil }
                return entitiesByID[entry.id]
            }
        }

        func queryIDs(
            _ viewportBounds: Kernel.CADBounds,
            layerIDs: Set<String>? = nil,
            layoutID: String? = nil
        ) -> [Kernel.CADEntity.ID] {
            query(viewportBounds, layerIDs: layerIDs, layoutID: layoutID).map(\.id)
        }

        static func effectiveBounds(for entity: Kernel.CADEntity) -> Kernel.CADBounds {
            if !entity.bounds.isEmpty {
                return entity.bounds
            }
            if let path = entity.path, !path.bounds.isEmpty {
                return path.bounds
            }
            if let text = entity.text {
                return Kernel.CADBounds(
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

private extension SiteKeeperCADKernel.CADBounds {
    var isFiniteForSpatialIndex: Bool {
        !isEmpty
            && minX.isFinite
            && minY.isFinite
            && maxX.isFinite
            && maxY.isFinite
    }
}
