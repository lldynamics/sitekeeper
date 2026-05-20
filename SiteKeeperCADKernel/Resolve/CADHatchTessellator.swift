import Foundation

extension SiteKeeperCADKernel {
    struct CADHatchTessellator {
        func tessellate(_ entity: CADEntity) -> [CADPath] {
            guard entity.kind == .hatch, let path = entity.path else { return [] }
            return [path]
        }

        func resolve(
            _ entity: CADEntity,
            options: CADRenderOptions,
            sourceEntityCount: Int
        ) -> [CADEntity] {
            guard entity.kind == .hatch else { return [entity] }

            if options.lodPolicy.shouldSimplify(entityCount: sourceEntityCount, zoomScale: options.deviceScale),
               options.deviceScale < 0.05 {
                return [
                    skipped(
                        entity,
                        reason: "Hatch hidden by LOD policy at low zoom.",
                        code: "CAD_HATCH_SKIPPED_LOW_ZOOM"
                    )
                ]
            }

            guard let path = entity.path, !path.elements.isEmpty else {
                return [
                    skipped(
                        entity,
                        reason: "Hatch has no boundary path.",
                        code: "CAD_HATCH_BOUNDARY_MISSING"
                    )
                ]
            }

            let containsCurves = path.elements.contains { element in
                if case .curve = element { return true }
                return false
            }

            var resolved = entity
            resolved.id = UUID()
            resolved.kind = containsCurves ? .polyline : .hatch
            resolved.path = containsCurves ? CADSplineTessellator().flatten(path: path) : path
            resolved.bounds = resolved.path?.bounds ?? entity.bounds
            resolved.diagnostics = resolved.diagnostics.appending(
                CADDrawingDiagnostics.Entry(
                    severity: containsCurves ? .warning : .info,
                    code: containsCurves ? "CAD_HATCH_DEGRADED_TO_BOUNDARY" : "CAD_HATCH_BOUNDARY_RENDERED",
                    message: containsCurves
                        ? "Complex hatch simplified to boundary lines."
                        : "Hatch rendered from boundary path.",
                    detail: entity.sourceHandle
                )
            )
            return [resolved]
        }

        private func skipped(_ entity: CADEntity, reason: String, code: String) -> CADEntity {
            var copy = entity
            copy.id = UUID()
            copy.kind = .unsupported
            copy.path = nil
            copy.text = nil
            copy.unsupportedReason = reason
            copy.diagnostics = copy.diagnostics.appending(
                CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: code,
                    message: reason,
                    detail: entity.sourceHandle
                )
            )
            return copy
        }
    }
}
