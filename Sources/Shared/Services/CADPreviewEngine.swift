import Foundation

enum CADPreviewEngine: String, CaseIterable {
    case libreDWG

    var title: String {
        switch self {
        case .libreDWG:
            return String(localized: "LibreDWG 预览")
        }
    }
}

enum CADPreviewEngineStore {
    static var selected: CADPreviewEngine {
        .libreDWG
    }

    static func setSelected(_: CADPreviewEngine) {
    }
}

enum CADPreviewCapability {
    static func isCADFile(extension fileExtension: String) -> Bool {
        let ext = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ext == "dwg" || ext == "dxf"
    }

    static func isLibreDWGRendererAvailable() -> Bool {
#if canImport(LibreDWGBridge)
        true
#else
        false
#endif
    }

    static func isProfessionalEngineAvailable() -> Bool {
        isLibreDWGRendererAvailable()
    }

    static func resolvedEngine(_: CADPreviewEngine) -> CADPreviewEngine {
        .libreDWG
    }
}
