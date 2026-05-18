import Foundation
import CoreGraphics

struct CADDiagnosticMachineTrace: Codable {
    struct FileInfo: Codable {
        let displayName: String
        let path: String
        let fileType: String
        let fileByteCount: Int
        let headerHex: String
        let importedAt: String
    }

    struct Environment: Codable {
        let appVersion: String
        let buildNumber: String
        let cadEngineInstalled: Bool
        let rendererBound: Bool
        let viewerMode: String
        let fallbackViewerActive: Bool
        let performanceFallbackActive: Bool
        let performanceFallbackReason: String?
    }

    struct Pipeline: Codable {
        let failureLayer: String
        let failureStage: String
        let openState: String
        let importSource: String?
        let conclusion: String
        let traceSource: String
    }

    struct Counts: Codable {
        let rawEntityCount: Int
        let adapterEntityCount: Int
        let databaseEntityCount: Int
        let drawableEntityCount: Int
        let renderCommandCount: Int
        let visibleLayerCount: Int
    }

    struct Bounds: Codable {
        let minX: Double
        let minY: Double
        let maxX: Double
        let maxY: Double
    }

    struct TextState: Codable {
        let selectedEncoding: String
        let selectedBigFont: String
        let codePageOverride: Int32?
        let bigFontCode: Int32?
        let detectedCodePage: String?
        let detectedStyleName: String?
        let detectedFontFile: String?
        let detectedBigFontFile: String?
        let autoDetectScore: Int?
        let unresolvedFontSummary: String?
        let fontResolutionSummary: String?
        let rawTextBytesHexSample: String?
    }

    struct Performance: Codable {
        let entityCountInViewport: Int
        let drawCallCount: Int
        let frameTimeMilliseconds: Double
        let skippedEntityCount: Int
        let visibleLayerCount: Int
        let totalLayerCount: Int
        let simplifiedMode: Bool
        let renderCommandCount: Int
        let textCommandCount: Int
        let textOverlayCount: Int
        let renderMilliseconds: Double
        let firstFrameMilliseconds: Double
        let totalEntityCount: Int
        let indexedEntityCount: Int
        let viewportEntityCountBeforeLayerFilter: Int
        let layerFilterActive: Bool
        let modelBounds: Bounds?
        let viewportBounds: Bounds?
        let modelBoundsValid: Bool
        let viewportBoundsValid: Bool
        let viewportIntersectsModel: Bool
        let vertexCount: Int
        let totalTextEntityCount: Int
        let indexedTextEntityCount: Int
        let viewportTextEntityCountBeforeLayerFilter: Int
        let visibleTextEntityCount: Int
        let renderInputTextEntityCount: Int
        let rendererFailureLayer: String
        let rendererFailureReason: String
    }

    struct OpenQuality: Codable {
        let level: String
        let title: String
        let summary: String
        let allowsMarkup: Bool
        let supportsSearch: Bool
        let detailLines: [String]
    }

    struct KernelTrace: Codable {
        let fileName: String
        let fileByteCount: Int
        let dwgVersion: String?
        let libreDwgAvailable: Bool
        let dwgreadJsonExitCode: Int?
        let dwgreadDxfExitCode: Int?
        let dwg2dxfExitCode: Int?
        let jsonRawEntityCount: Int
        let dxfRawEntityCount: Int
        let adapterEntityCount: Int
        let databaseEntityCount: Int
        let drawableEntityCount: Int
        let renderCommandCount: Int
        let extents: Bounds?
        let currentLayout: String?
        let visibleLayerCount: Int
        let openState: String
        let failureStage: String
    }

    struct NativeTrace: Codable {
        struct RawEntityCounts: Codable {
            let line: Int
            let polyline: Int
            let circle: Int
            let arc: Int
            let insert: Int
            let ellipse: Int
            let spline: Int
            let filledShape: Int
            let dimension: Int
            let hatch: Int
            let text: Int
            let total: Int
        }

