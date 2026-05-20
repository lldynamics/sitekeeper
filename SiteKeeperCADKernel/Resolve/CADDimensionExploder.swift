extension SiteKeeperCADKernel {
    struct CADDimensionExploder {
        func explode(_ entity: CADEntity) -> [CADEntity] {
            guard entity.kind == .dimension else { return [entity] }
            guard let endpoints = dimensionEndpoints(for: entity) else {
                var copy = entity
                copy.unsupportedReason = "Dimension has no usable geometry."
                copy.diagnostics = copy.diagnostics.appending(
                    CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_DIMENSION_DEGRADED",
                        message: "Dimension could not be exploded; original object preserved.",
                        detail: entity.sourceHandle
                    )
                )
                return [copy]
            }

            let start = endpoints.start
            let end = endpoints.end
            let distance = max(start.distance(to: end), 1)
            let arrowSize = min(max(distance * 0.06, 1.5), 6)
            let midpoint = CADPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let baseDiagnostics = entity.diagnostics.appending(
                CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: "CAD_DIMENSION_EXPLODED_SIMPLIFIED",
                    message: "Dimension simplified to line, arrows, and text.",
                    detail: entity.sourceHandle
                )
            )

            let dimensionLine = makeEntity(
                from: entity,
                kind: .line,
                path: CADPath(elements: [.move(to: start), .line(to: end)]),
                diagnostics: baseDiagnostics
            )
            let startArrow = makeEntity(
                from: entity,
                kind: .polyline,
                path: arrowPath(at: start, toward: end, size: arrowSize),
                diagnostics: baseDiagnostics
            )
            let endArrow = makeEntity(
                from: entity,
                kind: .polyline,
                path: arrowPath(at: end, toward: start, size: arrowSize),
                diagnostics: baseDiagnostics
            )
            let textEntity = makeTextEntity(
                from: entity,
                midpoint: midpoint,
                fallbackText: formattedDistance(distance),
                diagnostics: baseDiagnostics
            )

            return [dimensionLine, startArrow, endArrow, textEntity]
        }

        private func dimensionEndpoints(for entity: CADEntity) -> (start: CADPoint, end: CADPoint)? {
            if let points = entity.path?.points, points.count >= 2 {
                return (points[0], points[points.count - 1])
            }
            guard !entity.bounds.isEmpty else { return nil }
            return (
                CADPoint(x: entity.bounds.minX, y: entity.bounds.minY),
                CADPoint(x: entity.bounds.maxX, y: entity.bounds.minY)
            )
        }

        private func arrowPath(at tip: CADPoint, toward target: CADPoint, size: Double) -> CADPath {
            let vector = CADVector(dx: target.x - tip.x, dy: target.y - tip.y).normalized
            let perpendicular = CADVector(dx: -vector.dy, dy: vector.dx)
            let base = tip.offset(dx: vector.dx * size, dy: vector.dy * size)
            let left = base.offset(dx: perpendicular.dx * size * 0.45, dy: perpendicular.dy * size * 0.45)
            let right = base.offset(dx: -perpendicular.dx * size * 0.45, dy: -perpendicular.dy * size * 0.45)
            return CADPath(elements: [
                .move(to: left),
                .line(to: tip),
                .line(to: right)
            ])
        }

        private func makeEntity(
            from source: CADEntity,
            kind: CADEntityKind,
            path: CADPath,
            diagnostics: CADDrawingDiagnostics
        ) -> CADEntity {
            CADEntity(
                kind: kind,
                layerID: source.layerID,
                layoutID: source.layoutID,
                color: source.color,
                lineType: source.lineType,
                lineWeight: source.lineWeight,
                path: path,
                transform: source.transform,
                bounds: path.bounds,
                visibility: source.visibility,
                sourceHandle: source.sourceHandle,
                diagnostics: diagnostics
            )
        }

        private func makeTextEntity(
            from source: CADEntity,
            midpoint: CADPoint,
            fallbackText: String,
            diagnostics: CADDrawingDiagnostics
        ) -> CADEntity {
            var text = source.text ?? CADTextRun(rawText: fallbackText, insertionPoint: midpoint)
            text.insertionPoint = midpoint
            if text.rawText.isEmpty {
                text.rawText = fallbackText
            }
            return CADEntity(
                kind: .text,
                layerID: source.layerID,
                layoutID: source.layoutID,
                color: source.color,
                lineType: source.lineType,
                lineWeight: source.lineWeight,
                text: text,
                transform: source.transform,
                bounds: CADBounds(minX: midpoint.x, minY: midpoint.y, maxX: midpoint.x, maxY: midpoint.y),
                visibility: source.visibility,
                sourceHandle: source.sourceHandle,
                diagnostics: diagnostics
            )
        }

        private func formattedDistance(_ value: Double) -> String {
            let rounded = (value * 1000).rounded() / 1000
            return String(rounded)
        }
    }
}
