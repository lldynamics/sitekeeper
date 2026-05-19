import Foundation

extension SiteKeeperCADKernel {
    protocol CADViewerEngine {
        func open(file: CADFile) async throws -> CADOpenResult
        func getLayers() async throws -> [CADLayer]
        func setLayerVisible(_ layerId: String, visible: Bool) async throws
        func getLayouts() async throws -> [CADLayout]
        func setCurrentLayout(_ layoutId: String) async throws
        func render(viewport: CADViewport, options: CADRenderOptions) async throws -> CADRenderFrame
        func measure(_ input: CADMeasureInput) async throws -> CADMeasureResult
        func searchText(_ keyword: String) async throws -> [CADTextSearchResult]
    }

    enum CADViewerEngineError: LocalizedError, Equatable {
        case drawingNotOpen
        case layerNotFound(String)
        case layoutNotFound(String)

        var errorDescription: String? {
            switch self {
            case .drawingNotOpen:
                return "CAD drawing is not open"
            case let .layerNotFound(layerId):
                return "CAD layer not found: \(layerId)"
            case let .layoutNotFound(layoutId):
                return "CAD layout not found: \(layoutId)"
            }
        }
    }
}

extension SiteKeeperCADKernel.CADViewerEngine {
    func open(_ file: SiteKeeperCADKernel.CADFile) async -> SiteKeeperCADKernel.CADOpenResult {
        do {
            return try await open(file: file)
        } catch {
            return SiteKeeperCADKernel.CADOpenResult.failed(
                SiteKeeperCADKernel.CADDrawingDiagnostics(entries: [
                    SiteKeeperCADKernel.CADDrawingDiagnostics.Entry(
                        severity: .error,
                        code: "CAD_VIEWER_OPEN_FAILED",
                        message: error.localizedDescription,
                        detail: file.displayName
                    )
                ])
            )
        }
    }
}
