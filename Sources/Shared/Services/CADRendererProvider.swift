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

struct CADRendererCallbacks {
    var onCanvasTransformChange: (CADRendererCanvasTransform) -> Void = { _ in }
    var onViewStateChange: (CADRendererViewState) -> Void = { _ in }
    var onTextRepairPresetRequest: (Int32?, Int32?) -> Void = { _, _ in }
    var onSnapPointsChange: ([CADRendererSnapPointPayload]) -> Void = { _ in }
    var onTextAutoDetectionChange: (CADTextAutoDetectionResult) -> Void = { _ in }
}

@MainActor
enum CADRendererProvider {
    typealias LibreDWGRendererBuilder = (URL, Int32?, Int32?, CADRendererViewState?, [CADRendererFontMapping], CADRendererCallbacks) -> AnyView
    typealias LibreDWGTextAutoDetector = (URL, [CADRendererFontMapping]) async throws -> CADTextAutoDetectionResult
    typealias LibreDWGDiagnosticReporter = (URL, Int32?, Int32?) async throws -> String

    private static var libreDWGRendererBuilder: LibreDWGRendererBuilder?
    private static var libreDWGTextAutoDetector: LibreDWGTextAutoDetector?
    private static var libreDWGDiagnosticReporter: LibreDWGDiagnosticReporter?
    private static var didAttemptAutoConfigure = false

    private static func ensureConfiguredIfNeeded() {
        guard libreDWGRendererBuilder == nil, !didAttemptAutoConfigure else { return }
        didAttemptAutoConfigure = true
        CADRendererBootstrap.configure()
    }

    static var isLibreDWGRendererBound: Bool {
        ensureConfiguredIfNeeded()
        return libreDWGRendererBuilder != nil
    }

    static func registerLibreDWGRenderer(_ builder: @escaping LibreDWGRendererBuilder) {
        libreDWGRendererBuilder = builder
    }

    static func registerLibreDWGTextAutoDetector(_ detector: @escaping LibreDWGTextAutoDetector) {
        libreDWGTextAutoDetector = detector
    }

    static func registerLibreDWGDiagnosticReporter(_ reporter: @escaping LibreDWGDiagnosticReporter) {
        libreDWGDiagnosticReporter = reporter
    }

    static func clearLibreDWGRenderer() {
        libreDWGRendererBuilder = nil
        libreDWGTextAutoDetector = nil
        libreDWGDiagnosticReporter = nil
    }

    static func libreDWGRenderer(
        for fileURL: URL,
        preferredTextCodePage: Int32?,
        preferredTextBigFont: Int32?,
        initialViewState: CADRendererViewState? = nil,
        fontMappings: [CADRendererFontMapping] = [],
        callbacks: CADRendererCallbacks = CADRendererCallbacks()
    ) -> AnyView? {
        ensureConfiguredIfNeeded()
        return libreDWGRendererBuilder?(fileURL, preferredTextCodePage, preferredTextBigFont, initialViewState, fontMappings, callbacks)
    }

    static func detectLibreDWGTextOptions(
        for fileURL: URL,
        fontMappings: [CADRendererFontMapping] = []
    ) async throws -> CADTextAutoDetectionResult? {
        ensureConfiguredIfNeeded()
        guard let libreDWGTextAutoDetector else { return nil }
        return try await libreDWGTextAutoDetector(fileURL, fontMappings)
    }

    static func makeLibreDWGDiagnosticReport(
        for fileURL: URL,
        preferredTextCodePage: Int32?,
        preferredTextBigFont: Int32?
    ) async throws -> String? {
        ensureConfiguredIfNeeded()
        guard let libreDWGDiagnosticReporter else { return nil }
        return try await libreDWGDiagnosticReporter(fileURL, preferredTextCodePage, preferredTextBigFont)
    }
}
