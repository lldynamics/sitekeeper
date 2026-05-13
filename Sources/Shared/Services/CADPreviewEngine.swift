import Foundation

enum CADPreviewEngine: String, CaseIterable {
    case systemQuickLook
    case libreDWG

    var title: String {
        switch self {
        case .systemQuickLook:
            return String(localized: "系统 CAD 预览")
        case .libreDWG:
            return String(localized: "LibreDWG 预览")
        }
    }
}

enum CADPreviewEngineStore {
    static var selected: CADPreviewEngine {
        let raw = UserDefaults.standard.string(forKey: UserPreferenceKeys.cadPreviewEngine) ?? ""
        return StringEnumFallback.value(raw, default: .libreDWG)
    }

    static func setSelected(_ engine: CADPreviewEngine) {
        UserDefaults.standard.set(engine.rawValue, forKey: UserPreferenceKeys.cadPreviewEngine)
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

    static func resolvedEngine(_ preferred: CADPreviewEngine) -> CADPreviewEngine {
        switch preferred {
        case .systemQuickLook:
            return .systemQuickLook
        case .libreDWG:
            return isLibreDWGRendererAvailable() ? .libreDWG : .systemQuickLook
        }
    }
}
