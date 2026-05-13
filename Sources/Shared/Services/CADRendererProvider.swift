import SwiftUI

@MainActor
enum CADRendererProvider {
    typealias LibreDWGRendererBuilder = (URL, Int32?) -> AnyView

    private static var libreDWGRendererBuilder: LibreDWGRendererBuilder?
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

    static func clearLibreDWGRenderer() {
        libreDWGRendererBuilder = nil
    }

    static func libreDWGRenderer(for fileURL: URL, preferredTextCodePage: Int32?) -> AnyView? {
        ensureConfiguredIfNeeded()
        return libreDWGRendererBuilder?(fileURL, preferredTextCodePage)
    }
}
