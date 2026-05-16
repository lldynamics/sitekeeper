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
    let simplifiedMode: Bool
    let renderCommandCount: Int
    let textCommandCount: Int
    let textOverlayCount: Int
    let renderMs: Double
    let firstFrameMs: Double

    init(
        entityCountInViewport: Int,
        drawCallCount: Int,
        frameTimeMilliseconds: Double,
        skippedEntityCount: Int,
        visibleLayerCount: Int,
        simplifiedMode: Bool,
        renderCommandCount: Int? = nil,
        textCommandCount: Int = 0,
        textOverlayCount: Int = 0,
        renderMs: Double? = nil,
        firstFrameMs: Double? = nil
    ) {
        self.entityCountInViewport = entityCountInViewport
        self.drawCallCount = drawCallCount
        self.frameTimeMilliseconds = frameTimeMilliseconds
        self.skippedEntityCount = skippedEntityCount
        self.visibleLayerCount = visibleLayerCount
        self.simplifiedMode = simplifiedMode
        self.renderCommandCount = renderCommandCount ?? drawCallCount
        self.textCommandCount = textCommandCount
        self.textOverlayCount = textOverlayCount
        self.renderMs = renderMs ?? frameTimeMilliseconds
        self.firstFrameMs = firstFrameMs ?? frameTimeMilliseconds
    }

    var visibleEntityCount: Int {
        entityCountInViewport
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
