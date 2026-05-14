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
        CADRendererProvider.registerLibreDWGRenderer { fileURL, preferredTextCodePage, preferredTextBigFont, callbacks in
            AnyView(
                LibreDWGBridgePreview(
                    fileURL: fileURL,
                    preferredCodePage: preferredTextCodePage,
                    preferredBigFont: preferredTextBigFont,
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
                                rawTextBytesHexSample: result.rawTextBytesHexSample,
                                detectionSummary: result.detectionSummary,
                                summary: result.summary
                            )
                        )
                    }
                )
            )
        }
        CADRendererProvider.registerLibreDWGTextAutoDetector { fileURL in
            let result = try await Task.detached(priority: .userInitiated) {
                try LibreDWGTextAutoDetector.detect(fileURL: fileURL)
            }.value
            return CADTextAutoDetectionResult(
                codePage: result.codePage,
                bigFont: result.bigFont,
                styleName: result.styleName,
                fontFile: result.fontFile,
                bigFontFile: result.bigFontFile,
                autoDetectScore: result.score,
                styleSummary: result.styleSummary,
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