        let fileName: String
        let importSource: String
        let rawEntityCounts: RawEntityCounts
        let expandedInsertEntityCount: Int
        let entityCount: Int
        let drawableEntityCount: Int
        let renderCommandCount: Int
        let bounds: Bounds?
        let openedForRender: Bool
    }

    let schemaVersion: Int
    let traceKind: String
    let generatedAt: String
    let humanReportFile: String
    let machineTraceFile: String
    let file: FileInfo
    let environment: Environment
    let pipeline: Pipeline
    let counts: Counts
    let text: TextState
    let performance: Performance?
    let openQuality: OpenQuality?
    let kernelTrace: KernelTrace?
    let nativeTrace: NativeTrace?
    let diagnostics: [String]
    let runtimeLog: [CADPoC.CADDiagnosticLogEntry]
    let notes: [String]
}

extension CADDiagnosticMachineTrace.Bounds {
    init?(_ bounds: SiteKeeperCADKernel.CADBounds?) {
        guard let bounds, !bounds.isEmpty else { return nil }
        self.init(minX: bounds.minX, minY: bounds.minY, maxX: bounds.maxX, maxY: bounds.maxY)
    }

    init?(_ rect: CGRect?) {
        guard let rect, !rect.isNull, !rect.isEmpty else { return nil }
        self.init(
            minX: Double(rect.minX),
            minY: Double(rect.minY),
            maxX: Double(rect.maxX),
            maxY: Double(rect.maxY)
        )
    }
}

extension CADDiagnosticMachineTrace.KernelTrace {
    init(_ trace: SiteKeeperCADKernel.DWGOpenPipelineTrace) {
        self.init(
            fileName: trace.fileName,
            fileByteCount: trace.fileSize,
            dwgVersion: trace.dwgVersion,
            libreDwgAvailable: trace.libreDwgAvailable,
            dwgreadJsonExitCode: trace.dwgreadJsonExitCode,
            dwgreadDxfExitCode: trace.dwgreadDxfExitCode,
            dwg2dxfExitCode: trace.dwg2dxfExitCode,
            jsonRawEntityCount: trace.jsonRawEntityCount,
            dxfRawEntityCount: trace.dxfRawEntityCount,
            adapterEntityCount: trace.adapterEntityCount,
            databaseEntityCount: trace.databaseEntityCount,
            drawableEntityCount: trace.drawableEntityCount,
            renderCommandCount: trace.renderCommandCount,
            extents: CADDiagnosticMachineTrace.Bounds(trace.extents),
            currentLayout: trace.currentLayout,
            visibleLayerCount: trace.visibleLayerCount,
            openState: trace.openState.rawValue,
            failureStage: trace.failureStage
        )
    }
}

extension CADDiagnosticMachineTrace.NativeTrace {
    init(_ trace: CADPoC.CADOpenTrace) {
        let rawCounts = RawEntityCounts(
            line: trace.rawLineCount,
            polyline: trace.rawPolylineCount,
            circle: trace.rawCircleCount,
            arc: trace.rawArcCount,
            insert: trace.rawInsertCount,
            ellipse: trace.rawEllipseCount,
            spline: trace.rawSplineCount,
            filledShape: trace.rawFilledShapeCount,
            dimension: trace.rawDimensionCount,
            hatch: trace.rawHatchCount,
            text: trace.rawTextCount,
            total: trace.rawLineCount
                + trace.rawPolylineCount
                + trace.rawCircleCount
                + trace.rawArcCount
                + trace.rawInsertCount
                + trace.rawEllipseCount
                + trace.rawSplineCount
                + trace.rawFilledShapeCount
                + trace.rawDimensionCount
                + trace.rawHatchCount
                + trace.rawTextCount
        )
        self.init(
            fileName: trace.fileName,
            importSource: trace.importSource,
            rawEntityCounts: rawCounts,
            expandedInsertEntityCount: trace.expandedInsertEntityCount,
            entityCount: trace.entityCount,
            drawableEntityCount: trace.drawableEntityCount,
            renderCommandCount: trace.renderCommandCount,
            bounds: CADDiagnosticMachineTrace.Bounds(trace.bounds),
            openedForRender: trace.openedForRender
        )
    }
}
