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
        private enum CodingKeys: String, CodingKey {
            case layerID
            case colorARGB
            case lineWidth
            case lineType
        }

        var layerID: String
        var colorARGB: UInt32
        var lineWidth: Double
        var lineType: String

        init(
            layerID: String,
            colorARGB: UInt32,
            lineWidth: Double,
            lineType: String = "Continuous"
        ) {
            self.layerID = layerID
            self.colorARGB = colorARGB
            self.lineWidth = lineWidth
            self.lineType = lineType
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                layerID: try container.decode(String.self, forKey: .layerID),
                colorARGB: try container.decode(UInt32.self, forKey: .colorARGB),
                lineWidth: try container.decode(Double.self, forKey: .lineWidth),
                lineType: try container.decodeIfPresent(String.self, forKey: .lineType) ?? "Continuous"
            )
        }
    }
}
