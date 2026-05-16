import Foundation
import CoreGraphics

struct CADFile: Equatable {
    let id: UUID
    let projectId: UUID
    let drawingId: UUID
    let fileURL: URL
    let displayName: String
    let fileType: String
    let importedAt: String
    let fileSizeBytes: Int
}

struct CADLayer: Equatable, Identifiable {
    let id: String
    let name: String
    let isVisible: Bool
}

struct CADMeasureInput: Equatable {
    let points: [CGPoint]
    let kind: String
}

struct CADMeasureResult: Equatable {
    let value: Double
    let unit: String
}

struct CADTextSearchResult: Equatable, Identifiable {
    let id: String
    let text: String
    let location: CGPoint
}

enum CADOpenState: Equatable {
    case rendered
    case unsupported
    case failed
}

struct CADOpenTechnicalDetails: Equatable {
    let dwgVersion: String?
    let fileSizeBytes: Int?
    let importEngine: String?
    let geometryParsed: Bool
    let drawableEntityCount: Int
    let diagnostics: [String]
    let pipelineTrace: SiteKeeperCADKernel.DWGOpenPipelineTrace?
}

struct CADOpenResult: Equatable {
    let drawingId: UUID
    let openState: CADOpenState
    let message: String
    let technicalDetails: CADOpenTechnicalDetails?

    var supportsOnlineView: Bool {
        openState == .rendered
    }
}

enum CADViewerEngineError: LocalizedError, Equatable {
    case engineNotInstalled
    case featurePending(String)

    var errorDescription: String? {
        switch self {
        case .engineNotInstalled:
            return "CAD engine is not installed"
        case let .featurePending(message):
            return message
        }
    }
}

protocol CADViewerEngine {
    func open(file: CADFile) async throws -> CADOpenResult
    func getLayers() async throws -> [CADLayer]
    func setLayerVisible(_ layerId: String, visible: Bool) async throws
    func measure(_ input: CADMeasureInput) async throws -> CADMeasureResult
    func searchText(_ keyword: String) async throws -> [CADTextSearchResult]
}

struct CADViewerUnavailableEngine: CADViewerEngine {
    func open(file _: CADFile) async throws -> CADOpenResult {
        throw CADViewerEngineError.engineNotInstalled
    }

    func getLayers() async throws -> [CADLayer] {
        throw CADViewerEngineError.engineNotInstalled
    }

    func setLayerVisible(_: String, visible _: Bool) async throws {
        throw CADViewerEngineError.engineNotInstalled
    }

    func measure(_: CADMeasureInput) async throws -> CADMeasureResult {
        throw CADViewerEngineError.engineNotInstalled
    }

    func searchText(_: String) async throws -> [CADTextSearchResult] {
        throw CADViewerEngineError.engineNotInstalled
    }
}

enum CADViewerEngineRegistry {
    private static var engine: CADViewerEngine = CADViewerUnavailableEngine()

    static func configure(engine: CADViewerEngine) {
        self.engine = engine
    }

    static func resetToUnavailable() {
        engine = CADViewerUnavailableEngine()
    }

    static var shared: CADViewerEngine {
        engine
    }

    static var isInstalled: Bool {
        !(engine is CADViewerUnavailableEngine)
    }
}

enum CADOpenRoute: Equatable {
    case online(CADOpenResult)
    case unsupported(CADOpenResult)
}

enum CADViewerMessages {
    static let onlinePreviewUnavailableMessage = "当前图纸暂不支持在线预览，可下载原图查看。"
    static let engineMissingMessage = onlinePreviewUnavailableMessage
    static let dwgDiagnosticImportMessage = onlinePreviewUnavailableMessage
    static let dxfImportEnginePendingMessage = onlinePreviewUnavailableMessage

    static func importEnginePendingMessage(for fileExtension: String) -> String {
        switch fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "dwg":
            return dwgDiagnosticImportMessage
        case "dxf":
            return dxfImportEnginePendingMessage
        default:
            return engineMissingMessage
        }
    }
}

@MainActor
enum CADOpenRouter {
    static let unsupportedOnlineOpenMessage = CADViewerMessages.engineMissingMessage

    static func route(for file: CADFile) async -> CADOpenRoute {
        do {
            let result = try await CADViewerEngineRegistry.shared.open(file: file)
            if result.openState == .rendered {
                return .online(result)
            }
            return .unsupported(result)
        } catch {
            return .unsupported(
                CADOpenResult(
                    drawingId: file.drawingId,
                    openState: .failed,
                    message: unsupportedOnlineOpenMessage,
                    technicalDetails: nil
                )
            )
        }
    }
}
