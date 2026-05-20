extension SiteKeeperCADKernel {
    struct CADLayer: Identifiable, Equatable, Codable {
        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case isVisible
            case isLocked
            case colorARGB
            case lineWeight
            case lineType
        }

        var id: String
        var name: String
        var isVisible: Bool
        var isLocked: Bool
        var colorARGB: UInt32
        var lineWeight: Double
        var lineType: String

        init(
            id: String,
            name: String,
            isVisible: Bool = true,
            isLocked: Bool = false,
            colorARGB: UInt32 = 0xFF2F3437,
            lineWeight: Double = 0.25,
            lineType: String = "Continuous"
        ) {
            self.id = id
            self.name = name
            self.isVisible = isVisible
            self.isLocked = isLocked
            self.colorARGB = colorARGB
            self.lineWeight = lineWeight
            self.lineType = lineType
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let id = try container.decode(String.self, forKey: .id)
            self.init(
                id: id,
                name: try container.decodeIfPresent(String.self, forKey: .name) ?? id,
                isVisible: try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true,
                isLocked: try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false,
                colorARGB: try container.decodeIfPresent(UInt32.self, forKey: .colorARGB) ?? 0xFF2F3437,
                lineWeight: try container.decodeIfPresent(Double.self, forKey: .lineWeight) ?? 0.25,
                lineType: try container.decodeIfPresent(String.self, forKey: .lineType) ?? "Continuous"
            )
        }

        static let `default` = CADLayer(id: "0", name: "0")
    }
}
