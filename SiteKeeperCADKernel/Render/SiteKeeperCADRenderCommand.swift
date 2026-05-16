extension SiteKeeperCADKernel {
    enum CADRenderCommand: Equatable, Codable {
        case moveTo(CADPoint, style: CADRenderStyle)
        case lineTo(CADPoint, style: CADRenderStyle)
        case polyline([CADPoint], closed: Bool, style: CADRenderStyle)
        case circle(center: CADPoint, radius: Double, style: CADRenderStyle)
        case arc(center: CADPoint, radius: Double, startAngle: Double, endAngle: Double, style: CADRenderStyle)
        case ellipse(center: CADPoint, radiusX: Double, radiusY: Double, rotationRadians: Double, style: CADRenderStyle)
        case text(CADTextRun, style: CADRenderStyle)
        case hatch(CADPath, style: CADRenderStyle)
        case imagePlaceholder(entityID: String, bounds: CADBounds, reason: String)
        case marker(CADPoint, label: String?, style: CADRenderStyle)
        case unsupportedPlaceholder(entityID: String, bounds: CADBounds, reason: String)

        var drawCallCost: Int {
            switch self {
            case .moveTo:
                return 0
            case .lineTo,
                 .polyline,
                 .circle,
                 .arc,
                 .ellipse,
                 .text,
                 .hatch,
                 .imagePlaceholder,
                 .marker,
                 .unsupportedPlaceholder:
                return 1
            }
        }
    }

    struct CADRenderStyle: Equatable, Codable {
        var layerID: String
        var colorARGB: UInt32
        var lineWidth: Double
    }
}
