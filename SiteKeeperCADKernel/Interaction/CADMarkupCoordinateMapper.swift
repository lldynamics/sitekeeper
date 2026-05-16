import Foundation

extension SiteKeeperCADKernel {
    struct CADScreenSize: Equatable, Codable, Hashable {
        var width: Double
        var height: Double

        init(width: Double, height: Double) {
            self.width = max(width, 1)
            self.height = max(height, 1)
        }
    }

    struct CADIssueMarkerAnchor: Identifiable, Equatable, Codable {
        var id: UUID
        var drawingId: UUID
        var layoutId: String
        var worldPoint: CADPoint
        var title: String
        var note: String
        var externalIssueId: UUID?

        init(
            id: UUID = UUID(),
            drawingId: UUID,
            layoutId: String,
            worldPoint: CADPoint,
            title: String = "",
            note: String = "",
            externalIssueId: UUID? = nil
        ) {
            self.id = id
            self.drawingId = drawingId
            self.layoutId = layoutId
            self.worldPoint = worldPoint
            self.title = title
            self.note = note
            self.externalIssueId = externalIssueId
        }
    }

    struct CADMarkupCoordinateMapper: Equatable, Codable {
        var drawingToScreen: CADTransform
        var screenToDrawing: CADTransform
        var drawingId: UUID?
        var layoutId: String
        var screenSize: CADScreenSize?

        init(
            drawingToScreen: CADTransform = .identity,
            screenToDrawing: CADTransform = .identity,
            drawingId: UUID? = nil,
            layoutId: String = CADLayout.modelSpace.id,
            screenSize: CADScreenSize? = nil
        ) {
            self.drawingToScreen = drawingToScreen
            self.screenToDrawing = screenToDrawing
            self.drawingId = drawingId
            self.layoutId = layoutId
            self.screenSize = screenSize
        }

        init(
            viewport: CADViewport,
            screenSize: CADScreenSize,
            drawingId: UUID? = nil
        ) {
            let drawingToScreen = Self.makeDrawingToScreenTransform(viewport: viewport, screenSize: screenSize)
            self.init(
                drawingToScreen: drawingToScreen,
                screenToDrawing: drawingToScreen.inverted() ?? .identity,
                drawingId: drawingId,
                layoutId: viewport.layoutID,
                screenSize: screenSize
            )
        }

        func screenPoint(forDrawingPoint point: CADPoint) -> CADPoint {
            drawingToScreen.apply(to: point)
        }

        func drawingPoint(forScreenPoint point: CADPoint) -> CADPoint {
            screenToDrawing.apply(to: point)
        }

        func screenPoint(forWorldPoint point: CADPoint) -> CADPoint {
            screenPoint(forDrawingPoint: point)
        }

        func worldPoint(forScreenPoint point: CADPoint) -> CADPoint {
            drawingPoint(forScreenPoint: point)
        }

        func makeIssueMarker(
            drawingId explicitDrawingId: UUID,
            layoutId explicitLayoutId: String? = nil,
            screenPoint: CADPoint,
            title: String = "",
            note: String = "",
            externalIssueId: UUID? = nil
        ) -> CADIssueMarkerAnchor {
            CADIssueMarkerAnchor(
                drawingId: explicitDrawingId,
                layoutId: explicitLayoutId ?? layoutId,
                worldPoint: worldPoint(forScreenPoint: screenPoint),
                title: title,
                note: note,
                externalIssueId: externalIssueId
            )
        }

        func screenPoint(for marker: CADIssueMarkerAnchor) -> CADPoint? {
            guard marker.layoutId == layoutId else { return nil }
            if let drawingId, drawingId != marker.drawingId { return nil }
            return screenPoint(forWorldPoint: marker.worldPoint)
        }

        func viewportTarget(
            for worldPoint: CADPoint,
            id: String = "markup-target",
            viewHeight: Double
        ) -> CADViewport {
            CADViewport(
                id: id,
                layoutID: layoutId,
                viewCenter: worldPoint,
                viewHeight: max(viewHeight, 0.0001)
            )
        }

        private static func makeDrawingToScreenTransform(
            viewport: CADViewport,
            screenSize: CADScreenSize
        ) -> CADTransform {
            let safeViewHeight = max(viewport.viewHeight, 0.0001)
            let pixelsPerWorldUnit = screenSize.height / safeViewHeight
            let cosValue = cos(viewport.twistRadians)
            let sinValue = sin(viewport.twistRadians)
            let center = viewport.viewCenter
            let tx = screenSize.width / 2
                - pixelsPerWorldUnit * cosValue * center.x
                - pixelsPerWorldUnit * sinValue * center.y
            let ty = screenSize.height / 2
                - pixelsPerWorldUnit * sinValue * center.x
                + pixelsPerWorldUnit * cosValue * center.y

            return CADTransform(
                matrix: CADMatrix(
                    a: pixelsPerWorldUnit * cosValue,
                    b: pixelsPerWorldUnit * sinValue,
                    c: pixelsPerWorldUnit * sinValue,
                    d: -pixelsPerWorldUnit * cosValue,
                    tx: tx,
                    ty: ty
                )
            )
        }
    }
}
