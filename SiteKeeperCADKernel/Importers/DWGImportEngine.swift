import Foundation

extension SiteKeeperCADKernel {
    protocol CADDWGGeometryAdapter: DWGGeometrySource {
        var id: String { get }

        func canImportDWG(file: CADFile) -> Bool
        func importDWG(file: CADFile) async throws -> CADExternalSDKDrawing
    }
}

extension SiteKeeperCADKernel.CADDWGGeometryAdapter {
    func canImport(file: SiteKeeperCADKernel.CADFile, context _: SiteKeeperCADKernel.DWGImportContext) -> Bool {
        canImportDWG(file: file)
    }

    func importGeometry(
        file: SiteKeeperCADKernel.CADFile,
        context _: SiteKeeperCADKernel.DWGImportContext
    ) async throws -> SiteKeeperCADKernel.DWGGeometryImportResult {
        let drawing = try await importDWG(file: file)
        let database = drawing.makeDatabase(file: file, adapterID: id)
        return SiteKeeperCADKernel.DWGGeometryImportResult(
            database: database,
            geometryParsed: database.geometryParsed,
            drawableEntityCount: database.drawableEntityCount,
            diagnostics: database.diagnostics.entries,
            performanceTrace: database.performanceTrace,
            textTrace: database.textTrace,
            source: id
        )
    }
}

extension SiteKeeperCADKernel {
    struct DWGImportEngine: CADImportEngine {
        let id = "sitekeeper.dwg.diagnostic"
        let supportedFormats: Set<CADFileFormat> = [.dwg]
        private let geometryImportEngine: DWGGeometryImportEngine

        init(
            geometryAdapter: (any CADDWGGeometryAdapter)? = nil,
            geometryImportEngine: DWGGeometryImportEngine? = nil
        ) {
            self.geometryImportEngine = geometryImportEngine
                ?? DWGGeometryImportEngine(preferredAdapter: geometryAdapter)
        }

        func canImport(file: CADFile) -> Bool {
            supportedFormats.contains(file.format)
        }

        func importDrawing(file: CADFile) async throws -> CADDatabase {
            let geometryOutcome = await geometryImportEngine.importDrawing(file: file)
            if var database = geometryOutcome.database {
                geometryOutcome.diagnostics.forEach { database.diagnostics.append($0) }
                return database
            }

            let inspection = inspect(file: file)
            let diagnostics = CADDrawingDiagnostics(entries: inspection.diagnostics + geometryOutcome.diagnostics + [
                CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: "CAD_DWG_DIAGNOSTIC_ONLY",
                    message: "DWG 几何来源不可用，仅输出诊断信息。",
                    detail: "未导入真实可绘制几何，因此不会进入正式在线 CAD 查看器。"
                )
            ])

            var database = CADDatabase(
                file: file,
                units: .unitless,
                extents: .empty,
                layers: [.default],
                layouts: [.modelSpace],
                entities: [],
                diagnostics: diagnostics
            )
            database.setImportMetadata(
                geometryParsed: false,
                isDiagnosticOnly: true,
                importSource: id
            )
            database.performanceTrace = CADPerformanceTrace(
                fileSizeBytes: file.byteCount ?? fileSizeBytes(at: file.url),
                entityCount: 0,
                visibleEntityCount: 0,
                renderCommandCount: 0,
                drawCallCount: 0,
                spatialIndexBuildMs: 0,
                resolveMs: 0,
                renderMs: 0,
                firstFrameMs: 0,
                frameTimeMilliseconds: 0,
                peakMemoryMB: 0,
                skippedEntityCount: 0,
                warnings: diagnostics.entries.map { entry in
                    if let detail = entry.detail, !detail.isEmpty {
                        return "\(entry.code): \(entry.message) (\(detail))"
                    }
                    return "\(entry.code): \(entry.message)"
                }
            )
            return database
        }

        private func inspect(file: CADFile) -> DWGInspection {
            let fileSize = file.byteCount ?? fileSizeBytes(at: file.url)
            let header = readHeader(at: file.url)
            var diagnostics: [CADDrawingDiagnostics.Entry] = [
                CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_DWG_IMPORT_ENGINE_CONNECTED",
                    message: "DWG 导入入口已接入。",
                    detail: file.displayName
                ),
                CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_DWG_FILE_SIZE",
                    message: "已记录 DWG 文件大小。",
                    detail: "\(fileSize) bytes"
                )
            ]

            if let version = dwgVersion(from: header) {
                diagnostics.append(
                    CADDrawingDiagnostics.Entry(
                        severity: .info,
                        code: "CAD_DWG_VERSION_DETECTED",
                        message: "已识别 DWG 版本头。",
                        detail: version
                    )
                )
            } else {
                diagnostics.append(
                    CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_DWG_VERSION_UNKNOWN",
                        message: "未识别 DWG 版本头。",
                        detail: header.map { String(format: "%02X", $0) }.joined(separator: " ")
                    )
                )
            }

            diagnostics.append(
                CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: "CAD_DWG_GEOMETRY_IMPORT_PENDING",
                    message: "DWG 几何数据未导入成功。",
                    detail: "请先运行外部 CAD worker，生成 drawing.sitekeeper-cad.json 后再由 App 读取。"
                )
            )

            return DWGInspection(diagnostics: diagnostics)
        }

        private func fileSizeBytes(at url: URL) -> Int {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber else {
                return 0
            }
            return size.intValue
        }

        private func readHeader(at url: URL) -> [UInt8] {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
            defer { try? handle.close() }
            let data = (try? handle.read(upToCount: 16)) ?? Data()
            return Array(data)
        }

        private func dwgVersion(from header: [UInt8]) -> String? {
            guard header.count >= 6 else { return nil }
            let prefix = String(decoding: header.prefix(6), as: UTF8.self)
            guard prefix.hasPrefix("AC") else { return nil }
            switch prefix {
            case "AC1009": return "AutoCAD R12 (AC1009)"
            case "AC1012": return "AutoCAD R13 (AC1012)"
            case "AC1014": return "AutoCAD R14 (AC1014)"
            case "AC1015": return "AutoCAD 2000/2002 (AC1015)"
            case "AC1018": return "AutoCAD 2004/2005/2006 (AC1018)"
            case "AC1021": return "AutoCAD 2007/2008/2009 (AC1021)"
            case "AC1024": return "AutoCAD 2010/2011/2012 (AC1024)"
            case "AC1027": return "AutoCAD 2013/2014/2015/2016/2017 (AC1027)"
            case "AC1032": return "AutoCAD 2018+ (AC1032)"
            default: return "\(prefix)"
            }
        }
    }
}

private struct DWGInspection {
    var diagnostics: [SiteKeeperCADKernel.CADDrawingDiagnostics.Entry]
}
