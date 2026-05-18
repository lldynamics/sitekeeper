import SwiftUI

extension CADPreviewContainer {
    var quantitySheet: some View {
        CADQuantitySheetView(context: quantitySheetContext)
    }

    private var quantityTotal: Double {
        snapshot.quantityItems.reduce(0) { result, item in
            let quantity = ReportBuilder.number(item.quantity)
            let unitPrice = ReportBuilder.number(item.unitPrice)
            let waste = ReportBuilder.number(item.wasteRate) / 100
            return result + quantity * max(0, 1 + waste) * unitPrice
        }
    }

    var countCategoryOptions: [String] {
        [
            String(localized: "点位"),
            String(localized: "灯位"),
            String(localized: "插座"),
            String(localized: "开关"),
            String(localized: "桥架点"),
            String(localized: "管卡")
        ]
    }

    private var countCategoryStats: [(category: String, count: Int)] {
        var grouped: [String: Int] = [:]
        for marker in snapshot.countMarkers {
            grouped[marker.category, default: 0] += 1
        }
        return grouped
            .map { ($0.key, $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.category.localizedStandardCompare($1.category) == .orderedAscending
                }
                return $0.count > $1.count
            }
    }

    var selectedCategoryCount: Int {
        snapshot.countMarkers.reduce(0) { result, marker in
            result + (marker.category == selectedCountCategory ? 1 : 0)
        }
    }

    var highlightedLengthMeasurementID: UUID? {
        guard case let .length(id)? = quantityHighlightTarget else { return nil }
        return id
    }

    var highlightedAreaMeasurementID: UUID? {
        guard case let .area(id)? = quantityHighlightTarget else { return nil }
        return id
    }

    var highlightedCountCategory: String? {
        guard case let .countCategory(category)? = quantityHighlightTarget else { return nil }
        return category
    }

    var highlightedCountMarkerIDs: Set<UUID> {
        guard case let .countMarkers(ids)? = quantityHighlightTarget else { return [] }
        return Set(ids)
    }

    var quantityHighlightCanvasRect: CGRect? {
        guard let quantityHighlightTarget,
              let storedBounds = bounds(forStoredPoints: storedPoints(for: quantityHighlightTarget)) else {
            return nil
        }
        let minPoint = canvasPoint(fromStored: CGPoint(x: storedBounds.minX, y: storedBounds.minY))
        let maxPoint = canvasPoint(fromStored: CGPoint(x: storedBounds.maxX, y: storedBounds.maxY))
        let rect = CGRect(
            x: min(minPoint.x, maxPoint.x),
            y: min(minPoint.y, maxPoint.y),
            width: max(abs(maxPoint.x - minPoint.x), 34),
            height: max(abs(maxPoint.y - minPoint.y), 34)
        )
        return rect.insetBy(dx: -10, dy: -10)
    }

    private func appendQuantityFromLength(_ measurement: CADLengthMeasurement) {
        let length = lengthInMeters(for: measurement.points.map(\.cgPoint))
        recordUndoSnapshot()
        snapshot.quantityItems.append(
            CADQuantityItem(
                name: measurement.name,
                unit: "m",
                quantity: Formatters.number(length, minFraction: 2, maxFraction: 3),
                unitPrice: "0",
                wasteRate: "0",
                source: String(localized: "测量-线长"),
                sourceLinkKind: .lengthMeasurement,
                sourceLinkID: measurement.id
            )
        )
    }

    private func appendQuantityFromArea(_ measurement: CADAreaMeasurement) {
        let area = areaInSquareMeters(for: measurement.points.map(\.cgPoint))
        recordUndoSnapshot()
        snapshot.quantityItems.append(
            CADQuantityItem(
                name: measurement.name,
                unit: "m²",
                quantity: Formatters.number(area, minFraction: 2, maxFraction: 3),
                unitPrice: "0",
                wasteRate: "0",
                source: String(localized: "测量-面积"),
                sourceLinkKind: .areaMeasurement,
                sourceLinkID: measurement.id
            )
        )
    }

    func appendQuantityFromCountCategory(_ category: String) {
        let sourceMarkers = snapshot.countMarkers.filter { $0.category == category }
        let sourceIDs = sourceMarkers.map(\.id)
        let count = sourceIDs.count
        guard count > 0 else { return }
        recordUndoSnapshot()
        snapshot.quantityItems.append(
            CADQuantityItem(
                name: category,
                unit: String(localized: "个"),
                quantity: "\(count)",
                unitPrice: "0",
                wasteRate: "0",
                source: String(
                    format: String(localized: "数数-%@"),
                    category
                ),
                sourceLinkKind: .countMarkers,
                sourceLinkCategory: category,
                sourceLinkMarkerIDs: sourceIDs
            )
        )
    }

    private func appendManualQuantityItem() {
        recordUndoSnapshot()
        snapshot.quantityItems.append(
            CADQuantityItem(
                name: String(localized: "新条目"),
                unit: String(localized: "项"),
                quantity: "1",
                unitPrice: "0",
                wasteRate: "0",
                source: String(localized: "手动"),
                sourceLinkKind: .manual
            )
        )
    }

