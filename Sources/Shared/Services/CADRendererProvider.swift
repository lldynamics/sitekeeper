import SwiftUI

struct CADTextAutoDetectionResult {
    let codePage: Int32?
    let bigFont: Int32?
    let summary: String
}

@MainActor
enum CADRendererProvider {
    typealias LibreDWGRendererBuilder = (URL, Int32?, Int32?) -> AnyView
    typealias LibreDWGTextAutoDetector = (URL) async throws -> CADTextAutoDetectionResult

    private static var libreDWGRendererBuilder: LibreDWGRendererBuilder?
    private static var libreDWGTextAutoDetector: LibreDWGTextAutoDetector?
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

    static func clearLibreDWGRenderer() {
        libreDWGRendererBuilder = nil
        libreDWGTextAutoDetector = nil
    }

    static func libreDWGRenderer(for fileURL: URL, preferredTextCodePage: Int32?, preferredTextBigFont: Int32?) -> AnyView? {
        ensureConfiguredIfNeeded()
        return libreDWGRendererBuilder?(fileURL, preferredTextCodePage, preferredTextBigFont)
    }

    static func detectLibreDWGTextOptions(for fileURL: URL) async throws -> CADTextAutoDetectionResult? {
        ensureConfiguredIfNeeded()
        guard let libreDWGTextAutoDetector else { return nil }
        return try await libreDWGTextAutoDetector(fileURL)
    }
}
