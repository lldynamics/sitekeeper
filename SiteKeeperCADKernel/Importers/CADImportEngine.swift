import Foundation

extension SiteKeeperCADKernel {
    struct CADImportRequest: Equatable, Codable {
        var file: CADFile
        var preferredLayoutID: String?
        var visibleLayerIDs: Set<String>?
    }

    enum CADImportError: LocalizedError, Equatable, Codable {
        case engineNotInstalled
        case unsupportedFormat(CADFileFormat)
        case invalidIntermediateJSON
        case importerNotReady(String)

        var errorDescription: String? {
            switch self {
            case .engineNotInstalled:
                return "CAD engine is not installed"
            case let .unsupportedFormat(format):
                return "Unsupported CAD format: \(format.rawValue)"
            case .invalidIntermediateJSON:
                return "Invalid intermediate CAD JSON"
            case let .importerNotReady(message):
                return message
            }
        }
    }

    protocol CADImportEngine {
        func canImport(file: CADFile) -> Bool
        func importDrawing(file: CADFile) async throws -> CADDatabase
    }
}

extension SiteKeeperCADKernel.CADImportEngine {
    func canImport(_ request: SiteKeeperCADKernel.CADImportRequest) -> Bool {
        canImport(file: request.file)
    }

    func importDatabase(_ request: SiteKeeperCADKernel.CADImportRequest) async -> SiteKeeperCADKernel.CADOpenResult {
        do {
            let database = try await importDrawing(file: request.file)
            return .evaluated(database)
        } catch let error as SiteKeeperCADKernel.CADImportError {
            switch error {
            case .engineNotInstalled:
                return .unsupported(error.localizedDescription)
            case .unsupportedFormat:
                return .unsupported(error.localizedDescription)
            case .invalidIntermediateJSON, .importerNotReady:
                return SiteKeeperCADKernel.CADOpenResult.failed(
                    SiteKeeperCADKernel.CADDrawingDiagnostics(entries: [
                        SiteKeeperCADKernel.CADDrawingDiagnostics.Entry(
                            severity: .error,
                            code: "CAD_IMPORT_FAILED",
                            message: error.localizedDescription,
                            detail: request.file.displayName
                        )
                    ])
                )
            }
        } catch {
            return SiteKeeperCADKernel.CADOpenResult.failed(
                SiteKeeperCADKernel.CADDrawingDiagnostics(entries: [
                    SiteKeeperCADKernel.CADDrawingDiagnostics.Entry(
                        severity: .error,
                        code: "CAD_IMPORT_FAILED",
                        message: error.localizedDescription,
                        detail: request.file.displayName
                    )
                ])
            )
        }
    }
}
