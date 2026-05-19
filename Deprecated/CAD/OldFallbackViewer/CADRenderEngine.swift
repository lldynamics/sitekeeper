import Foundation

extension SiteKeeperCADKernel {
    protocol CADRenderEngine {
        func prepare(database: CADDatabase) async throws
        func render(viewport: CADViewport, options: CADRenderOptions) async throws -> CADRenderFrame
    }

    enum CADRenderError: LocalizedError, Equatable {
        case databaseNotPrepared

        var errorDescription: String? {
            switch self {
            case .databaseNotPrepared:
                return "CAD database is not prepared for rendering"
            }
        }
    }
}
