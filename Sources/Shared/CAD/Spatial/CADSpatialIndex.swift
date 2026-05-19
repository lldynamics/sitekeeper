import Foundation

extension NativeCAD {
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
                entity.isRenderable && !Self.indexBounds(for: entity).isEmpty
            }
            var rootBounds = renderableEntities.reduce(Kernel.CADBounds.empty) { partial, entity in
                partial.union(Self.effectiveBounds(for: entity))
            }
            if !rootBounds.isEmpty {
                let padding = max(max(rootBounds.width, rootBounds.height) * 0.001, 1)
                rootBounds = rootBounds.expanded(by: padding)
            }

            self.entries = renderableEntities.flatMap { entity in
                Self.indexBounds(for: entity).map { bounds in
                    Entry(
                        id: entity.id,
                        bounds: bounds,
                        layerID: entity.layerID,
                        layoutID: entity.layoutID
                    )
                }
            }
            self.entitiesByID = Dictionary(uniqueKeysWithValues: renderableEntities.map { ($0.id, $0) })

            var tree = CADQuadTree<Entry>(bounds: rootBounds)
            for entry in entries where !entry.bounds.isEmpty {
                tree.insert(entry, bounds: entry.bounds)
            }
            self.tree = tree
        }

        var entityCount: Int {
            entitiesByID.count
        }

        var indexedEntityCount: Int {
            entitiesByID.count
        }

        func query(
            _ viewportBounds: Kernel.CADBounds,
            layerIDs: Set<String>? = nil,
            layoutID: String? = nil
        ) -> [Kernel.CADEntity] {
            let candidateEntries = viewportBounds.isEmpty ? entries : tree.query(viewportBounds)
            var seen: Set<Kernel.CADEntity.ID> = []
            var result: [Kernel.CADEntity] = []
            result.reserveCapacity(candidateEntries.count)
            for entry in candidateEntries {
                guard layerIDs == nil || layerIDs?.contains(entry.layerID) == true else { continue }
                guard layoutID == nil || entry.layoutID == layoutID else { continue }
                guard seen.insert(entry.id).inserted, let entity = entitiesByID[entry.id] else { continue }
                result.append(entity)
            }
            return result
        }

        func queryIDs(
            _ viewportBounds: Kernel.CADBounds,
            layerIDs: Set<String>? = nil,
            layoutID: String? = nil
        ) -> [Kernel.CADEntity.ID] {
            query(viewportBounds, layerIDs: layerIDs, layoutID: layoutID).map(\.id)
        }

        static func effectiveBounds(for entity: Kernel.CADEntity) -> Kernel.CADBounds {
            indexBounds(for: entity).reduce(Kernel.CADBounds.empty) { $0.union($1) }
        }

        private static func indexBounds(for entity: Kernel.CADEntity) -> [Kernel.CADBounds] {
            var indexBounds: [Kernel.CADBounds] = []
            if !entity.bounds.isEmpty {
                indexBounds.append(entity.bounds)
            }
            if let path = entity.path, !path.bounds.isEmpty {
                indexBounds.append(path.bounds)
            }
            if let text = entity.text {
                indexBounds.append(fallbackTextBounds(for: text))
            }
            return indexBounds.filter(\.isFiniteForSpatialIndex)
        }

        private static func fallbackTextBounds(for text: Kernel.CADTextRun) -> Kernel.CADBounds {
            let height = max(abs(text.height), abs(text.boxHeight ?? 0), 1)
            let widthFactor = max(text.widthFactor ?? 1, 0.05)
            let estimatedWidth = Double(max(text.displayText.count, 1)) * height * 0.65 * widthFactor
            let width = max(abs(text.boxWidth ?? 0), estimatedWidth, height)
            let boxHeight = max(abs(text.boxHeight ?? 0), height)
            let origin = text.insertionPoint
            let corners = [
                Kernel.CADPoint(x: 0, y: 0),
                Kernel.CADPoint(x: width, y: 0),
                Kernel.CADPoint(x: width, y: boxHeight),
                Kernel.CADPoint(x: 0, y: boxHeight)
            ]
            let angle = text.rotationRadians
            let cosValue = Darwin.cos(angle)
            let sinValue = Darwin.sin(angle)

            return corners.reduce(Kernel.CADBounds.empty) { partial, point in
                let rotated = Kernel.CADPoint(
                    x: origin.x + point.x * cosValue - point.y * sinValue,
                    y: origin.y + point.x * sinValue + point.y * cosValue
                )
                return partial.including(rotated)
            }.expanded(by: max(height * 0.1, 0.01))
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