    func quantityHighlightTarget(for item: CADQuantityItem) -> CADQuantityHighlightTarget? {
        switch item.sourceLinkKind {
        case .manual:
            if item.source.contains(String(localized: "测量-线长")),
               let measurement = snapshot.lengthMeasurements.last(where: { $0.name == item.name }) {
                return .length(measurement.id)
            }
            if item.source.contains(String(localized: "测量-面积")),
               let measurement = snapshot.areaMeasurements.last(where: { $0.name == item.name }) {
                return .area(measurement.id)
            }
            if let range = item.source.range(of: String(localized: "数数-")) {
                let category = String(item.source[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !category.isEmpty else { return nil }
                let ids = snapshot.countMarkers
                    .filter { $0.category == category }
                    .map(\.id)
                guard !ids.isEmpty else { return nil }
                return .countMarkers(ids)
            }
            return nil
        case .lengthMeasurement:
            guard let id = item.sourceLinkID,
                  snapshot.lengthMeasurements.contains(where: { $0.id == id }) else { return nil }
            return .length(id)
        case .areaMeasurement:
            guard let id = item.sourceLinkID,
                  snapshot.areaMeasurements.contains(where: { $0.id == id }) else { return nil }
            return .area(id)
        case .countCategory:
            let category = (item.sourceLinkCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !category.isEmpty else { return nil }
            let ids = snapshot.countMarkers
                .filter { $0.category == category }
                .map(\.id)
            guard !ids.isEmpty else { return nil }
            return .countMarkers(ids)
        case .countMarkers:
            let ids = (item.sourceLinkMarkerIDs ?? [])
                .filter { markerID in
                    snapshot.countMarkers.contains(where: { $0.id == markerID })
                }
            if !ids.isEmpty {
                return .countMarkers(ids)
            }
            let category = (item.sourceLinkCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !category.isEmpty,
                  snapshot.countMarkers.contains(where: { $0.category == category }) else { return nil }
            return .countCategory(category)
        }
    }

    private func locateQuantitySource(_ item: CADQuantityItem) {
        guard let target = quantityHighlightTarget(for: item) else {
            alertMessage = String(localized: "该算量条目来源已不存在，无法定位。")
            showAlert = true
            return
        }
        quantityHighlightTarget = target
        tool = .browse
        clearInProgress()
        showQuantitySheet = false
        focusQuantityTarget(target)
    }

    private func focusQuantityTarget(_ target: CADQuantityHighlightTarget) {
        let points = storedPoints(for: target)
        guard let center = centerPoint(of: points) else { return }
        var userInfo: [String: Any] = [
            "filePath": activeRequest.fileURL.path,
            "point": NSValue(cgPoint: center),
        ]
        if let bounds = bounds(forStoredPoints: points) {
            userInfo["bounds"] = NSValue(cgRect: bounds)
        }
        NotificationCenter.default.post(
            name: .cadFocusSourcePoint,
            object: nil,
            userInfo: userInfo
        )
    }

    private func bounds(forStoredPoints points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let width = max(maxX - minX, 0.001)
        let height = max(maxY - minY, 0.001)
        let pad = max(max(width, height) * 0.18, 0.002)
        return CGRect(x: minX - pad, y: minY - pad, width: width + pad * 2, height: height + pad * 2)
    }

    func storedPoints(for target: CADQuantityHighlightTarget) -> [CGPoint] {
        switch target {
        case .length(let id):
            return snapshot.lengthMeasurements
                .first(where: { $0.id == id })?
                .points
                .map(\.cgPoint) ?? []
        case .area(let id):
            return snapshot.areaMeasurements
                .first(where: { $0.id == id })?
                .points
                .map(\.cgPoint) ?? []
        case .countCategory(let category):
            return snapshot.countMarkers
                .filter { $0.category == category }
                .map { $0.point.cgPoint }
        case .countMarkers(let markerIDs):
            let sourceIDSet = Set(markerIDs)
            return snapshot.countMarkers
                .filter { sourceIDSet.contains($0.id) }
                .map { $0.point.cgPoint }
        }
    }

    private func quantitySubtotal(_ item: CADQuantityItem) -> Double {
        let quantity = ReportBuilder.number(item.quantity)
        let unitPrice = ReportBuilder.number(item.unitPrice)
        let waste = ReportBuilder.number(item.wasteRate) / 100
        return quantity * max(0, 1 + waste) * unitPrice
    }

    private var quantitySheetContext: CADQuantitySheetContext {
        CADQuantitySheetContext(
            lengthMeasurements: snapshot.lengthMeasurements,
            areaMeasurements: snapshot.areaMeasurements,
            countCategoryStats: countCategoryStats,
            quantityItems: $snapshot.quantityItems,
            lengthSummary: { measurement in
                lengthLabel(for: measurement.points.map(\.cgPoint))
            },
            areaSummary: { measurement in
                areaLabel(for: measurement.points.map(\.cgPoint))
            },
            appendLengthMeasurement: { measurement in
                appendQuantityFromLength(measurement)
            },
            appendAreaMeasurement: { measurement in
                appendQuantityFromArea(measurement)
            },
            appendCountCategory: { category in
                appendQuantityFromCountCategory(category)
            },
            canLocateItem: { item in
                quantityHighlightTarget(for: item) != nil
            },
            locateItem: { item in
                locateQuantitySource(item)
            },
            quantitySubtotal: { item in
                quantitySubtotal(item)
            },
            deleteItem: { item in
                recordUndoSnapshot()
                snapshot.quantityItems.removeAll { $0.id == item.id }
            },
            quantityTotal: quantityTotal,
            addManualItem: {
                appendManualQuantityItem()
            },
            close: {
                showQuantitySheet = false
            }
        )
    }
}
