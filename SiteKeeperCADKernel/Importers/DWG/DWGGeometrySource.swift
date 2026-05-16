import Foundation

extension SiteKeeperCADKernel {
    typealias CADDiagnostic = CADDrawingDiagnostics.Entry

    struct DWGImportContext: Equatable, Codable {
        var importID: UUID
        var startedAt: Date
        var preferredLayoutID: String?

        init(
            importID: UUID = UUID(),
            startedAt: Date = Date(),
            preferredLayoutID: String? = nil
        ) {
            self.importID = importID
            self.startedAt = startedAt
            self.preferredLayoutID = preferredLayoutID
        }

        static var `default`: DWGImportContext {
            DWGImportContext()
        }
    }

    struct DWGGeometryImportResult: Equatable, Codable {
        var database: CADDatabase
        var geometryParsed: Bool
        var drawableEntityCount: Int
        var diagnostics: [CADDiagnostic]
        var performanceTrace: CADPerformanceTrace
        var textTrace: [CADTextTrace]
        var source: String

        init(
            database: CADDatabase,
            geometryParsed: Bool? = nil,
            drawableEntityCount: Int? = nil,
            diagnostics: [CADDiagnostic]? = nil,
            performanceTrace: CADPerformanceTrace? = nil,
            textTrace: [CADTextTrace]? = nil,
            source: String
        ) {
            self.database = database
            self.geometryParsed = geometryParsed ?? database.geometryParsed
            self.drawableEntityCount = drawableEntityCount ?? database.drawableEntityCount
            self.diagnostics = diagnostics ?? database.diagnostics.entries
            self.performanceTrace = performanceTrace ?? database.performanceTrace
            self.textTrace = textTrace ?? database.textTrace
            self.source = source
        }
    }

    protocol DWGGeometrySource {
        var id: String { get }

        func canImport(file: CADFile, context: DWGImportContext) -> Bool

        func importGeometry(
            file: CADFile,
            context: DWGImportContext
        ) async throws -> DWGGeometryImportResult
    }
}

extension SiteKeeperCADKernel.DWGGeometrySource {
    func canImportDWG(file: SiteKeeperCADKernel.CADFile) -> Bool {
        canImport(file: file, context: .default)
    }

    func importDWG(file: SiteKeeperCADKernel.CADFile) async throws -> SiteKeeperCADKernel.CADExternalSDKDrawing {
        let result = try await importGeometry(file: file, context: .default)
        var database = result.database
        database.performanceTrace = result.performanceTrace
        database.textTrace = result.textTrace
        return SiteKeeperCADKernel.CADExternalSDKDrawing(database: database)
    }
}
