extension CADPoC {
    struct CADRenderPipeline {
        var lodPolicy: SiteKeeperCADKernel.CADLODPolicy

        init(lodPolicy: SiteKeeperCADKernel.CADLODPolicy = .standard) {
            self.lodPolicy = lodPolicy
        }

        func commands(from entities: [SiteKeeperCADKernel.CADEntity]) -> [SiteKeeperCADKernel.CADRenderCommand] {
            entities.flatMap { entity -> [SiteKeeperCADKernel.CADRenderCommand] in
                let style = SiteKeeperCADKernel.CADRenderStyle(
                    layerID: entity.layerID,
                    colorARGB: entity.color,
                    lineWidth: max(entity.lineWeight, 2)
                )

                guard let path = entity.path else { return [] }
                let points = path.points
                guard points.count >= 2 else { return [] }

                switch entity.kind {
                case .line:
                    return [.polyline(points, closed: false, style: style)]
                case .polyline, .lwPolyline:
                    return [.polyline(points, closed: path.isClosed, style: style)]
                default:
                    return []
                }
            }
        }

        func commandCount(in frame: SiteKeeperCADKernel.CADRenderFrame) -> Int {
            frame.commands.count
        }
    }
}

private extension SiteKeeperCADKernel.CADPath {
    var isClosed: Bool {
        elements.contains {
            if case .close = $0 {
                return true
            }
            return false
        }
    }
}
