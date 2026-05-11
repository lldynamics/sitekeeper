import Foundation

enum CADPreviewEngine: String, CaseIterable {
    case systemQuickLook

    var title: String {
        String(localized: "系统 CAD 预览")
    }
}

enum CADPreviewEngineStore {
    static var selected: CADPreviewEngine {
        let raw = UserDefaults.standard.string(forKey: UserPreferenceKeys.cadPreviewEngine) ?? ""
        return StringEnumFallback.value(raw, default: .systemQuickLook)
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

    static func isProfessionalEngineAvailable() -> Bool {
        false
    }
}
