import CoreGraphics
import Foundation

struct DXFLayerStat: Identifiable {
    let name: String
    let count: Int
    let kindCounts: [DXFPreviewModel.PrimitiveKind: Int]

    var id: String { name }

    var dominantKinds: [DXFPreviewModel.PrimitiveKind] {
        kindCounts
            .sorted {
                if $0.value == $1.value {
                    return $0.key.rawValue < $1.key.rawValue
                }
                return $0.value > $1.value
            }
            .map(\.key)
    }

    var kindSummaryText: String {
        dominantKinds
            .prefix(3)
            .map(\.displayName)
            .joined(separator: " / ")
    }
}

struct DXFVisibleGeometry {
    let segments: [DXFPreviewModel.Segment]
    let polylines: [DXFPreviewModel.Polyline]
    let circles: [DXFPreviewModel.Circle]
    let texts: [DXFPreviewModel.TextEntity]

    static let empty = DXFVisibleGeometry(
        segments: [],
        polylines: [],
        circles: [],
        texts: []
    )
}

struct DXFCanvasIndex {
    let model: DXFPreviewModel
    let geometryIndex: DXFSpatialGeometryIndex
    let visibleLayers: Set<String>
    let searchText: String
    let layerSearchText: String

    init(
        model: DXFPreviewModel,
        geometryIndex: DXFSpatialGeometryIndex? = nil,
        visibleLayers: Set<String>,
        searchText: String,
        layerSearchText: String
    ) {
        self.model = model
        self.geometryIndex = geometryIndex ?? DXFSpatialGeometryIndex(model: model)
        self.visibleLayers = visibleLayers
        self.searchText = searchText
        self.layerSearchText = layerSearchText
    }

    var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedSearchQuery: DXFTextSearchQuery {
        DXFTextSearchQuery.parse(from: normalizedSearchText)
    }

