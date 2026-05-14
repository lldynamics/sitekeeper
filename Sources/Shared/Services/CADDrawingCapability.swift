import Foundation

enum CADDrawingCapability {
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
}
