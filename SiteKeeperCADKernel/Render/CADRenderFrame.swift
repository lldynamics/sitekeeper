import Foundation

extension SiteKeeperCADKernel {
    struct CADRenderFrame: Equatable, Codable {
        var id: UUID
        var databaseID: UUID
        var bounds: CADBounds
        var commands: [CADRenderCommand]
        var textTraces: [CADTextTrace]
        var performance: CADPerformanceTrace

        init(
            id: UUID = UUID(),
            databaseID: UUID,
            bounds: CADBounds,
            commands: [CADRenderCommand],
            textTraces: [CADTextTrace] = [],
            performance: CADPerformanceTrace = CADPerformanceTrace()
        ) {
            self.id = id
            self.databaseID = databaseID
            self.bounds = bounds
            self.commands = commands
            self.textTraces = textTraces
            self.performance = performance
        }

        func writeTextTrace(to url: URL) throws {
            try CADTextTraceJSONLWriter().write(textTraces, to: url)
        }

        func writeFontDiagnostics(to url: URL) throws {
            try CADFontDiagnosticsJSONWriter().write(from: textTraces, to: url)
        }
    }
}
