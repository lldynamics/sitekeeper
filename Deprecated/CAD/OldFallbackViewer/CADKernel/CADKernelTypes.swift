import CoreGraphics
import Foundation

enum CADKernelFileFormat: String, Codable, CaseIterable {
    case dwg
    case dxf
    case pdf
    case unknown

    init(fileExtension: String) {
        switch fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "dwg":
            self = .dwg
        case "dxf":
            self = .dxf
        case "pdf":
            self = .pdf
        default:
            self = .unknown
        }
    }

    var displayName: String {
        switch self {
        case .dwg:
            return "DWG"
        case .dxf:
            return "DXF"
        case .pdf:
            return "PDF"
        case .unknown:
            return "未知"
        }
    }
}

enum CADKernelDiagnosticSeverity: String, Codable, CaseIterable {
    case info
    case warning
    case error
    case blocker

    var sortRank: Int {
        switch self {
        case .blocker: return 0
        case .error: return 1
        case .warning: return 2
        case .info: return 3
        }
    }
}

struct CADKernelDiagnostic: Identifiable, Codable, Equatable {
    var id: String
    var severity: CADKernelDiagnosticSeverity
    var code: String
    var message: String
    var detail: String
    var source: String

    init(
        id: String = UUID().uuidString,
        severity: CADKernelDiagnosticSeverity,
        code: String,
        message: String,
        detail: String = "",
        source: String = "CADKernel"
    ) {
        self.id = id
        self.severity = severity
        self.code = code
        self.message = message
        self.detail = detail
        self.source = source
    }
}

struct CADKernelMetadata: Codable, Equatable {
    var sourceFileName: String
    var sourceFormat: CADKernelFileFormat
    var dwgVersion: String?
    var declaredCodePage: String?
    var units: String?
    var importerID: String
    var importedAt: Date

    init(
        sourceFileName: String,
        sourceFormat: CADKernelFileFormat,
        dwgVersion: String? = nil,
        declaredCodePage: String? = nil,
        units: String? = nil,
        importerID: String,
        importedAt: Date = Date()
    ) {
        self.sourceFileName = sourceFileName
        self.sourceFormat = sourceFormat
        self.dwgVersion = dwgVersion
        self.declaredCodePage = declaredCodePage
        self.units = units
        self.importerID = importerID
        self.importedAt = importedAt
    }
}

struct CADKernelLayer: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var isVisible: Bool
    var colorRGB: UInt32?
    var lineWeight: Double?

    init(
        id: String,
        name: String,
        isVisible: Bool = true,
        colorRGB: UInt32? = nil,
        lineWeight: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.colorRGB = colorRGB
        self.lineWeight = lineWeight
    }
}

struct CADKernelLayout: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var bounds: CGRect
    var isModelSpace: Bool

    init(id: String, name: String, bounds: CGRect = .null, isModelSpace: Bool = true) {
        self.id = id
        self.name = name
        self.bounds = bounds
        self.isModelSpace = isModelSpace
    }
}

enum CADKernelEntityKind: String, Codable, CaseIterable {
    case line
    case polyline
    case circle
    case arc
    case text
    case hatch
    case imageReference
    case blockReference
    case unsupported
}

struct CADKernelEntity: Identifiable, Codable, Equatable {
    var id: String
    var kind: CADKernelEntityKind
    var layerID: String
    var layoutID: String
    var bounds: CGRect
    var points: [CGPoint]
    var radius: Double?
    var text: String?
    var styleName: String?
    var colorRGB: UInt32?
    var lineWeight: Double?
    var diagnostics: [CADKernelDiagnostic]

    init(
        id: String = UUID().uuidString,
        kind: CADKernelEntityKind,
        layerID: String,
        layoutID: String = CADKernelDocument.modelSpaceLayoutID,
        bounds: CGRect = .null,
        points: [CGPoint] = [],
        radius: Double? = nil,
        text: String? = nil,
        styleName: String? = nil,
        colorRGB: UInt32? = nil,
        lineWeight: Double? = nil,
        diagnostics: [CADKernelDiagnostic] = []
    ) {
        self.id = id
        self.kind = kind
        self.layerID = layerID
        self.layoutID = layoutID
        self.bounds = bounds
        self.points = points
        self.radius = radius
        self.text = text
        self.styleName = styleName
        self.colorRGB = colorRGB
        self.lineWeight = lineWeight
        self.diagnostics = diagnostics
    }
}

struct CADKernelDocument: Codable, Equatable {
    static let modelSpaceLayoutID = "model"
    static let defaultLayerID = "0"

    var metadata: CADKernelMetadata
    var layouts: [CADKernelLayout]
    var layers: [CADKernelLayer]
    var entities: [CADKernelEntity]
    var diagnostics: [CADKernelDiagnostic]

    init(
        metadata: CADKernelMetadata,
        layouts: [CADKernelLayout] = [CADKernelLayout(id: "model", name: "Model")],
        layers: [CADKernelLayer] = [CADKernelLayer(id: "0", name: "0")],
        entities: [CADKernelEntity] = [],
        diagnostics: [CADKernelDiagnostic] = []
    ) {
        self.metadata = metadata
        self.layouts = layouts
        self.layers = layers
        self.entities = entities
        self.diagnostics = diagnostics
    }

    var hasRenderableGeometry: Bool {
        entities.contains { $0.kind != .unsupported }
    }

    var blockingDiagnostics: [CADKernelDiagnostic] {
        diagnostics.filter { $0.severity == .blocker }
    }

    var drawingBounds: CGRect {
        let entityBounds = entities
            .map(\.bounds)
            .filter { !$0.isNull && !$0.isInfinite && !$0.isEmpty }
        guard let first = entityBounds.first else { return .null }
        return entityBounds.dropFirst().reduce(first) { $0.union($1) }
    }

    var visibleLayers: [CADKernelLayer] {
        layers.filter(\.isVisible)
    }
}