    var normalizedLayerSearchText: String {
        layerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var layerStats: [DXFLayerStat] {
        geometryIndex.layerStats
    }

    var filteredLayerStats: [DXFLayerStat] {
        guard !normalizedLayerSearchText.isEmpty else { return layerStats }
        let query = normalizedLayerSearchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return layerStats.filter { layer in
            let normalizedName = layer.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let normalizedKinds = layer.kindSummaryText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if normalizedName.contains(query) || normalizedKinds.contains(query) {
                return true
            }
            return layer.kindCounts.keys.contains { $0.matches(searchToken: query) }
        }
    }

    var primaryLayerStats: [DXFLayerStat] {
        Array(layerStats.prefix(8))
    }

    var matchedTexts: [DXFPreviewModel.TextEntity] {
        let query = parsedSearchQuery
        guard query.isActive else { return [] }
        return model.texts.filter { text in
            guard visibleLayers.isEmpty || visibleLayers.contains(text.layer) else { return false }
            let layerText = text.layer.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if !query.layerTokens.allSatisfy({ layerText.contains($0) }) {
                return false
            }

            let styleText = [text.styleName, text.fontFile, text.bigFontFile]
                .compactMap { $0 }
                .joined(separator: " ")
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if !query.styleTokens.allSatisfy({ styleText.contains($0) }) {
                return false
            }

            if !query.kindTokens.allSatisfy({ text.kind.matches(searchToken: $0) }) {
                return false
            }

            if query.freeTextTokens.isEmpty {
                return true
            }

            let value = text.value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let rawValue = (text.rawValue ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let combined = "\(value) \(rawValue)"
            return query.freeTextTokens.allSatisfy { combined.contains($0) }
        }
    }

    func visibleGeometry(in viewport: CGRect) -> DXFVisibleGeometry {
        geometryIndex.query(viewport: viewport, visibleLayers: visibleLayers)
    }

    func selectedSearchText(id: UUID?) -> DXFPreviewModel.TextEntity? {
        guard let id else { return nil }
        return matchedTexts.first { $0.id == id }
    }

    func visibleSnapSourcePoints(limit: Int = 6000) -> DXFSnapPointSet {
        guard !visibleLayers.isEmpty else { return DXFSnapPointSet(points: []) }
        let all = geometryIndex.queryAll(visibleLayers: visibleLayers)
        return snapSourcePoints(from: all, limit: limit)
    }

    func visibleSnapSourcePoints(in viewport: CGRect, limit: Int = 6000) -> DXFSnapPointSet {
        guard !visibleLayers.isEmpty else { return DXFSnapPointSet(points: []) }
        let partial = geometryIndex.query(viewport: viewport, visibleLayers: visibleLayers)
        return snapSourcePoints(from: partial, limit: limit)
    }

    func layerBounds(for layerName: String) -> CGRect? {
        geometryIndex.layerBounds(for: layerName)
    }

    private func snapSourcePoints(from geometry: DXFVisibleGeometry, limit: Int) -> DXFSnapPointSet {
        var points: [DXFSnapSourcePoint] = []
        points.reserveCapacity(min(
            geometry.segments.count * 3 +
            geometry.polylines.count * 8 +
            geometry.circles.count * 5 +
            geometry.texts.count * 2,
            limit
        ))

        func append(_ point: DXFSnapSourcePoint) -> Bool {
            guard points.count < limit else { return false }
            points.append(point)
            return points.count < limit
        }

        for segment in geometry.segments {
            guard append(.init(
                point: segment.from,
                kind: .endpoint,
                layer: segment.layer,
                primitiveKind: segment.kind,
                styleRGB: segment.style.rgb,
                styleWidth: segment.style.width,
                styleName: nil
            )) else { return DXFSnapPointSet(points: points) }
            guard append(.init(
                point: segment.to,
                kind: .endpoint,
                layer: segment.layer,
                primitiveKind: segment.kind,
                styleRGB: segment.style.rgb,
                styleWidth: segment.style.width,
                styleName: nil
            )) else { return DXFSnapPointSet(points: points) }
            guard append(.init(
                point: CGPoint(x: (segment.from.x + segment.to.x) / 2, y: (segment.from.y + segment.to.y) / 2),
                kind: .midpoint,
                layer: segment.layer,
                primitiveKind: segment.kind,
                styleRGB: segment.style.rgb,
                styleWidth: segment.style.width,
                styleName: nil
            )) else { return DXFSnapPointSet(points: points) }
        }
        for polyline in geometry.polylines {
            for point in polyline.points {
                guard append(.init(
                    point: point,
                    kind: .endpoint,
                    layer: polyline.layer,
                    primitiveKind: polyline.kind,
                    styleRGB: polyline.style.rgb,
                    styleWidth: polyline.style.width,
                    styleName: nil
                )) else { return DXFSnapPointSet(points: points) }
            }
            if polyline.points.count >= 2 {
                for idx in 1..<polyline.points.count {
                    let p0 = polyline.points[idx - 1]
                    let p1 = polyline.points[idx]
                    guard append(.init(
                        point: CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2),
                        kind: .midpoint,
                        layer: polyline.layer,
                        primitiveKind: polyline.kind,
                        styleRGB: polyline.style.rgb,
                        styleWidth: polyline.style.width,
                        styleName: nil
                    )) else { return DXFSnapPointSet(points: points) }
                }
            }
            if let center = centerPoint(of: polyline.points) {
                guard append(.init(
                    point: center,
                    kind: .center,
                    layer: polyline.layer,
                    primitiveKind: polyline.kind,
                    styleRGB: polyline.style.rgb,
                    styleWidth: polyline.style.width,
                    styleName: nil
                )) else { return DXFSnapPointSet(points: points) }
            }
        }
        for circle in geometry.circles {
            guard append(.init(
                point: circle.center,
                kind: .center,
                layer: circle.layer,
                primitiveKind: circle.kind,
                styleRGB: circle.style.rgb,
                styleWidth: circle.style.width,
                styleName: nil
            )) else { return DXFSnapPointSet(points: points) }
            guard append(.init(
                point: CGPoint(x: circle.center.x + circle.radius, y: circle.center.y),
                kind: .endpoint,
                layer: circle.layer,
                primitiveKind: circle.kind,
                styleRGB: circle.style.rgb,
                styleWidth: circle.style.width,
                styleName: nil
            )) else { return DXFSnapPointSet(points: points) }
            guard append(.init(
                point: CGPoint(x: circle.center.x - circle.radius, y: circle.center.y),
                kind: .endpoint,
                layer: circle.layer,
                primitiveKind: circle.kind,
                styleRGB: circle.style.rgb,
                styleWidth: circle.style.width,
                styleName: nil
            )) else { return DXFSnapPointSet(points: points) }
            guard append(.init(
                point: CGPoint(x: circle.center.x, y: circle.center.y + circle.radius),
                kind: .endpoint,
                layer: circle.layer,
                primitiveKind: circle.kind,
                styleRGB: circle.style.rgb,
                styleWidth: circle.style.width,
                styleName: nil
            )) else { return DXFSnapPointSet(points: points) }
            guard append(.init(
                point: CGPoint(x: circle.center.x, y: circle.center.y - circle.radius),
                kind: .endpoint,
                layer: circle.layer,
                primitiveKind: circle.kind,
                styleRGB: circle.style.rgb,
                styleWidth: circle.style.width,
                styleName: nil
            )) else { return DXFSnapPointSet(points: points) }
        }
        for text in geometry.texts {
            guard append(.init(
                point: text.point,
                kind: .endpoint,
                layer: text.layer,
                primitiveKind: text.kind,
                styleRGB: text.style.rgb,
                styleWidth: text.style.width,
                styleName: text.styleName
            )) else { return DXFSnapPointSet(points: points) }
        }
        return DXFSnapPointSet(points: points)
    }

    private func centerPoint(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { result, point in
            CGPoint(x: result.x + point.x, y: result.y + point.y)
        }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
}

private struct DXFTextSearchQuery {
    var freeTextTokens: [String]
    var layerTokens: [String]
    var styleTokens: [String]
    var kindTokens: [String]

    var isActive: Bool {
        !freeTextTokens.isEmpty || !layerTokens.isEmpty || !styleTokens.isEmpty || !kindTokens.isEmpty
    }

    static func parse(from source: String) -> DXFTextSearchQuery {
        let normalizedTokens = source
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }

        var query = DXFTextSearchQuery(freeTextTokens: [], layerTokens: [], styleTokens: [], kindTokens: [])
        for token in normalizedTokens {
            if let value = token.value(afterAnyPrefix: ["layer:", "图层:"]) {
                query.layerTokens.append(value)
            } else if let value = token.value(afterAnyPrefix: ["style:", "样式:"]) {
                query.styleTokens.append(value)
            } else if let value = token.value(afterAnyPrefix: ["kind:", "类型:", "实体:"]) {
                query.kindTokens.append(value)
            } else {
                query.freeTextTokens.append(token)
            }
        }
        return query
    }
}

private extension String {
    func value(afterAnyPrefix prefixes: [String]) -> String? {
        for prefix in prefixes where hasPrefix(prefix) {
            let value = String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

private extension DXFPreviewModel.PrimitiveKind {
    var displayName: String {
        switch self {
        case .line: return "直线"
        case .polyline: return "多段线"
        case .arc: return "圆弧"
        case .circle: return "圆"
        case .ellipse: return "椭圆"
        case .text: return "单行文字"
        case .mtext: return "多行文字"
        case .dimension: return "标注"
        case .hatch: return "填充"
        case .leader: return "引线"
        case .image: return "图像"
        case .wipeout: return "遮挡"
        case .blockRef: return "块参照"
        case .unknownProxy: return "代理对象"
        }
    }

    func matches(searchToken token: String) -> Bool {
        let normalized = token.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if rawValue.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalized) {
            return true
        }
        return displayName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(normalized)
    }
}

struct DXFSpatialGeometryIndex {
    private let model: DXFPreviewModel
    private let sceneBounds: CGRect
    private let columns: Int
    private let rows: Int
    private let cellWidth: CGFloat
    private let cellHeight: CGFloat

    private let segmentBounds: [CGRect]
    private let polylineBounds: [CGRect]
    private let circleBounds: [CGRect]
    private let textBounds: [CGRect]
    let layerStats: [DXFLayerStat]
    private let layerBoundsByName: [String: CGRect]

    private let segmentBuckets: [Int: [Int]]
    private let polylineBuckets: [Int: [Int]]
    private let circleBuckets: [Int: [Int]]
    private let textBuckets: [Int: [Int]]
    private let queryScratch = DXFSpatialQueryScratch()

    init(model: DXFPreviewModel) {
        self.model = model
        self.sceneBounds = model.bounds.isNull ? CGRect(x: 0, y: 0, width: 1, height: 1) : model.bounds

        let total = max(1, model.segments.count + model.polylines.count + model.circles.count + model.texts.count)
        let bucketSide = min(96, max(12, Int(sqrt(Double(total) / 24.0).rounded(.up))))
        self.columns = bucketSide
        self.rows = bucketSide
        self.cellWidth = max(self.sceneBounds.width / CGFloat(bucketSide), 0.0001)
        self.cellHeight = max(self.sceneBounds.height / CGFloat(bucketSide), 0.0001)

        self.segmentBounds = model.segments.map(Self.segmentBounds)
        self.polylineBounds = model.polylines.map(Self.polylineBounds)
        self.circleBounds = model.circles.map(Self.circleBounds)
        self.textBounds = model.texts.map(Self.textBounds)
        let layerMetadata = Self.buildLayerMetadata(
            model: model,
            segmentBounds: segmentBounds,
            polylineBounds: polylineBounds,
            circleBounds: circleBounds,
            textBounds: textBounds
        )
        self.layerStats = layerMetadata.stats
        self.layerBoundsByName = layerMetadata.bounds

        self.segmentBuckets = Self.buildBuckets(
            itemBounds: segmentBounds,
            sceneBounds: sceneBounds,
            columns: columns,
            rows: rows,
            cellWidth: cellWidth,
            cellHeight: cellHeight
        )
        self.polylineBuckets = Self.buildBuckets(
            itemBounds: polylineBounds,
            sceneBounds: sceneBounds,
            columns: columns,
            rows: rows,
            cellWidth: cellWidth,
            cellHeight: cellHeight
        )
        self.circleBuckets = Self.buildBuckets(
            itemBounds: circleBounds,
            sceneBounds: sceneBounds,
            columns: columns,
            rows: rows,
            cellWidth: cellWidth,
            cellHeight: cellHeight
        )
        self.textBuckets = Self.buildBuckets(
            itemBounds: textBounds,
            sceneBounds: sceneBounds,
            columns: columns,
            rows: rows,
            cellWidth: cellWidth,
            cellHeight: cellHeight
        )
    }

    func query(viewport: CGRect, visibleLayers: Set<String>) -> DXFVisibleGeometry {
        guard !visibleLayers.isEmpty else { return .empty }
        let rect = viewport.intersection(sceneBounds)
        guard !rect.isNull, rect.width >= 0, rect.height >= 0 else { return .empty }

        let cellRange = cellRangeIntersecting(rect)
        let segmentIndices = uniqueIndices(cellRange: cellRange, buckets: segmentBuckets, itemCount: model.segments.count)
        let polylineIndices = uniqueIndices(cellRange: cellRange, buckets: polylineBuckets, itemCount: model.polylines.count)
        let circleIndices = uniqueIndices(cellRange: cellRange, buckets: circleBuckets, itemCount: model.circles.count)
        let textIndices = uniqueIndices(cellRange: cellRange, buckets: textBuckets, itemCount: model.texts.count)

        return DXFVisibleGeometry(
            segments: collectSegments(indices: segmentIndices, visibleLayers: visibleLayers, viewport: rect),
            polylines: collectPolylines(indices: polylineIndices, visibleLayers: visibleLayers, viewport: rect),
            circles: collectCircles(indices: circleIndices, visibleLayers: visibleLayers, viewport: rect),
            texts: collectTexts(indices: textIndices, visibleLayers: visibleLayers, viewport: rect)
        )
    }

    func queryAll(visibleLayers: Set<String>) -> DXFVisibleGeometry {
        guard !visibleLayers.isEmpty else { return .empty }
        return DXFVisibleGeometry(
            segments: model.segments.filter { visibleLayers.contains($0.layer) },
            polylines: model.polylines.filter { visibleLayers.contains($0.layer) },
            circles: model.circles.filter { visibleLayers.contains($0.layer) },
            texts: model.texts.filter { visibleLayers.contains($0.layer) }
        )
    }

    func layerBounds(for layerName: String) -> CGRect? {
        layerBoundsByName[layerName]
    }

    private func collectSegments(indices: [Int], visibleLayers: Set<String>, viewport: CGRect) -> [DXFPreviewModel.Segment] {
        var result: [DXFPreviewModel.Segment] = []
        result.reserveCapacity(indices.count)
        for index in indices {
            guard visibleLayers.contains(model.segments[index].layer),
                  segmentBounds[index].intersects(viewport) else { continue }
            result.append(model.segments[index])
        }
        return result
    }

    private func collectPolylines(indices: [Int], visibleLayers: Set<String>, viewport: CGRect) -> [DXFPreviewModel.Polyline] {
        var result: [DXFPreviewModel.Polyline] = []
        result.reserveCapacity(indices.count)
        for index in indices {
            guard visibleLayers.contains(model.polylines[index].layer),
                  polylineBounds[index].intersects(viewport) else { continue }
            result.append(model.polylines[index])
        }
        return result
    }

    private func collectCircles(indices: [Int], visibleLayers: Set<String>, viewport: CGRect) -> [DXFPreviewModel.Circle] {
        var result: [DXFPreviewModel.Circle] = []
        result.reserveCapacity(indices.count)
        for index in indices {
            guard visibleLayers.contains(model.circles[index].layer),
                  circleBounds[index].intersects(viewport) else { continue }
            result.append(model.circles[index])
        }
        return result
    }

    private func collectTexts(indices: [Int], visibleLayers: Set<String>, viewport: CGRect) -> [DXFPreviewModel.TextEntity] {
        var result: [DXFPreviewModel.TextEntity] = []
        result.reserveCapacity(indices.count)
        for index in indices {
            guard visibleLayers.contains(model.texts[index].layer),
                  textBounds[index].intersects(viewport) else { continue }
            result.append(model.texts[index])
        }
        return result
    }

    private func cellRangeIntersecting(_ rect: CGRect) -> DXFSpatialCellRange {
        DXFSpatialCellRange(
            minColumn: clampedColumn(forX: rect.minX),
            maxColumn: clampedColumn(forX: rect.maxX),
            minRow: clampedRow(forY: rect.minY),
            maxRow: clampedRow(forY: rect.maxY)
        )
    }

    private func uniqueIndices(cellRange: DXFSpatialCellRange, buckets: [Int: [Int]], itemCount: Int) -> [Int] {
        queryScratch.uniqueIndices(cellRange: cellRange, columns: columns, buckets: buckets, itemCount: itemCount)
    }

    private func clampedColumn(forX x: CGFloat) -> Int {
        let normalized = Int(floor((x - sceneBounds.minX) / cellWidth))
        return min(max(normalized, 0), columns - 1)
    }

    private func clampedRow(forY y: CGFloat) -> Int {
        let normalized = Int(floor((y - sceneBounds.minY) / cellHeight))
        return min(max(normalized, 0), rows - 1)
    }

    private static func buildBuckets(
        itemBounds: [CGRect],
        sceneBounds: CGRect,
        columns: Int,
        rows: Int,
        cellWidth: CGFloat,
        cellHeight: CGFloat
    ) -> [Int: [Int]] {
        guard !itemBounds.isEmpty else { return [:] }
        var buckets: [Int: [Int]] = [:]
        buckets.reserveCapacity(columns * rows / 3)

        func clampedColumn(forX x: CGFloat) -> Int {
            let normalized = Int(floor((x - sceneBounds.minX) / cellWidth))
            return min(max(normalized, 0), columns - 1)
        }

        func clampedRow(forY y: CGFloat) -> Int {
            let normalized = Int(floor((y - sceneBounds.minY) / cellHeight))
            return min(max(normalized, 0), rows - 1)
        }

        for (index, bounds) in itemBounds.enumerated() {
            let minColumn = clampedColumn(forX: bounds.minX)
            let maxColumn = clampedColumn(forX: bounds.maxX)
            let minRow = clampedRow(forY: bounds.minY)
            let maxRow = clampedRow(forY: bounds.maxY)
            for row in minRow...maxRow {
                for column in minColumn...maxColumn {
                    let cell = row * columns + column
                    buckets[cell, default: []].append(index)
                }
            }
        }
        return buckets
    }

    private static func buildLayerMetadata(
        model: DXFPreviewModel,
        segmentBounds: [CGRect],
        polylineBounds: [CGRect],
        circleBounds: [CGRect],
        textBounds: [CGRect]
    ) -> (stats: [DXFLayerStat], bounds: [String: CGRect]) {
        var counter: [String: Int] = [:]
        var kindCounter: [String: [DXFPreviewModel.PrimitiveKind: Int]] = [:]
        var boundsByName: [String: CGRect] = [:]

        func append(layer: String, kind: DXFPreviewModel.PrimitiveKind, bounds: CGRect) {
            counter[layer, default: 0] += 1
            var kinds = kindCounter[layer] ?? [:]
            kinds[kind, default: 0] += 1
            kindCounter[layer] = kinds
            guard !bounds.isNull else { return }
            boundsByName[layer] = (boundsByName[layer] ?? .null).union(bounds)
        }

        for (index, item) in model.segments.enumerated() {
            append(layer: item.layer, kind: item.kind, bounds: segmentBounds[index])
        }
        for (index, item) in model.polylines.enumerated() {
            append(layer: item.layer, kind: item.kind, bounds: polylineBounds[index])
        }
        for (index, item) in model.circles.enumerated() {
            append(layer: item.layer, kind: item.kind, bounds: circleBounds[index])
        }
        for (index, item) in model.texts.enumerated() {
            append(layer: item.layer, kind: item.kind, bounds: textBounds[index])
        }

        let stats = counter
            .map { layer, count in
                DXFLayerStat(name: layer, count: count, kindCounts: kindCounter[layer] ?? [:])
            }
            .sorted {
                if $0.count == $1.count { return $0.name < $1.name }
                return $0.count > $1.count
            }
        return (stats, boundsByName)
    }

    private static func segmentBounds(_ segment: DXFPreviewModel.Segment) -> CGRect {
        normalizedRect(
            minX: min(segment.from.x, segment.to.x),
            maxX: max(segment.from.x, segment.to.x),
            minY: min(segment.from.y, segment.to.y),
            maxY: max(segment.from.y, segment.to.y)
        )
    }

    private static func polylineBounds(_ polyline: DXFPreviewModel.Polyline) -> CGRect {
        guard !polyline.points.isEmpty else { return .null }
        var minX = polyline.points[0].x
        var maxX = minX
        var minY = polyline.points[0].y
        var maxY = minY
        for point in polyline.points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return normalizedRect(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    private static func circleBounds(_ circle: DXFPreviewModel.Circle) -> CGRect {
        normalizedRect(
            minX: circle.center.x - circle.radius,
            maxX: circle.center.x + circle.radius,
            minY: circle.center.y - circle.radius,
            maxY: circle.center.y + circle.radius
        )
    }

    private static func textBounds(_ text: DXFPreviewModel.TextEntity) -> CGRect {
        let height = max(text.height, 0.8)
        let width = max(CGFloat(text.value.count) * height * 0.62, height * 0.85)
        return normalizedRect(
            minX: text.point.x,
            maxX: text.point.x + width,
            minY: text.point.y - height * 0.55,
            maxY: text.point.y + height * 0.55
        )
    }

    private static func normalizedRect(minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) -> CGRect {
        let epsilon: CGFloat = 0.0001
        let width = max(maxX - minX, epsilon)
        let height = max(maxY - minY, epsilon)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }
}

private struct DXFSpatialCellRange {
    let minColumn: Int
    let maxColumn: Int
    let minRow: Int
    let maxRow: Int

    var isEmpty: Bool {
        minColumn > maxColumn || minRow > maxRow
    }

    var estimatedCellCount: Int {
        guard !isEmpty else { return 0 }
        return (maxColumn - minColumn + 1) * (maxRow - minRow + 1)
    }
}

private final class DXFSpatialQueryScratch {
    private var marks: [UInt32] = []
    private var generation: UInt32 = 0

    func uniqueIndices(
        cellRange: DXFSpatialCellRange,
        columns: Int,
        buckets: [Int: [Int]],
        itemCount: Int
    ) -> [Int] {
        guard !cellRange.isEmpty, itemCount > 0 else { return [] }
        prepareMarks(for: itemCount)

        var result: [Int] = []
        result.reserveCapacity(min(itemCount, cellRange.estimatedCellCount * 8))
        for row in cellRange.minRow...cellRange.maxRow {
            for column in cellRange.minColumn...cellRange.maxColumn {
                let cell = row * columns + column
                guard let indices = buckets[cell] else { continue }
                for index in indices where marks[index] != generation {
                    marks[index] = generation
                    result.append(index)
                }
            }
        }
        return result
    }

    private func prepareMarks(for itemCount: Int) {
        if generation == UInt32.max {
            marks = Array(repeating: 0, count: max(marks.count, itemCount))
            generation = 1
        } else {
            generation += 1
            if marks.count < itemCount {
                marks.append(contentsOf: repeatElement(0, count: itemCount - marks.count))
            }
        }
    }
}
