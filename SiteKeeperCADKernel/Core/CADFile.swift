import Foundation

extension SiteKeeperCADKernel {
    enum CADFileFormat: String, Equatable, Codable {
        case dwg
        case dxf
        case intermediateJSON
        case unknown

        init(fileExtension: String) {
            switch fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "dwg": self = .dwg
            case "dxf": self = .dxf
            case "json": self = .intermediateJSON
            default: self = .unknown
            }
        }
    }

    struct CADFile: Equatable, Codable {
        var url: URL
        var displayName: String
        var format: CADFileFormat
        var byteCount: Int?
        var importedAt: Date?

        init(
            url: URL,
            displayName: String? = nil,
            format: CADFileFormat? = nil,
            byteCount: Int? = nil,
            importedAt: Date? = nil
        ) {
            self.url = url
            self.displayName = displayName ?? url.lastPathComponent
            self.format = format ?? CADFileFormat(fileExtension: url.pathExtension)
            self.byteCount = byteCount
            self.importedAt = importedAt
        }
    }
}
