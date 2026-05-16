import CoreGraphics
import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct CADKernelTests {
    @Test func fileFormatDetectionUsesExtension() {
        #expect(CADKernelFileFormat(fileExtension: "DWG") == .dwg)
        #expect(CADKernelFileFormat(fileExtension: "dxf") == .dxf)
        #expect(CADKernelFileFormat(fileExtension: "pdf") == .pdf)
        #expect(CADKernelFileFormat(fileExtension: "png") == .unknown)
    }

    @Test func diagnosticImportInspectsDWGHeaderWithoutGeometry() async throws {
        CADKernelImportRegistry.resetDefaultEngines()
        let url = try makeTemporaryFile(name: "sample.dwg", bytes: Array("AC1027 mock dwg".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await CADKernelImportRegistry.importDocument(CADKernelImportRequest(fileURL: url))

        #expect(result.document.metadata.sourceFormat == .dwg)
        #expect(result.document.metadata.dwgVersion == "AC1027")
        #expect(!result.document.hasRenderableGeometry)
        #expect(result.diagnostics.contains { $0.code == "CAD_IMPORT_ENGINE_BOOTSTRAP_ONLY" })
    }

    @Test func documentBoundsUnionsRenderableEntities() {
        let document = CADKernelDocument(
            metadata: CADKernelMetadata(
                sourceFileName: "bounds.dxf",
                sourceFormat: .dxf,
                importerID: "test"
            ),
            entities: [
                CADKernelEntity(
                    kind: .line,
                    layerID: CADKernelDocument.defaultLayerID,
                    bounds: CGRect(x: 0, y: 0, width: 10, height: 5)
                ),
                CADKernelEntity(
                    kind: .circle,
                    layerID: CADKernelDocument.defaultLayerID,
                    bounds: CGRect(x: -5, y: -5, width: 4, height: 4)
                )
            ]
        )

        #expect(document.hasRenderableGeometry)
        #expect(document.drawingBounds == CGRect(x: -5, y: -5, width: 15, height: 10))
    }

    @Test func diagnosticReportStatesRendererConsumesKernelDocument() async throws {
        let url = try makeTemporaryFile(name: "diagnose.dxf", bytes: Array("0\nSECTION\n2\nENTITIES\n".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let report = try await CADKernelDiagnosticReportBuilder.makeReport(
            for: url,
            diagnostics: [
                CADKernelDiagnostic(
                    severity: .warning,
                    code: "TEST_DIAGNOSTIC",
                    message: "测试诊断"
                )
            ],
            importerID: "test-importer"
        )

        #expect(report.contains("Renderer 输入：CADKernelDocument"))
        #expect(report.contains("导入引擎：test-importer"))
        #expect(report.contains("TEST_DIAGNOSTIC"))
    }

    private func makeTemporaryFile(name: String, bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data(bytes).write(to: url, options: .atomic)
        return url
    }
}
