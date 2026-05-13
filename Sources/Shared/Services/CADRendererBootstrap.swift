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
        CADRendererProvider.registerLibreDWGRenderer { fileURL, preferredTextCodePage in
            AnyView(LibreDWGBridgePreview(fileURL: fileURL, preferredCodePage: preferredTextCodePage))
        }
#endif
    }
}
