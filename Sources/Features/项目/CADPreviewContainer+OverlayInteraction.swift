import SwiftUI
#if os(iOS)
import UIKit
#endif

extension CADPreviewContainer {
    private var selectedStrokeIndex: Int? {
        guard let selectedStrokeID else { return nil }
        return snapshot.strokes.firstIndex { $0.id == selectedStrokeID }
    }

    var selectedStroke: CADStroke? {
        guard let selectedStrokeIndex else { return nil }
        return snapshot.strokes[selectedStrokeIndex]
    }

    var hasNativeDrawingCoordinateSpace: Bool {
        snapshot.coordinateSpace == .drawing && nativeCanvasTransform != nil
    }

    var canCaptureDrawingOverlay: Bool {
        allowsOverlayEditing && hasNativeDrawingCoordinateSpace
    }

    var overlayHitTestingEnabled: Bool {
        guard allowsOverlayEditing else { return false }
        if tool.requiresDrawingCoordinateCapture {
            return canCaptureDrawingOverlay
        }
        return isSelectingStroke && canCaptureDrawingOverlay
    }

    private func isOverlayToolEnabled(_ candidate: CADOverlayTool) -> Bool {
        !candidate.requiresDrawingCoordinateCapture || canCaptureDrawingOverlay
    }

    func ensureDrawingCoordinateCaptureAvailable(showAlertIfMissing: Bool = true) -> Bool {
        guard hasNativeDrawingCoordinateSpace else {
            if showAlertIfMissing {
                alertMessage = String(localized: "当前图纸坐标尚未就绪，已阻止写入批注、测量和数数数据。请等待图纸加载完成后重试。")
                showAlert = true
            }
            return false
        }
        return true
    }

    func clearInProgress() {
        activeStrokePoints.removeAll()
        pendingLengthPoints.removeAll()
        pendingAreaPoints.removeAll()
        activeDragLengthPoints.removeAll()
        activeDragArrowPoints.removeAll()
        pendingIssueMarkerPoint = nil
        isDeletingOverlayItem = false
    }

