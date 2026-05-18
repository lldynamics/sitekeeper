import SwiftUI

struct CADRendererCanvasTransform: Equatable {
    let bounds: CGRect
    let size: CGSize
    let zoomScale: CGFloat
    let panOffset: CGSize
}

struct CADRendererViewState: Equatable {
    let zoomScale: CGFloat
    let panOffset: CGSize
    let viewportCenter: CGPoint?
    let usesSavedVisibleLayers: Bool
    let visibleLayerNames: [String]
}

struct CADRendererFontMapping: Hashable, Sendable {
    let sourceKind: String
    let pattern: String
    let bigFont: Int32
}

struct CADRendererSnapPointPayload: Equatable {
    let point: CGPoint
    let snapKind: String
    let layer: String
    let primitiveKind: String
    let styleRGB: UInt32
    let styleWidth: CGFloat
    let styleName: String?
}

struct CADTextAutoDetectionResult {
    let codePage: Int32?
    let bigFont: Int32?
    let styleName: String?
    let fontFile: String?
    let bigFontFile: String?
    let autoDetectScore: Int
    let styleSummary: String?
    let matchedFontSummary: String?
    let unresolvedFontSummary: String?
    let fontResolutionSummary: String?
    let rawTextBytesHexSample: String?
    let detectionSummary: String?
    let summary: String
}

struct CADOpenQualitySnapshot: Equatable {
    let level: String
    let title: String
    let summary: String
    let primaryAction: String
    let detailLines: [String]
    let allowsMarkup: Bool
    let supportsSearch: Bool

    var isReady: Bool {
        level == "ready"
    }
}

struct CADRendererPerformanceSnapshot: Equatable {
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
    let textOverlaySkippedCount: Int
    let renderMs: Double
    let firstFrameMs: Double
    let totalEntityCount: Int
    let indexedEntityCount: Int
    let viewportEntityCountBeforeLayerFilter: Int
    let layerFilterActive: Bool
    let modelBounds: CGRect?
    let viewportBounds: CGRect?
    let modelBoundsValid: Bool
    let viewportBoundsValid: Bool
    let viewportIntersectsModel: Bool
    let vertexCount: Int
    let totalTextEntityCount: Int
    let indexedTextEntityCount: Int
    let viewportTextEntityCountBeforeLayerFilter: Int
    let visibleTextEntityCount: Int
    let renderInputTextEntityCount: Int
    let textWorldBounds: CGRect?
    let visibleLayerTextWorldBounds: CGRect?
    let nearestTextBounds: CGRect?
    let nearestTextDistance: Double?
    let nearestTextPreview: String?
    let nearestTextLayerID: String?
    let textDiagnosticRows: [String]
    let rendererFailureLayer: String
    let rendererFailureReason: String

