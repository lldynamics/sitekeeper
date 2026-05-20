import Foundation

extension SiteKeeperCADKernel {
    struct CADSplineTessellator {
        var curveSegmentCount: Int = 12

        func tessellate(controlPoints: [CADPoint]) -> CADPath {
            guard let first = controlPoints.first else { return CADPath() }
            var elements: [CADPath.Element] = [.move(to: first)]
            controlPoints.dropFirst().forEach { elements.append(.line(to: $0)) }
            return CADPath(elements: elements)
        }

        func resolve(_ entity: CADEntity) -> [CADEntity] {
            guard entity.kind == .spline else { return [entity] }
            guard let path = entity.path else {
                var copy = entity
                copy.unsupportedReason = "Spline has no control path."
                copy.diagnostics = copy.diagnostics.appending(
                    CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_SPLINE_PATH_MISSING",
                        message: "Spline has no control path; original object preserved.",
                        detail: entity.sourceHandle
                    )
                )
                return [copy]
            }

            let flattened = flatten(path: path)
            var copy = entity
            copy.id = UUID()
            copy.kind = .polyline
            copy.path = flattened
            copy.bounds = flattened.bounds
            copy.diagnostics = copy.diagnostics.appending(
                CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: "CAD_SPLINE_TESSELLATED",
                    message: "Spline approximated as polyline.",
                    detail: entity.sourceHandle
                )
            )
            return [copy]
        }

        func flatten(path: CADPath) -> CADPath {
            var flattened: [CADPath.Element] = []
            var currentPoint: CADPoint?

            for element in path.elements {
                switch element {
                case let .move(point):
                    flattened.append(.move(to: point))
                    currentPoint = point
                case let .line(point):
                    flattened.append(.line(to: point))
                    currentPoint = point
                case let .curve(point, control1, control2):
                    guard let start = currentPoint else {
                        flattened.append(.move(to: point))
                        currentPoint = point
                        continue
                    }
                    for segment in 1...max(curveSegmentCount, 1) {
                        let t = Double(segment) / Double(max(curveSegmentCount, 1))
                        flattened.append(.line(to: cubicBezier(start: start, control1: control1, control2: control2, end: point, t: t)))
                    }
                    currentPoint = point
                case .close:
                    flattened.append(.close)
                }
            }

            return CADPath(elements: flattened)
        }

        private func cubicBezier(
            start: CADPoint,
            control1: CADPoint,
            control2: CADPoint,
            end: CADPoint,
            t: Double
        ) -> CADPoint {
            let mt = 1 - t
            let x = mt * mt * mt * start.x
                + 3 * mt * mt * t * control1.x
                + 3 * mt * t * t * control2.x
                + t * t * t * end.x
            let y = mt * mt * mt * start.y
                + 3 * mt * mt * t * control1.y
                + 3 * mt * t * t * control2.y
                + t * t * t * end.y
            return CADPoint(x: x, y: y)
        }
    }
}
