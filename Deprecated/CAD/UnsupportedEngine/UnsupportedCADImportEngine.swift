extension SiteKeeperCADKernel {
    struct UnsupportedCADImportEngine: CADImportEngine {
        let id = "sitekeeper.unsupported"
        let supportedFormats: Set<CADFileFormat> = [.dwg, .dxf, .unknown]

        func canImport(file: CADFile) -> Bool {
            supportedFormats.contains(file.format)
        }

        func importDrawing(file _: CADFile) async throws -> CADDatabase {
            throw CADImportError.engineNotInstalled
        }
    }
}