    init(
        entityCountInViewport: Int,
        drawCallCount: Int,
        frameTimeMilliseconds: Double,
        skippedEntityCount: Int,
        visibleLayerCount: Int,
        totalLayerCount: Int? = nil,
        simplifiedMode: Bool,
        renderCommandCount: Int? = nil,
        textCommandCount: Int = 0,
        textOverlayCount: Int = 0,
        textOverlaySkippedCount: Int = 0,
        renderMs: Double? = nil,
        firstFrameMs: Double? = nil,
        totalEntityCount: Int? = nil,
        indexedEntityCount: Int? = nil,
        viewportEntityCountBeforeLayerFilter: Int? = nil,
        layerFilterActive: Bool = false,
        modelBounds: CGRect? = nil,
        viewportBounds: CGRect? = nil,
        modelBoundsValid: Bool = true,
        viewportBoundsValid: Bool = true,
        viewportIntersectsModel: Bool = true,
        vertexCount: Int? = nil,
        totalTextEntityCount: Int = 0,
        indexedTextEntityCount: Int = 0,
        viewportTextEntityCountBeforeLayerFilter: Int = 0,
        visibleTextEntityCount: Int = 0,
        renderInputTextEntityCount: Int = 0,
        textWorldBounds: CGRect? = nil,
        visibleLayerTextWorldBounds: CGRect? = nil,
        nearestTextBounds: CGRect? = nil,
        nearestTextDistance: Double? = nil,
        nearestTextPreview: String? = nil,
        nearestTextLayerID: String? = nil,
        textDiagnosticRows: [String] = [],
        rendererFailureLayer: String? = nil,
        rendererFailureReason: String? = nil
    ) {
        let resolvedRenderCommandCount = renderCommandCount ?? drawCallCount
        let resolvedTotalEntityCount = totalEntityCount ?? entityCountInViewport
        let resolvedIndexedEntityCount = indexedEntityCount ?? entityCountInViewport
        let resolvedViewportEntityCountBeforeLayerFilter = viewportEntityCountBeforeLayerFilter ?? entityCountInViewport
        let resolvedTotalLayerCount = totalLayerCount ?? visibleLayerCount
        let resolvedVertexCount = vertexCount ?? drawCallCount
        let classification = Self.classifyFrame(
            totalEntityCount: resolvedTotalEntityCount,
            indexedEntityCount: resolvedIndexedEntityCount,
            viewportEntityCountBeforeLayerFilter: resolvedViewportEntityCountBeforeLayerFilter,
            visibleEntityCount: entityCountInViewport,
            renderCommandCount: resolvedRenderCommandCount,
            drawCallCount: drawCallCount,
            textCommandCount: textCommandCount,
            textOverlayCount: textOverlayCount,
            visibleLayerCount: visibleLayerCount,
            totalLayerCount: resolvedTotalLayerCount,
            layerFilterActive: layerFilterActive,
            modelBoundsValid: modelBoundsValid,
            viewportBoundsValid: viewportBoundsValid,
            viewportIntersectsModel: viewportIntersectsModel,
            vertexCount: resolvedVertexCount,
            totalTextEntityCount: totalTextEntityCount,
            indexedTextEntityCount: indexedTextEntityCount,
            viewportTextEntityCountBeforeLayerFilter: viewportTextEntityCountBeforeLayerFilter,
            visibleTextEntityCount: visibleTextEntityCount,
            renderInputTextEntityCount: renderInputTextEntityCount
        )
        self.entityCountInViewport = entityCountInViewport
        self.drawCallCount = drawCallCount
        self.frameTimeMilliseconds = frameTimeMilliseconds
        self.skippedEntityCount = skippedEntityCount
        self.visibleLayerCount = visibleLayerCount
        self.totalLayerCount = resolvedTotalLayerCount
        self.simplifiedMode = simplifiedMode
        self.renderCommandCount = resolvedRenderCommandCount
        self.textCommandCount = textCommandCount
        self.textOverlayCount = textOverlayCount
        self.textOverlaySkippedCount = textOverlaySkippedCount
        self.renderMs = renderMs ?? frameTimeMilliseconds
        self.firstFrameMs = firstFrameMs ?? frameTimeMilliseconds
        self.totalEntityCount = resolvedTotalEntityCount
        self.indexedEntityCount = resolvedIndexedEntityCount
        self.viewportEntityCountBeforeLayerFilter = resolvedViewportEntityCountBeforeLayerFilter
        self.layerFilterActive = layerFilterActive
        self.modelBounds = modelBounds
        self.viewportBounds = viewportBounds
        self.modelBoundsValid = modelBoundsValid
        self.viewportBoundsValid = viewportBoundsValid
        self.viewportIntersectsModel = viewportIntersectsModel
        self.vertexCount = resolvedVertexCount
        self.totalTextEntityCount = totalTextEntityCount
        self.indexedTextEntityCount = indexedTextEntityCount
        self.viewportTextEntityCountBeforeLayerFilter = viewportTextEntityCountBeforeLayerFilter
        self.visibleTextEntityCount = visibleTextEntityCount
        self.renderInputTextEntityCount = renderInputTextEntityCount
        self.textWorldBounds = textWorldBounds
        self.visibleLayerTextWorldBounds = visibleLayerTextWorldBounds
        self.nearestTextBounds = nearestTextBounds
        self.nearestTextDistance = nearestTextDistance
        self.nearestTextPreview = nearestTextPreview
        self.nearestTextLayerID = nearestTextLayerID
        self.textDiagnosticRows = textDiagnosticRows
        self.rendererFailureLayer = rendererFailureLayer ?? classification.layer
        self.rendererFailureReason = rendererFailureReason ?? classification.reason
    }

