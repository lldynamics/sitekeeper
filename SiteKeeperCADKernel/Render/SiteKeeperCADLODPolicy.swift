extension SiteKeeperCADKernel {
    struct CADLODPolicy: Equatable, Codable {
        var simplifyEntityThreshold: Int
        var minTextHeightOnScreen: Double
        var minDimensionHeightOnScreen: Double
        var minLineLengthOnScreen: Double
        var zoomedOutScaleThreshold: Double
        var maxHatchBoundaryElements: Int

        init(
            simplifyEntityThreshold: Int = 20_000,
            minTextHeightOnScreen: Double = 6,
            minDimensionHeightOnScreen: Double = 5,
            minLineLengthOnScreen: Double = 1.5,
            zoomedOutScaleThreshold: Double = 0.05,
            maxHatchBoundaryElements: Int = 48
        ) {
            self.simplifyEntityThreshold = simplifyEntityThreshold
            self.minTextHeightOnScreen = minTextHeightOnScreen
            self.minDimensionHeightOnScreen = minDimensionHeightOnScreen
            self.minLineLengthOnScreen = minLineLengthOnScreen
            self.zoomedOutScaleThreshold = zoomedOutScaleThreshold
            self.maxHatchBoundaryElements = maxHatchBoundaryElements
        }

        static let standard = CADLODPolicy()

        func shouldSimplify(entityCount: Int, zoomScale: Double) -> Bool {
            zoomScale < zoomedOutScaleThreshold
                || (entityCount > simplifyEntityThreshold && zoomScale < zoomedOutScaleThreshold * 4)
        }

        func decision(
            for entity: CADEntity,
            totalEntityCount: Int,
            zoomScale: Double,
            interactionPhase: CADRenderInteractionPhase
        ) -> CADLODDecision {
            let effectiveZoomScale = max(zoomScale, 0.0001)
            if hasDiagnostic(entity, code: "CAD_HATCH_SKIPPED_LOW_ZOOM") {
                return .skip("CAD_HATCH_SKIPPED_LOW_ZOOM")
            }

            if interactionPhase == .zooming {
                return zoomingDecision(for: entity, zoomScale: effectiveZoomScale)
            }

            if isTextEntity(entity), totalEntityCount <= 512 {
                return .render
            }

            guard shouldSimplify(entityCount: totalEntityCount, zoomScale: effectiveZoomScale) else {
                return .render
            }

            if isTinyLine(entity, zoomScale: effectiveZoomScale) {
                return .skip("CAD_LOD_TINY_LINE_SKIPPED")
            }

            switch entity.kind {
            case .text, .mtext, .attrib:
                if textHeight(for: entity) * effectiveZoomScale < minTextHeightOnScreen {
                    return .skip("CAD_LOD_SMALL_TEXT_SKIPPED")
                }
                return .render
            case .hatch:
                if isComplexHatch(entity) {
                    return .skip("CAD_LOD_COMPLEX_HATCH_SKIPPED")
                }
                return .render
            default:
                if isDimensionEntity(entity),
                   max(entity.bounds.width, entity.bounds.height) * effectiveZoomScale < minDimensionHeightOnScreen {
                    return .skip("CAD_LOD_SMALL_DIMENSION_SKIPPED")
                }
                return .render
            }
        }

        private func zoomingDecision(for entity: CADEntity, zoomScale: Double) -> CADLODDecision {
            switch entity.kind {
            case .line, .point, .polyline, .lwPolyline, .circle, .arc, .ellipse:
                if isTinyLine(entity, zoomScale: zoomScale) {
                    return .skip("CAD_LOD_ZOOMING_TINY_LINE_SKIPPED")
                }
                return .render
            case .text, .mtext, .attrib:
                return .skip("CAD_LOD_ZOOMING_TEXT_SKIPPED")
            case .dimension:
                return .skip("CAD_LOD_ZOOMING_DIMENSION_SKIPPED")
            case .hatch:
                return .skip("CAD_LOD_ZOOMING_HATCH_SKIPPED")
            case .image, .table, .xref, .proxy, .unsupported, .insert, .blockReference:
                return entity.path == nil ? .placeholder("CAD_LOD_ZOOMING_COMPLEX_PLACEHOLDER") : .render
            case .spline:
                return .render
            }
        }

        private func textHeight(for entity: CADEntity) -> Double {
            entity.text?.height ?? max(entity.bounds.width, entity.bounds.height)
        }

        private func isTinyLine(_ entity: CADEntity, zoomScale: Double) -> Bool {
            guard entity.path != nil else { return false }
            guard entity.kind == .line || entity.kind == .polyline || entity.kind == .lwPolyline else { return false }
            return max(entity.bounds.width, entity.bounds.height) * zoomScale < minLineLengthOnScreen
        }

        private func isComplexHatch(_ entity: CADEntity) -> Bool {
            guard let path = entity.path else { return true }
            return path.elements.count > maxHatchBoundaryElements
                || path.elements.contains {
                    if case .curve = $0 { return true }
                    return false
                }
        }

        private func isDimensionEntity(_ entity: CADEntity) -> Bool {
            entity.kind == .dimension || entity.diagnostics.entries.contains { $0.code.hasPrefix("CAD_DIMENSION") }
        }

        private func isTextEntity(_ entity: CADEntity) -> Bool {
            switch entity.kind {
            case .text, .mtext, .attrib:
                return entity.text != nil
            case .dimension:
                return entity.text != nil
            default:
                return false
            }
        }

        private func hasDiagnostic(_ entity: CADEntity, code: String) -> Bool {
            entity.diagnostics.entries.contains { $0.code == code }
        }
    }

    enum CADLODDecision: Equatable {
        case render
        case placeholder(String)
        case skip(String)
    }
}
