import Foundation

extension SiteKeeperCADKernel {
    enum CADDWGGeometryAdapterRegistry {
        private static var adapters: [any CADDWGGeometryAdapter] = []

        static func register(_ adapter: any CADDWGGeometryAdapter) {
            adapters.removeAll { $0.id == adapter.id }
            adapters.append(adapter)
        }

        static func reset() {
            adapters = []
        }

        static func registeredAdapterIDs() -> [String] {
            adapters.map(\.id)
        }

        static func adapter(for file: CADFile) -> (any CADDWGGeometryAdapter)? {
            adapters.first { $0.canImportDWG(file: file) }
        }
    }

    struct DWGSidecarJSONGeometryAdapter: CADDWGGeometryAdapter {
        let id = "sitekeeper.dwg.libredwg"
        private let fileManager: FileManager

        init(fileManager: FileManager = .default) {
            self.fileManager = fileManager
        }

        func canImportDWG(file: CADFile) -> Bool {
            file.format == .dwg && sidecarURL(for: file.url) != nil
        }

        func importDWG(file: CADFile) async throws -> CADExternalSDKDrawing {
            guard let sidecarURL = sidecarURL(for: file.url) else {
                throw CADImportError.importerNotReady("DWG sidecar JSON was not found.")
            }

            let sidecarFile = CADFile(
                url: sidecarURL,
                displayName: "\(file.displayName).sidecar.json",
                format: .intermediateJSON
            )
            let database = try await IntermediateJSONImportEngine().importDrawing(file: sidecarFile)
            var drawing = CADExternalSDKDrawing(database: database)
            drawing.diagnostics.append(
                CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_DWG_LIBREDWG_WORKER_JSON_USED",
                    message: "LibreDWG worker JSON 已转换为 CADDatabase。",
                    detail: sidecarURL.lastPathComponent
                )
            )
            return drawing
        }

        private func sidecarURL(for dwgURL: URL) -> URL? {
            sidecarCandidates(for: dwgURL).first { candidate in
                fileManager.fileExists(atPath: candidate.path)
            }
        }

        private func sidecarCandidates(for dwgURL: URL) -> [URL] {
            [
                dwgURL.appendingPathExtension("sitekeeper-cad.json"),
                dwgURL.deletingPathExtension()
                    .appendingPathExtension("sitekeeper-cad.json"),
                dwgURL.appendingPathExtension("sitekeeper-cad")
                    .appendingPathComponent("drawing.sitekeeper-cad.json"),
                dwgURL.deletingPathExtension()
                    .appendingPathExtension("sitekeeper-cad")
                    .appendingPathComponent("drawing.sitekeeper-cad.json"),
                dwgURL.deletingLastPathComponent()
                    .appendingPathComponent("drawing.sitekeeper-cad.json")
            ]
        }
    }
}