    func selectOverlayTool(_ nextTool: CADOverlayTool) {
        guard isOverlayToolEnabled(nextTool) else {
            clearInProgress()
            tool = .browse
            _ = ensureDrawingCoordinateCaptureAvailable()
            return
        }
        if tool != nextTool {
            clearInProgress()
            AppHaptics.impact(.light, intensity: 0.55)
        }
        tool = nextTool
        selectedStrokeID = nil
        isSelectingStroke = false
        switch nextTool {
        case .annotation, .cloud:
            revealOverlayContent(for: .annotation)
            if selectedStrokeLayer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedStrokeLayer = String(localized: "现场批注")
            }
        case .length, .continuousLength, .area:
            revealOverlayContent(for: .measurement)
        case .arrow:
            revealOverlayContent(for: .annotation)
        case .note:
            revealOverlayContent(for: .notes)
        case .issueMarker:
            revealOverlayContent(for: .issues)
        case .count:
            revealOverlayContent(for: .counts)
        case .browse:
            break
        }
    }

    func updateSelectedStrokeLayer(_ layer: String) {
        guard let index = selectedStrokeIndex else { return }
        guard snapshot.strokes[index].layerName != layer else { return }
        recordUndoSnapshot()
        snapshot.strokes[index].layerName = layer
        hiddenStrokeLayers.remove(layer)
    }

    func updateSelectedStrokeColor(_ hex: String) {
        guard let index = selectedStrokeIndex else { return }
        guard snapshot.strokes[index].colorHex != hex else { return }
        recordUndoSnapshot()
        snapshot.strokes[index].colorHex = hex
    }

    func deleteSelectedStroke() {
        guard let index = selectedStrokeIndex else { return }
        recordUndoSnapshot()
        snapshot.strokes.remove(at: index)
        selectedStrokeID = nil
    }

    var canUndoOverlayChange: Bool {
        !overlayUndoStack.isEmpty
    }

    var canRedoOverlayChange: Bool {
        !overlayRedoStack.isEmpty
    }

    private var hasVisibleDeletableOverlayContent: Bool {
        !visibleStrokes.isEmpty ||
        !visibleArrows.isEmpty ||
        !visibleLengthMeasurements.isEmpty ||
        !visibleAreaMeasurements.isEmpty ||
        !visibleNotes.isEmpty ||
        !visibleIssueMarkers.isEmpty ||
        (isOverlayGroupVisible(.counts) && !snapshot.countMarkers.isEmpty)
    }

    var canDeleteCurrentOverlayItem: Bool {
        selectedStrokeIndex != nil || hasVisibleDeletableOverlayContent
    }

    func deleteCurrentOverlayItem() {
        guard canDeleteCurrentOverlayItem || isDeletingOverlayItem else { return }
        let shouldEnterDeleteMode = !isDeletingOverlayItem
        clearInProgress()
        tool = .browse
        selectedStrokeID = nil
        quantityHighlightTarget = nil
        isSelectingStroke = false
        isDeletingOverlayItem = shouldEnterDeleteMode
        AppHaptics.impact(.light, intensity: shouldEnterDeleteMode ? 0.65 : 0.45)
    }

    func deleteOverlayItem(atCanvasPoint point: CGPoint) {
        guard let target = nearestOverlayDeleteTarget(toCanvasPoint: point) else {
            AppHaptics.warning()
            return
        }
        guard deleteOverlayTarget(target) else {
            AppHaptics.warning()
            return
        }
        selectedStrokeID = nil
        quantityHighlightTarget = nil
        isDeletingOverlayItem = false
        AppHaptics.success()
    }

    private func deleteOverlayTarget(_ target: CADOverlayDeleteTarget) -> Bool {
        switch target {
        case .stroke(let id):
            guard let index = snapshot.strokes.firstIndex(where: { $0.id == id }) else { return false }
            recordUndoSnapshot()
            snapshot.strokes.remove(at: index)
        case .length(let id):
            guard let index = snapshot.lengthMeasurements.firstIndex(where: { $0.id == id }) else { return false }
            recordUndoSnapshot()
            snapshot.lengthMeasurements.remove(at: index)
        case .area(let id):
            guard let index = snapshot.areaMeasurements.firstIndex(where: { $0.id == id }) else { return false }
            recordUndoSnapshot()
            snapshot.areaMeasurements.remove(at: index)
        case .arrow(let id):
            guard let index = snapshot.arrowAnnotations.firstIndex(where: { $0.id == id }) else { return false }
            recordUndoSnapshot()
            snapshot.arrowAnnotations.remove(at: index)
        case .note(let id):
            guard let index = snapshot.notes.firstIndex(where: { $0.id == id }) else { return false }
            recordUndoSnapshot()
            snapshot.notes.remove(at: index)
        case .issue(let id):
            guard let index = snapshot.issueMarkers.firstIndex(where: { $0.id == id }) else { return false }
            recordUndoSnapshot()
            snapshot.issueMarkers.remove(at: index)
        case .count(let id):
            guard let index = snapshot.countMarkers.firstIndex(where: { $0.id == id }) else { return false }
            recordUndoSnapshot()
            snapshot.countMarkers.remove(at: index)
        }
        return true
    }

    private var overlaySnapCandidates: [CGPoint] {
        var points: [CGPoint] = []
        if hasNativeDrawingCoordinateSpace {
            let buckets = nativeSnapPointBuckets.isEmpty ? fallbackNativeSnapPointBuckets() : nativeSnapPointBuckets
            points.append(contentsOf: buckets.points(
                enabledModes: enabledSnapModes,
                measurementOnly: tool.usesMeasurementSnapPrimitives
            ))
        }
        if isOverlayGroupVisible(.counts) {
            points.append(contentsOf: snapshot.countMarkers.map { $0.point.cgPoint })
        }
        for arrow in visibleArrows {
            points.append(arrow.start.cgPoint)
            points.append(arrow.end.cgPoint)
        }
        points.append(contentsOf: visibleNotes.map { $0.point.cgPoint })
        points.append(contentsOf: visibleIssueMarkers.map { $0.point.cgPoint })
        for measurement in visibleLengthMeasurements {
            points.append(contentsOf: measurement.points.map(\.cgPoint))
        }
        for measurement in visibleAreaMeasurements {
            points.append(contentsOf: measurement.points.map(\.cgPoint))
        }
        points.append(contentsOf: pendingLengthPoints)
        points.append(contentsOf: pendingAreaPoints)
        points.append(contentsOf: activeDragLengthPoints)
        points.append(contentsOf: activeDragArrowPoints)
        return points
    }

    func snappedOverlayPoint(_ rawPoint: CGPoint) -> CGPoint? {
        guard let storedRawPoint = storedDrawingPoint(fromCanvas: rawPoint) else {
            return nil
        }
        guard tool == .length || tool == .continuousLength || tool == .area || tool == .note || tool == .count else {
            return storedRawPoint
        }
        guard let nearest = nearestPoint(toCanvasPoint: rawPoint, inStoredPoints: overlaySnapCandidates, maxDistance: overlaySnapTolerance) else {
            return storedRawPoint
        }
        return nearest
    }

    func nearestCountMarkerIndex(toCanvasPoint point: CGPoint) -> Int? {
        guard isOverlayGroupVisible(.counts) else { return nil }
        var bestIndex: Int?
        var bestDistance = overlaySnapTolerance
        for (index, marker) in snapshot.countMarkers.enumerated() {
            let target = canvasPoint(fromStored: marker.point.cgPoint)
            let distance = hypot(target.x - point.x, target.y - point.y)
            if distance <= bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    func nearestStrokeID(toCanvasPoint point: CGPoint) -> UUID? {
        var bestID: UUID?
        var bestDistance = overlaySnapTolerance
        for stroke in visibleStrokes {
            let renderedPoints = canvasPoints(fromStored: stroke.points.map(\.cgPoint))
            let distance = distanceFrom(point, toPolyline: renderedPoints)
            if distance <= bestDistance {
                bestDistance = distance
                bestID = stroke.id
            }
        }
        return bestID
    }

    func nearestNoteIndex(toCanvasPoint point: CGPoint) -> Int? {
        var bestIndex: Int?
        var bestDistance = overlaySnapTolerance
        for (index, note) in snapshot.notes.enumerated() {
            guard isOverlayGroupVisible(.notes),
                  isOverlayColorVisible(noteColorHex(note)) else { continue }
            let target = canvasPoint(fromStored: note.point.cgPoint)
            let distance = hypot(target.x - point.x, target.y - point.y)
            if distance <= bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func nearestOverlayDeleteTarget(toCanvasPoint point: CGPoint) -> CADOverlayDeleteTarget? {
        var bestTarget: CADOverlayDeleteTarget?
        var bestDistance = max(overlaySnapTolerance, 24)

        func consider(_ target: CADOverlayDeleteTarget, distance: CGFloat) {
            guard distance <= bestDistance else { return }
            bestDistance = distance
            bestTarget = target
        }

        for stroke in visibleStrokes {
            let renderedPoints = canvasPoints(fromStored: stroke.points.map(\.cgPoint))
            consider(.stroke(stroke.id), distance: distanceFrom(point, toPolyline: renderedPoints))
        }

        for arrow in visibleArrows {
            let renderedPoints = canvasPoints(fromStored: [arrow.start.cgPoint, arrow.end.cgPoint])
            consider(.arrow(arrow.id), distance: distanceFrom(point, toPolyline: renderedPoints))
        }

        for measurement in visibleLengthMeasurements {
            let renderedPoints = canvasPoints(fromStored: measurement.points.map(\.cgPoint))
            consider(.length(measurement.id), distance: distanceFrom(point, toPolyline: renderedPoints))
        }

        for area in visibleAreaMeasurements {
            let renderedPoints = canvasPoints(fromStored: area.points.map(\.cgPoint))
            guard renderedPoints.count >= 3 else { continue }
            let distance = isPoint(point, insidePolygon: renderedPoints)
                ? 0
                : distanceFrom(point, toPolyline: closedPolylinePoints(renderedPoints))
            consider(.area(area.id), distance: distance)
        }

        for note in visibleNotes {
            let target = canvasPoint(fromStored: note.point.cgPoint)
            let distance = hypot(target.x - point.x, target.y - point.y)
            consider(.note(note.id), distance: distance)
        }

        for marker in visibleIssueMarkers {
            let target = canvasPoint(fromStored: marker.point.cgPoint)
            let distance = hypot(target.x - point.x, target.y - point.y)
            consider(.issue(marker.id), distance: distance)
        }

        if isOverlayGroupVisible(.counts) {
            for marker in snapshot.countMarkers {
                let target = canvasPoint(fromStored: marker.point.cgPoint)
                let distance = hypot(target.x - point.x, target.y - point.y)
                consider(.count(marker.id), distance: distance)
            }
        }

        return bestTarget
    }

    private func nearestPoint(toCanvasPoint source: CGPoint, inStoredPoints points: [CGPoint], maxDistance: CGFloat) -> CGPoint? {
        var nearest: CGPoint?
        var nearestDistance = maxDistance
        for point in points {
            let canvasPoint = canvasPoint(fromStored: point)
            let distance = hypot(canvasPoint.x - source.x, canvasPoint.y - source.y)
            if distance <= nearestDistance {
                nearestDistance = distance
                nearest = point
            }
        }
        return nearest
    }

    func distanceFrom(_ point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        guard !points.isEmpty else { return .greatestFiniteMagnitude }
        guard points.count > 1 else {
            return hypot(points[0].x - point.x, points[0].y - point.y)
        }
        var best = CGFloat.greatestFiniteMagnitude
        for index in 0..<(points.count - 1) {
            best = min(best, distanceFrom(point, toSegmentStart: points[index], end: points[index + 1]))
        }
        return best
    }

    func closedPolylinePoints(_ points: [CGPoint]) -> [CGPoint] {
        guard let first = points.first, let last = points.last else { return points }
        guard hypot(first.x - last.x, first.y - last.y) > 0.5 else { return points }
        var result = points
        result.append(first)
        return result
    }

    func isPoint(_ point: CGPoint, insidePolygon polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var isInside = false
        var previousIndex = polygon.count - 1
        for index in polygon.indices {
            let current = polygon[index]
            let previous = polygon[previousIndex]
            let crossesY = (current.y > point.y) != (previous.y > point.y)
            if crossesY {
                let projectedX = (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x
                if point.x < projectedX {
                    isInside.toggle()
                }
            }
            previousIndex = index
        }
        return isInside
    }

    func distanceFrom(_ point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let rawT = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let t = min(max(rawT, 0), 1)
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }
}
