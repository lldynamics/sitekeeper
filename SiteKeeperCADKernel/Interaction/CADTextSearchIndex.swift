import Foundation

extension SiteKeeperCADKernel {
    struct CADTextSearchResult: Identifiable, Equatable, Codable {
        var id: String
        var entityId: CADEntity.ID
        var layoutId: String
        var bounds: CADBounds
        var previewText: String
        var displayText: String
        var worldPoint: CADPoint
        var targetViewport: CADViewport

        var entityID: CADEntity.ID { entityId }
        var text: String { displayText }
        var location: CADPoint { worldPoint }
    }

    struct CADTextSearchIndex {
        private var entries: [CADTextSearchResult]

        init(database: CADDatabase, layoutID: String? = nil) {
            let resolvedEntities = CADBlockResolver().resolve(entities: database.entities, in: database)
            entries = resolvedEntities.compactMap { entity in
                guard let text = entity.text else { return nil }
                guard layoutID == nil || entity.layoutID == layoutID else { return nil }
                let bounds = Self.searchBounds(for: entity, text: text)
                let worldPoint = bounds.isEmpty ? text.insertionPoint : bounds.center
                return CADTextSearchResult(
                    id: entity.id.uuidString,
                    entityId: entity.id,
                    layoutId: entity.layoutID,
                    bounds: bounds,
                    previewText: text.displayText,
                    displayText: text.displayText,
                    worldPoint: worldPoint,
                    targetViewport: Self.targetViewport(
                        entityID: entity.id,
                        layoutID: entity.layoutID,
                        bounds: bounds,
                        fallbackPoint: text.insertionPoint
                    )
                )
            }
        }

        func search(_ keyword: String) -> [CADTextSearchResult] {
            let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { return [] }
            return entries
                .filter { $0.displayText.localizedCaseInsensitiveContains(needle) }
                .map { result in
                    var copy = result
                    copy.previewText = Self.previewText(for: result.displayText, keyword: needle)
                    return copy
                }
        }

        private static func searchBounds(for entity: CADEntity, text: CADTextRun) -> CADBounds {
            let effectiveBounds = CADSpatialIndex.effectiveBounds(for: entity)
            guard effectiveBounds.isEmpty else {
                return effectiveBounds.expanded(by: max(text.height * 0.25, 0))
            }

            let width = max(Double(text.displayText.count) * text.height * 0.6, text.height)
            return CADBounds(
                minX: text.insertionPoint.x,
                minY: text.insertionPoint.y,
                maxX: text.insertionPoint.x + width,
                maxY: text.insertionPoint.y + max(text.height, 0.0001)
            )
        }

        private static func targetViewport(
            entityID: CADEntity.ID,
            layoutID: String,
            bounds: CADBounds,
            fallbackPoint: CADPoint
        ) -> CADViewport {
            let targetBounds = bounds.isEmpty
                ? CADBounds(
                    minX: fallbackPoint.x,
                    minY: fallbackPoint.y,
                    maxX: fallbackPoint.x,
                    maxY: fallbackPoint.y
                )
                : bounds
            let focusBounds = targetBounds.expanded(by: max(max(targetBounds.width, targetBounds.height) * 0.6, 10))
            return CADViewport(
                id: "search-\(entityID.uuidString)",
                layoutID: layoutID,
                viewCenter: focusBounds.center,
                viewHeight: max(focusBounds.height, 20),
                clipBounds: focusBounds
            )
        }

        private static func previewText(for text: String, keyword: String) -> String {
            guard text.count > 80 else { return text }
            guard let range = text.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) else {
                return String(text.prefix(77)) + "..."
            }
            let lowerBound = text.distance(from: text.startIndex, to: range.lowerBound)
            let startOffset = max(0, lowerBound - 24)
            let endOffset = min(text.count, startOffset + 80)
            let start = text.index(text.startIndex, offsetBy: startOffset)
            let end = text.index(text.startIndex, offsetBy: endOffset)
            let prefix = startOffset > 0 ? "..." : ""
            let suffix = endOffset < text.count ? "..." : ""
            return prefix + String(text[start..<end]) + suffix
        }
    }
}
