extension SiteKeeperCADKernel {
    struct CADLayoutResolution: Equatable, Codable {
        var layout: CADLayout
        var entities: [CADEntity]
        var clipBounds: CADBounds
        var diagnostics: CADDrawingDiagnostics
    }

    struct CADLayoutResolver {
        func activeLayout(in database: CADDatabase, preferredLayoutID: String?) -> CADLayout {
            if let preferredLayoutID,
               let layout = database.layouts.first(where: { $0.id == preferredLayoutID }) {
                return layout
            }
            return database.layouts.first(where: \.isModelSpace) ?? .modelSpace
        }

        func resolve(
            database: CADDatabase,
            viewport: CADViewport?,
            options: CADRenderOptions
        ) -> CADLayoutResolution {
            let preferredLayoutID = options.layoutID ?? viewport?.layoutID
            let layout = activeLayout(in: database, preferredLayoutID: preferredLayoutID)
            let renderClip = renderClipBounds(viewport: viewport, options: options)

            if layout.isModelSpace {
                return CADLayoutResolution(
                    layout: layout,
                    entities: clip(
                        database.entities.filter { $0.layoutID == layout.id },
                        to: renderClip
                    ),
                    clipBounds: renderClip,
                    diagnostics: CADDrawingDiagnostics()
                )
            }

            var diagnostics = CADDrawingDiagnostics()
            var resolved = database.entities.filter { $0.layoutID == layout.id }

            let viewports = database.viewports.filter {
                $0.layoutID == layout.id && (layout.viewportIDs.isEmpty || layout.viewportIDs.contains($0.id))
            }

            if viewports.isEmpty {
                diagnostics.append(
                    CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_LAYOUT_VIEWPORT_MISSING",
                        message: "Paper space layout has no resolved model viewport.",
                        detail: layout.id
                    )
                )
            }

            for paperViewport in viewports {
                let viewportClip = paperViewport.clipBounds
                let modelEntities = database.entities
                    .filter { $0.layoutID == CADLayout.modelSpace.id }
                    .filter { viewportClip.isEmpty || $0.bounds.isEmpty || $0.bounds.intersects(viewportClip) }
                    .map { entity in
                        var copy = entity
                        copy.layoutID = layout.id
                        copy.diagnostics = copy.diagnostics.appending(
                            CADDrawingDiagnostics.Entry(
                                severity: .info,
                                code: "CAD_LAYOUT_VIEWPORT_CLIPPED",
                                message: "Model-space entity emitted through paper-space viewport.",
                                detail: paperViewport.id
                            )
                        )
                        return copy
                    }
                resolved.append(contentsOf: modelEntities)
            }

            return CADLayoutResolution(
                layout: layout,
                entities: clip(resolved, to: renderClip),
                clipBounds: renderClip,
                diagnostics: diagnostics
            )
        }

        private func renderClipBounds(viewport: CADViewport?, options: CADRenderOptions) -> CADBounds {
            if let viewport, !viewport.clipBounds.isEmpty {
                return viewport.clipBounds
            }
            return options.viewportBounds
        }

        private func clip(_ entities: [CADEntity], to bounds: CADBounds) -> [CADEntity] {
            guard !bounds.isEmpty else { return entities }
            return entities.filter { entity in
                entity.bounds.isEmpty || entity.bounds.intersects(bounds)
            }
        }
    }
}