    var visibleEntityCount: Int {
        entityCountInViewport
    }

    var hasActionableRendererFailure: Bool {
        rendererFailureLayer != "none"
    }

    var rendererDiagnosticSummary: String {
        switch rendererFailureLayer {
        case "none":
            return "渲染链路正常"
        case "import":
            return "导入层没有可绘制实体"
        case "bounds":
            return "bounds 无效"
        case "layer":
            return "图层过滤后无可见实体"
        case "viewport":
            return "viewport 没有命中图纸范围"
        case "renderCommand":
            return "实体未生成 renderCommand"
        case "textOverlay":
            return "文字命令未生成可见 overlay"
        case "textBounds":
            return "文字 bounds 未进入索引"
        case "textLayer":
            return "文字被图层过滤"
        case "textRenderCommand":
            return "文字实体未生成命令"
        case "metal":
            return "Metal 绘制阶段没有顶点输出"
        default:
            return "渲染诊断未知"
        }
    }

    private static func classifyFrame(
        totalEntityCount: Int,
        indexedEntityCount: Int,
        viewportEntityCountBeforeLayerFilter: Int,
        visibleEntityCount: Int,
        renderCommandCount: Int,
        drawCallCount: Int,
        textCommandCount: Int,
        textOverlayCount: Int,
        visibleLayerCount: Int,
        totalLayerCount: Int,
        layerFilterActive: Bool,
        modelBoundsValid: Bool,
        viewportBoundsValid: Bool,
        viewportIntersectsModel: Bool,
        vertexCount: Int,
        totalTextEntityCount: Int,
        indexedTextEntityCount: Int,
        viewportTextEntityCountBeforeLayerFilter: Int,
        visibleTextEntityCount: Int,
        renderInputTextEntityCount: Int
    ) -> (layer: String, reason: String) {
        if totalEntityCount == 0 {
            return ("import", "Import produced zero renderable entities.")
        }
        if indexedEntityCount == 0 {
            return ("bounds", "No entities entered the spatial index; check entity bounds.")
        }
        if !modelBoundsValid {
            return ("bounds", "Model bounds are empty or non-finite.")
        }
        if !viewportBoundsValid {
            return ("viewport", "Viewport bounds are empty or non-finite.")
        }
        if !viewportIntersectsModel {
            return ("viewport", "Viewport does not intersect model bounds.")
        }
        if totalLayerCount > 0, visibleLayerCount == 0 {
            return ("layer", "All layers are hidden.")
        }
        if layerFilterActive,
           viewportEntityCountBeforeLayerFilter > 0,
           visibleEntityCount == 0 {
            return ("layer", "Viewport has entities before layer filtering, but none remain visible.")
        }
        if visibleEntityCount == 0 {
            return ("viewport", "Spatial index found no entities in the current viewport.")
        }
        if renderCommandCount == 0 {
            return ("renderCommand", "Visible entities did not produce render commands.")
        }
        if totalTextEntityCount > 0, indexedTextEntityCount == 0 {
            return ("textBounds", "Text entities were imported, but none entered the spatial index; check text bounds and insertion points.")
        }
        if viewportTextEntityCountBeforeLayerFilter > 0, visibleTextEntityCount == 0 {
            return ("textLayer", "Viewport contains text before layer filtering, but no text remains visible after layer filtering.")
        }
        if visibleTextEntityCount > 0, renderInputTextEntityCount == 0 {
            return ("textRenderCommand", "Text entities are visible, but text rendering is disabled by the current performance options.")
        }
        if renderInputTextEntityCount > 0, textCommandCount == 0 {
            return ("textRenderCommand", "Text entities are visible, but no text render commands were produced.")
        }
        if textCommandCount > 0, textOverlayCount == 0 {
            return ("textOverlay", "Text render commands exist, but visible text overlays are missing or incomplete.")
        }
        if drawCallCount > 0, vertexCount == 0, textCommandCount == 0 {
            return ("metal", "Render commands exist, but Metal vertex output is empty.")
        }
        return ("none", "Renderer produced visible output.")
    }
}

