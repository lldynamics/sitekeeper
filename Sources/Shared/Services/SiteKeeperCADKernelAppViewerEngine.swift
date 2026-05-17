import CoreGraphics
import Foundation

actor SiteKeeperCADKernelAppViewerEngine: CADViewerEngine {
    private let kernelEngine: SiteKeeperCADKernel.SiteKeeperCADViewerEngine
    private var appDrawingId: UUID?

    init(kernelEngine: SiteKeeperCADKernel.SiteKeeperCADViewerEngine = SiteKeeperCADKernel.SiteKeeperCADViewerEngine()) {
        self.kernelEngine = kernelEngine
    }

    func open(file: CADFile) async throws -> CADOpenResult {
        appDrawingId = file.drawingId
        let result = try await kernelEngine.open(file: kernelFile(from: file))
        let details = technicalDetails(from: result, appFile: file)
        switch result.status {
        case .rendered:
            return CADOpenResult(
                drawingId: file.drawingId,
                openState: .rendered,
                message: "",
                technicalDetails: details
            )
        case .unsupported:
            return CADOpenResult(
                drawingId: file.drawingId,
                openState: .unsupported,
                message: CADViewerMessages.interactivePreviewUnavailableMessage,
                technicalDetails: details
            )
        case .failed:
            return CADOpenResult(
                drawingId: file.drawingId,
                openState: .failed,
                message: CADViewerMessages.interactivePreviewUnavailableMessage,
                technicalDetails: details
            )
        default:
            return CADOpenResult(
                drawingId: file.drawingId,
                openState: .failed,
                message: CADViewerMessages.interactivePreviewUnavailableMessage,
                technicalDetails: details
            )
        }
    }

    func getLayers() async throws -> [CADLayer] {
        try await kernelEngine.getLayers().map {
            CADLayer(id: $0.id, name: $0.name, isVisible: $0.isVisible)
        }
    }

    func setLayerVisible(_ layerId: String, visible: Bool) async throws {
        try await kernelEngine.setLayerVisible(layerId, visible: visible)
    }

    func measure(_ input: CADMeasureInput) async throws -> CADMeasureResult {
        let kernelResult = try await kernelEngine.measure(
            SiteKeeperCADKernel.CADMeasureInput(
                mode: measureMode(from: input.kind),
                points: input.points.map(SiteKeeperCADKernel.CADPoint.init),
                unit: SiteKeeperCADKernel.CADMeasurementUnit.drawingUnit.rawValue
            )
        )
        return CADMeasureResult(value: kernelResult.value, unit: kernelResult.unit)
    }

    func searchText(_ keyword: String) async throws -> [CADTextSearchResult] {
        try await kernelEngine.searchText(keyword).map {
            CADTextSearchResult(
                id: $0.id,
                text: $0.displayText,
                location: $0.worldPoint.cgPoint
            )
        }
    }

    private func kernelFile(from file: CADFile) -> SiteKeeperCADKernel.CADFile {
        let inferredExtension = file.fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let extensionForFormat = inferredExtension.isEmpty ? file.fileType : inferredExtension
        return SiteKeeperCADKernel.CADFile(
            url: file.fileURL,
            displayName: file.displayName,
            format: SiteKeeperCADKernel.CADFileFormat(fileExtension: extensionForFormat),
            byteCount: file.fileSizeBytes,
            importedAt: nil
        )
    }

    private func measureMode(from kind: String) -> SiteKeeperCADKernel.CADMeasureMode {
        switch kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "area", "面积":
            return .area
        case "polyline", "continuous", "连续测距":
            return .polyline
        default:
            return .distance
        }
    }

    private func technicalDetails(
        from result: SiteKeeperCADKernel.CADOpenResult,
        appFile: CADFile
    ) -> CADOpenTechnicalDetails {
        let version = result.diagnostics.entries.first { $0.code == "CAD_DWG_VERSION_DETECTED" }?.detail
        let importEngine = result.database?.importSource
        let geometryParsed = result.database?.geometryParsed ?? false
        let drawableEntityCount = result.database?.drawableEntityCount ?? 0
        let databaseEntityCount = result.database?.entityCount ?? 0
        let renderCommandCount = result.database?.performanceTrace.renderCommandCount ?? 0
        let diagnostics = result.diagnostics.entries.map { entry in
            let detail = (entry.detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "\(entry.code): \(entry.message)"
                : "\(entry.code): \(entry.message) (\(detail))"
        }
        let pipelineTrace = SiteKeeperCADKernel.DWGOpenPipelineTrace(
            fileName: appFile.displayName,
            fileSize: appFile.fileSizeBytes,
            dwgVersion: version,
            libreDwgAvailable: isLibreDWGReferenced(importEngine: importEngine, diagnostics: result.diagnostics),
            adapterEntityCount: databaseEntityCount,
            databaseEntityCount: databaseEntityCount,
            drawableEntityCount: drawableEntityCount,
            renderCommandCount: renderCommandCount,
            extents: result.database?.extents,
            currentLayout: currentLayoutId(from: result.database),
            visibleLayerCount: result.database?.layers.filter(\.isVisible).count ?? 0,
            openState: result.status,
            failureStage: failureStage(for: result)
        )
        return CADOpenTechnicalDetails(
            dwgVersion: version,
            fileSizeBytes: appFile.fileSizeBytes,
            importEngine: importEngine,
            geometryParsed: geometryParsed,
            drawableEntityCount: drawableEntityCount,
            diagnostics: diagnostics,
            pipelineTrace: pipelineTrace
        )
    }

    private func currentLayoutId(from database: SiteKeeperCADKernel.CADDatabase?) -> String? {
        guard let database else { return nil }
        return database.layouts.first(where: \.isModelSpace)?.id ?? database.layouts.first?.id
    }

    private func isLibreDWGReferenced(
        importEngine: String?,
        diagnostics: SiteKeeperCADKernel.CADDrawingDiagnostics
    ) -> Bool {
        if importEngine?.localizedCaseInsensitiveContains("libredwg") == true {
            return true
        }
        return diagnostics.entries.contains { entry in
            entry.code.localizedCaseInsensitiveContains("libredwg")
                || entry.message.localizedCaseInsensitiveContains("libredwg")
                || (entry.detail?.localizedCaseInsensitiveContains("libredwg") == true)
        }
    }

    private func failureStage(for result: SiteKeeperCADKernel.CADOpenResult) -> String {
        guard let database = result.database else {
            return result.status == .failed ? "import_failed" : "no_database"
        }
        if result.status == .rendered {
            return "rendered"
        }
        if !database.geometryParsed {
            return "geometry_source"
        }
        if database.entityCount == 0 {
            return "adapter"
        }
        if database.drawableEntityCount == 0 {
            return "cad_database_drawable_filter"
        }
        if database.performanceTrace.renderCommandCount == 0 {
            return "render_command"
        }
        return "open_state"
    }
}
