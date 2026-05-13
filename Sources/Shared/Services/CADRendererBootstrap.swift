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
        CADRendererProvider.registerLibreDWGRenderer { fileURL, preferredTextCodePage, preferredTextBigFont in
            AnyView(
                LibreDWGBridgePreview(
                    fileURL: fileURL,
                    preferredCodePage: preferredTextCodePage,
                    preferredBigFont: preferredTextBigFont
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
                summary: result.summary
            )
        }
#endif
    }
}
