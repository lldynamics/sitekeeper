import SwiftUI
#if os(iOS)
import UIKit
#endif

extension CADPreviewContainer {
    func canvasPoint(fromStored point: CGPoint) -> CGPoint {
        guard snapshot.coordinateSpace == .drawing,
              let nativeCanvasTransform else { return point }
        return nativeCanvasTransform.canvasPoint(fromDrawing: point)
    }

    func storedDrawingPoint(fromCanvas point: CGPoint) -> CGPoint? {
        guard snapshot.coordinateSpace == .drawing,
              let nativeCanvasTransform else { return nil }
        return nativeCanvasTransform.drawingPoint(fromCanvas: point)
    }

    func appendActiveStrokePoint(fromCanvas canvasPoint: CGPoint, force: Bool = false) {
        guard let point = storedDrawingPoint(fromCanvas: canvasPoint) else { return }
        appendActiveStrokePoint(point, force: force)
    }

    func appendActiveStrokePoint(_ point: CGPoint, force: Bool = false) {
        guard let last = activeStrokePoints.last else {
            activeStrokePoints.append(point)
            return
        }

        let distance = hypot(point.x - last.x, point.y - last.y)
        let minimumDistance = activeStrokeMinimumDrawingDistance()
        if force {
            guard distance > max(minimumDistance * 0.15, 0.000001) else { return }
            appendOrReplaceActiveStrokePoint(point)
            return
        }

        guard distance >= minimumDistance else { return }
        appendOrReplaceActiveStrokePoint(point)
    }

    private func appendOrReplaceActiveStrokePoint(_ point: CGPoint) {
        guard activeStrokePoints.count < activeStrokePointLimit else {
            activeStrokePoints[activeStrokePoints.count - 1] = point
            return
        }
        activeStrokePoints.append(point)
    }

    private func activeStrokeMinimumDrawingDistance() -> CGFloat {
        guard let nativeCanvasTransform else { return 0.5 }
        let baseCanvasPoint = CGPoint(
            x: nativeCanvasTransform.size.width * 0.5,
            y: nativeCanvasTransform.size.height * 0.5
        )
        let rightCanvasPoint = CGPoint(
            x: baseCanvasPoint.x + activeStrokeSamplingCanvasDistance,
            y: baseCanvasPoint.y
        )
        let p0 = nativeCanvasTransform.drawingPoint(fromCanvas: baseCanvasPoint)
        let p1 = nativeCanvasTransform.drawingPoint(fromCanvas: rightCanvasPoint)
        return max(hypot(p1.x - p0.x, p1.y - p0.y), 0.0001)
    }

    func canvasPoints(fromStored points: [CGPoint]) -> [CGPoint] {
        points.map(canvasPoint(fromStored:))
    }

    @MainActor
    func appendIssueMarker(photo image: UIImage?) {
        guard ensureDrawingCoordinateCaptureAvailable(showAlertIfMissing: false),
              let point = pendingIssueMarkerPoint else {
            pendingIssueMarkerPoint = nil
            showIssuePhotoCamera = false
            return
        }

        let photoFileName = image
            .flatMap { $0.jpegData(compressionQuality: 0.82) }
            .flatMap { PhotoStorage.save(original: $0, fileName: "cad-issue-\(UUID().uuidString).jpg") }
        recordUndoSnapshot()
        let marker = CADFallbackIssueMarker(
            point: CADPoint(point),
            normalizedPoint: CADPoint(normalizedFallbackPoint(fromStored: point)),
            drawingId: activeRequest.drawingID,
            layoutId: SiteKeeperCADKernel.CADLayout.modelSpace.id,
            worldPoint: CADPoint(point),
            viewportTransform: currentFallbackViewportTransform(),
            title: String(
                format: String(localized: "问题点 %lld"),
                Int64(snapshot.issueMarkers.count + 1)
            ),
            note: "",
            photoFileName: photoFileName,
            layerName: nearestDrawingLayerName(toStoredPoint: point),
            measurementSummary: nearestMeasurementSummary(toStoredPoint: point),
            colorHex: "E24A7A",
            createdAt: Formatters.now()
        )
        hiddenOverlayGroups.remove(.issues)
        hiddenOverlayColorHexes.remove(issueMarkerColorHex(marker))
        snapshot.issueMarkers.append(marker)
        pendingIssueMarkerPoint = nil
        showIssuePhotoCamera = false
        AppHaptics.success()
    }

    private func normalizedFallbackPoint(fromStored point: CGPoint) -> CGPoint {
        guard shouldUseFallbackViewer,
              let bounds = nativeCanvasTransform?.bounds,
              bounds.width > 0,
              bounds.height > 0 else {
            return point
        }
        return CGPoint(
            x: min(max((point.x - bounds.minX) / bounds.width, 0), 1),
            y: min(max((point.y - bounds.minY) / bounds.height, 0), 1)
        )
    }

    private func currentFallbackViewportTransform() -> CADFallbackViewportTransform? {
        guard shouldUseFallbackViewer,
              let nativeCanvasTransform else { return nil }
        return CADFallbackViewportTransform(
            transform: nativeCanvasTransform,
            viewState: currentCADViewState
        )
    }
}
