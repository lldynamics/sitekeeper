import Foundation

enum ProjectDetailDrawingHelper {
    static func drawingIcon(_ fileType: String) -> String {
        switch fileType.lowercased() {
        case "pdf":
            return "doc.richtext.fill"
        case "dwg", "dxf":
            return "point.3.connected.trianglepath.dotted"
        default:
            return "doc.fill"
        }
    }

    static func nextDrawingVersion(name: String, drawings: [ProjectDrawing]) -> String {
        let sameName = drawings.filter { $0.name == name }
        let versions = sameName.map(\.version).compactMap(versionNumber)
        let next = (versions.max() ?? 0) + 1
        return "V\(next)"
    }

    static func normalizedVersion(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = versionNumber(trimmed) {
            return "V\(n)"
        }
        if trimmed.isEmpty {
            return "V1"
        }
        return trimmed.uppercased()
    }

    static func versionNumber(_ version: String) -> Int? {
        let upper = version.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if upper.hasPrefix("V"), let value = Int(upper.dropFirst()) {
            return value
        }
        return Int(upper)
    }
}
