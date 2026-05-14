import SwiftUI
#if canImport(LibreDWGBridge)
import LibreDWGBridge
#endif

@MainActor
enum CADRendererBootstrap {
    static func configure() {
        CADRendererProvider.clearLibreDWGRenderer()
        registerLibreDWGRendererIfAvailable()
    }

    private static func registerLibreDWGRendererIfAvailable() {
#if canImport(LibreDWGBridge)
        CADRendererProvider.registerLibreDWGRenderer { fileURL, preferredTextCodePage, preferredTextBigFont, initialViewState, fontMappings, callbacks in
            AnyView(
                LibreDWGBridgePreview(
                    fileURL: fileURL,
                    preferredCodePage: preferredTextCodePage,
                    preferredBigFont: preferredTextBigFont,
                    fontMappings: fontMappings.map {
                        LibreDWGFontMapping(
                            sourceKind: $0.sourceKind,
                            pattern: $0.pattern,
                            bigFont: $0.bigFont
                        )
                    },
                    initialViewState: initialViewState.map {
                        LibreDWGCanvasViewStateSnapshot(
                            zoomScale: $0.zoomScale,
                            panOffset: $0.panOffset,
                            viewportCenter: $0.viewportCenter,
                            usesSavedVisibleLayers: $0.usesSavedVisibleLayers,
                            visibleLayerNames: $0.visibleLayerNames
                        )
                    },
                    onCanvasTransformChange: { transform in
                        callbacks.onCanvasTransformChange(
                            CADRendererCanvasTransform(
                                bounds: transform.bounds,
                                size: transform.size,
                                zoomScale: transform.zoomScale,
                                panOffset: transform.panOffset
                            )
                        )
                    },
                    onViewStateChange: { state in
                        callbacks.onViewStateChange(
                            CADRendererViewState(
                                zoomScale: state.zoomScale,
                                panOffset: state.panOffset,
                                viewportCenter: state.viewportCenter,
                                usesSavedVisibleLayers: state.usesSavedVisibleLayers,
                                visibleLayerNames: state.visibleLayerNames
                            )
                        )
                    },
                    onTextRepairPresetRequest: { codePage, bigFont in
                        callbacks.onTextRepairPresetRequest(codePage, bigFont)
                    },
                    onSnapPointsChange: { points in
                        callbacks.onSnapPointsChange(
                            points.map { point in
                                CADRendererSnapPointPayload(
                                    point: point.point,
                                    snapKind: point.snapKind,
                                    layer: point.layer,
                                    primitiveKind: point.primitiveKind,
                                    styleRGB: point.styleRGB,
                                    styleWidth: point.styleWidth,
                                    styleName: point.styleName
                                )
                            }
                        )
                    },
                    onTextAutoDetectionChange: { result in
                        callbacks.onTextAutoDetectionChange(
                            CADTextAutoDetectionResult(
                                codePage: result.codePage,
                                bigFont: result.bigFont,
                                styleName: result.styleName,
                                fontFile: result.fontFile,
                                bigFontFile: result.bigFontFile,
                                autoDetectScore: result.autoDetectScore,
                                styleSummary: result.styleSummary,
                                matchedFontSummary: result.matchedFontSummary,
                                unresolvedFontSummary: result.unresolvedFontSummary,
                                fontResolutionSummary: result.fontResolutionSummary,
                                rawTextBytesHexSample: result.rawTextBytesHexSample,
                                detectionSummary: result.detectionSummary,
                                summary: result.summary
                            )
                        )
                    }
                )
            )
        }
        CADRendererProvider.registerLibreDWGTextAutoDetector { fileURL, fontMappings in
            let result = try await Task.detached(priority: .userInitiated) {
                try LibreDWGTextAutoDetector.detect(
                    fileURL: fileURL,
                    fontMappings: fontMappings.map {
                        LibreDWGFontMapping(
                            sourceKind: $0.sourceKind,
                            pattern: $0.pattern,
                            bigFont: $0.bigFont
                        )
                    }
                )
            }.value
            return CADTextAutoDetectionResult(
                codePage: result.codePage,
                bigFont: result.bigFont,
                styleName: result.styleName,
                fontFile: result.fontFile,
                bigFontFile: result.bigFontFile,
                autoDetectScore: result.score,
                styleSummary: result.styleSummary,
                matchedFontSummary: result.matchedFontSummary,
                unresolvedFontSummary: result.unresolvedFontSummary,
                fontResolutionSummary: result.fontResolutionSummary,
                rawTextBytesHexSample: result.rawTextBytesHexSample,
                detectionSummary: result.detectionSummary,
                summary: result.summary
            )
        }
        CADRendererProvider.registerLibreDWGDiagnosticReporter { fileURL, preferredTextCodePage, preferredTextBigFont in
            try await Task.detached(priority: .utility) {
                try LibreDWGDiagnosticReportBuilder.makeReport(
                    fileURL: fileURL,
                    preferredCodePage: preferredTextCodePage,
                    preferredBigFont: preferredTextBigFont
                )
            }.value
        }
#endif
    }
}
