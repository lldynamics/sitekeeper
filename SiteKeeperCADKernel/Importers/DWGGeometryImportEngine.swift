import Foundation

extension SiteKeeperCADKernel {
    struct DWGGeometryImportOutcome {
        var database: CADDatabase?
        var diagnostics: [CADDrawingDiagnostics.Entry]

        init(
            database: CADDatabase? = nil,
            diagnostics: [CADDrawingDiagnostics.Entry] = []
        ) {
            self.database = database
            self.diagnostics = diagnostics
        }
    }

    struct DWGGeometryImportEngine {
        private let sourceResolver: DWGGeometrySourceResolver

        init(
            preferredAdapter: (any CADDWGGeometryAdapter)? = nil,
            extraAdapters: [any CADDWGGeometryAdapter] = []
        ) {
            self.sourceResolver = DWGGeometrySourceResolver(
                preferredAdapter: preferredAdapter,
                extraAdapters: extraAdapters
            )
        }

        func importDrawing(file: CADFile) async -> DWGGeometryImportOutcome {
            let startTime = CFAbsoluteTimeGetCurrent()
            let context = DWGImportContext(
                startedAt: Date(timeIntervalSinceReferenceDate: startTime)
            )
            let sources = resolvedSources(for: file, context: context)
            guard !sources.isEmpty else {
                return DWGGeometryImportOutcome(
                    diagnostics: [
                        CADDrawingDiagnostics.Entry(
                            severity: .warning,
                            code: "CAD_DWG_GEOMETRY_SOURCE_MISSING",
                            message: "DWG 几何来源未配置。",
                            detail: "未找到 worker 生成的 drawing.sitekeeper-cad.json 或显式注册的几何来源。"
                        )
                    ]
                )
            }

            var attemptDiagnostics: [CADDrawingDiagnostics.Entry] = []
            for source in sources {
                do {
                    let result = try await source.importGeometry(file: file, context: context)
                    var database = result.database
                    result.diagnostics.forEach { diagnostic in
                        if !database.diagnostics.entries.contains(diagnostic) {
                            database.diagnostics.append(diagnostic)
                        }
                    }
                    database.performanceTrace = result.performanceTrace
                    if !result.textTrace.isEmpty {
                        database.textTrace = result.textTrace
                    }
                    enrichDatabase(
                        &database,
                        file: file,
                        sourceID: result.source,
                        startTime: startTime,
                        sourcePerformanceTrace: result.performanceTrace,
                        sourceTextTrace: result.textTrace
                    )
                    if database.drawableEntityCount == 0 || !database.geometryParsed {
                        database.diagnostics.append(
                            CADDrawingDiagnostics.Entry(
                                severity: .warning,
                                code: "CAD_DWG_GEOMETRY_NOT_DRAWABLE",
                                message: "DWG 几何来源返回了不可绘制结果。",
                                detail: "source=\(result.source), drawableEntityCount=\(database.drawableEntityCount)"
                            )
                        )
                        database.setImportMetadata(
                            geometryParsed: false,
                            isMetadataOnly: true,
                            importSource: result.source
                        )
                    }
                    return DWGGeometryImportOutcome(
                        database: database,
                        diagnostics: attemptDiagnostics
                    )
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription
                        ?? String(describing: error)
                    attemptDiagnostics.append(
                        CADDrawingDiagnostics.Entry(
                            severity: .warning,
                            code: "CAD_DWG_GEOMETRY_ADAPTER_FAILED",
                            message: "DWG 几何 source 导入失败。",
                            detail: "source=\(source.id); \(message)"
                        )
                    )
                }
            }

            return DWGGeometryImportOutcome(
                database: nil,
                diagnostics: attemptDiagnostics
            )
        }

        private func resolvedSources(for file: CADFile, context: DWGImportContext) -> [any DWGGeometrySource] {
            sourceResolver.resolveSources(for: file, context: context)
        }

        private func enrichDatabase(
            _ database: inout CADDatabase,
            file: CADFile,
            sourceID: String,
            startTime: CFAbsoluteTime,
            sourcePerformanceTrace: CADPerformanceTrace,
            sourceTextTrace: [CADTextTrace]
        ) {
            database.diagnostics.append(
                CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_DWG_GEOMETRY_ADAPTER_USED",
                    message: "DWG 几何 Source 已导入 CADDatabase。",
                    detail: sourceID
                )
            )

            if !sourceTextTrace.isEmpty {
                database.textTrace = sourceTextTrace
            } else if database.textTrace.isEmpty {
                database.textTrace = database.entities.compactMap { entity in
                    guard let text = entity.text else { return nil }
                    return text.makeTrace(
                        entityId: entity.id.uuidString,
                        entityType: entity.kind
                    )
                }
            }

            let elapsedMs = max((CFAbsoluteTimeGetCurrent() - startTime) * 1000, 0)
            if sourcePerformanceTrace == CADPerformanceTrace() {
                database.performanceTrace = CADPerformanceTrace(
                    fileSizeBytes: file.byteCount ?? fileSizeBytes(at: file.url),
                    entityCount: database.entityCount,
                    visibleEntityCount: database.drawableEntityCount,
                    renderCommandCount: 0,
                    drawCallCount: 0,
                    spatialIndexBuildMs: 0,
                    resolveMs: elapsedMs,
                    renderMs: 0,
                    firstFrameMs: elapsedMs,
                    frameTimeMilliseconds: elapsedMs,
                    peakMemoryMB: 0,
                    skippedEntityCount: database.placeholderEntityCount,
                    warnings: database.importWarnings
                )
            } else {
                database.performanceTrace = sourcePerformanceTrace
            }

            if database.drawableEntityCount > 0 {
                database.setImportMetadata(
                    geometryParsed: true,
                    isMetadataOnly: false,
                    importSource: sourceID
                )
            }
        }

        private func fileSizeBytes(at url: URL) -> Int {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber else {
                return 0
            }
            return size.intValue
        }
    }

}