struct CADRendererCallbacks {
    var onCanvasTransformChange: (CADRendererCanvasTransform) -> Void = { _ in }
    var onViewStateChange: (CADRendererViewState) -> Void = { _ in }
    var onTextRepairPresetRequest: (Int32?, Int32?) -> Void = { _, _ in }
    var onSnapPointsChange: ([CADRendererSnapPointPayload]) -> Void = { _ in }
    var onTextAutoDetectionChange: (CADTextAutoDetectionResult) -> Void = { _ in }
    var onOpenQualityChange: (CADOpenQualitySnapshot) -> Void = { _ in }
    var onOpenTraceChange: (CADPoC.CADOpenTrace) -> Void = { _ in }
    var onPerformanceSample: (CADRendererPerformanceSnapshot) -> Void = { _ in }
    var onFallbackRecommendation: (String) -> Void = { _ in }
}

@MainActor
enum CADRendererProvider {
    typealias RendererBuilder = (URL, Int32?, Int32?, CADRendererViewState?, [CADRendererFontMapping], CADRendererCallbacks) -> AnyView
    typealias TextAutoDetector = (URL, [CADRendererFontMapping]) async throws -> CADTextAutoDetectionResult
    typealias DiagnosticReporter = (URL, Int32?, Int32?) async throws -> String

    private static var rendererBuilder: RendererBuilder?
    private static var textAutoDetector: TextAutoDetector?
    private static var diagnosticReporter: DiagnosticReporter?

    static var isRendererBound: Bool {
        rendererBuilder != nil
    }

    static var isCADRendererBound: Bool {
        isRendererBound
    }

    static func registerRenderer(_ builder: @escaping RendererBuilder) {
        rendererBuilder = builder
    }

    static func registerTextAutoDetector(_ detector: @escaping TextAutoDetector) {
        textAutoDetector = detector
    }

    static func registerDiagnosticReporter(_ reporter: @escaping DiagnosticReporter) {
        diagnosticReporter = reporter
    }

    static func clearRenderer() {
        rendererBuilder = nil
        textAutoDetector = nil
        diagnosticReporter = nil
    }

    static func renderer(
        for fileURL: URL,
        preferredTextCodePage: Int32?,
        preferredTextBigFont: Int32?,
        initialViewState: CADRendererViewState? = nil,
        fontMappings: [CADRendererFontMapping] = [],
        callbacks: CADRendererCallbacks = CADRendererCallbacks()
    ) -> AnyView? {
        rendererBuilder?(fileURL, preferredTextCodePage, preferredTextBigFont, initialViewState, fontMappings, callbacks)
    }

    static func cadRenderer(
        for fileURL: URL,
        preferredTextCodePage: Int32?,
        preferredTextBigFont: Int32?,
        initialViewState: CADRendererViewState? = nil,
        fontMappings: [CADRendererFontMapping] = [],
        callbacks: CADRendererCallbacks = CADRendererCallbacks()
    ) -> AnyView? {
        renderer(
            for: fileURL,
            preferredTextCodePage: preferredTextCodePage,
            preferredTextBigFont: preferredTextBigFont,
            initialViewState: initialViewState,
            fontMappings: fontMappings,
            callbacks: callbacks
        )
    }

    static func detectTextOptions(
        for fileURL: URL,
        fontMappings: [CADRendererFontMapping] = []
    ) async throws -> CADTextAutoDetectionResult? {
        guard let textAutoDetector else { return nil }
        return try await textAutoDetector(fileURL, fontMappings)
    }

    static func makeDiagnosticReport(
        for fileURL: URL,
        preferredTextCodePage: Int32?,
        preferredTextBigFont: Int32?
    ) async throws -> String? {
        guard let diagnosticReporter else { return nil }
        return try await diagnosticReporter(fileURL, preferredTextCodePage, preferredTextBigFont)
    }
}
