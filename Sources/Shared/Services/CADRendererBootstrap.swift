import SwiftUI

@MainActor
enum CADRendererBootstrap {
    static func configure() {
        CADRendererProvider.clearRenderer()
        CADRendererProvider.registerTextAutoDetector { _, _ in
            CADTextAutoDetectionResult(
                codePage: nil,
                bigFont: nil,
                styleName: nil,
                fontFile: nil,
                bigFontFile: nil,
                autoDetectScore: 0,
                styleSummary: nil,
                matchedFontSummary: nil,
                unresolvedFontSummary: nil,
                fontResolutionSummary: nil,
                rawTextBytesHexSample: nil,
                detectionSummary: "SiteKeeperCADKernel text engine is active; diagnostic DWG import is available.",
                summary: "自有 CAD 文字引擎已启用，DWG 几何/文字解析接入后会输出 text trace。"
            )
        }
        SiteKeeperCADKernel.CADDWGGeometryAdapterRegistry.register(
            SiteKeeperCADKernel.DWGSidecarJSONGeometryAdapter()
        )
        SiteKeeperCADKernel.CADDWGGeometryAdapterRegistry.register(
            CADRemoteDWGConversionAdapter()
        )
        CADViewerEngineRegistry.configure(engine: SiteKeeperCADKernelAppViewerEngine())
    }
}
