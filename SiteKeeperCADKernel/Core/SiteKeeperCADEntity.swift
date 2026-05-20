import Foundation

extension SiteKeeperCADKernel {
    enum CADEntityKind: String, Equatable, Codable, CaseIterable {
        case line
        case point
        case polyline
        case lwPolyline
        case circle
        case arc
        case ellipse
        case spline
        case text
        case mtext
        case insert
        case attrib
        case hatch
        case dimension
        case image
        case table
        case xref
        case proxy
        case unsupported
        case blockReference
    }

    enum CADVisibility: String, Equatable, Codable {
        case visible
        case hidden
    }

    struct CADTextRun: Equatable, Codable {
        var rawText: String
        var decodedText: String
        var normalizedText: String
        var displayText: String
        var styleName: String
        var fontFile: String?
        var bigFontFile: String?
        var selectedFontName: String
        var fontWasAvailable: Bool
        var fallbackReason: String?
        var decodeMethod: String
        var warnings: [String]
        var insertionPoint: CADPoint
        var textStyleId: String
        var height: Double
        var rotationRadians: Double
        var widthFactor: Double?
        var boxWidth: Double?
        var boxHeight: Double?
        var horizontalAlignmentCode: Int?
        var verticalAlignmentCode: Int?
        var attributeTag: String?
        var rawTextBytesHex: String?

        init(
            rawText: String,
            decodedText: String? = nil,
            normalizedText: String? = nil,
            displayText: String? = nil,
            styleName: String = CADTextStyle.default.name,
            fontFile: String? = nil,
            bigFontFile: String? = nil,
            selectedFontName: String = "System",
            fontWasAvailable: Bool = true,
            fallbackReason: String? = nil,
            decodeMethod: String = "rawString",
            warnings: [String] = [],
            insertionPoint: CADPoint,
            textStyleId: String = CADTextStyle.default.id,
            height: Double = 2.5,
            rotationRadians: Double = 0,
            widthFactor: Double? = nil,
            boxWidth: Double? = nil,
            boxHeight: Double? = nil,
            horizontalAlignmentCode: Int? = nil,
            verticalAlignmentCode: Int? = nil,
            attributeTag: String? = nil,
            rawTextBytesHex: String? = nil
        ) {
            self.rawText = rawText
            self.decodedText = decodedText ?? rawText
            self.normalizedText = normalizedText ?? displayText ?? decodedText ?? rawText
            self.displayText = displayText ?? normalizedText ?? decodedText ?? rawText
            self.styleName = styleName
            self.fontFile = fontFile
            self.bigFontFile = bigFontFile
            self.selectedFontName = selectedFontName
            self.fontWasAvailable = fontWasAvailable
            self.fallbackReason = fallbackReason
            self.decodeMethod = decodeMethod
            self.warnings = warnings
            self.insertionPoint = insertionPoint
            self.textStyleId = textStyleId
            self.height = height
            self.rotationRadians = rotationRadians
            self.widthFactor = widthFactor
            self.boxWidth = boxWidth
            self.boxHeight = boxHeight
            self.horizontalAlignmentCode = horizontalAlignmentCode
            self.verticalAlignmentCode = verticalAlignmentCode
            self.attributeTag = attributeTag
            self.rawTextBytesHex = rawTextBytesHex
        }

        var styleID: String {
            get { textStyleId }
            set { textStyleId = newValue }
        }

        func makeTrace(entityId: String, entityType: CADEntityKind) -> CADTextTrace {
            CADTextTrace(
                entityId: entityId,
                entityType: entityType.rawValue,
                rawText: rawText,
                decodedText: decodedText,
                normalizedText: normalizedText,
                displayText: displayText,
                textStyleName: styleName,
                fontFile: fontFile,
                bigFontFile: bigFontFile,
                selectedFontName: selectedFontName,
                fontWasAvailable: fontWasAvailable,
                fallbackReason: fallbackReason,
                attributeTag: attributeTag,
                rawTextBytesHex: rawTextBytesHex,
                warnings: warnings
            )
        }
    }

    struct CADEntity: Identifiable, Equatable, Codable {
        var id: UUID
        var type: CADEntityKind
        var layerId: String
        var layoutId: String
        var color: UInt32
        var lineType: String
        var lineWeight: Double
        var bounds: CADBounds
        var transform: CADTransform
        var visibility: CADVisibility
        var sourceHandle: String?
        var diagnostics: CADDrawingDiagnostics
        var path: CADPath?
        var text: CADTextRun?
        var blockName: String?
        var unsupportedReason: String?

        init(
            id: UUID = UUID(),
            kind: CADEntityKind,
            layerID: String = CADLayer.default.id,
            layoutID: String = CADLayout.modelSpace.id,
            color: UInt32 = 0x00000000,
            lineType: String = "ByLayer",
            lineWeight: Double = -1,
            path: CADPath? = nil,
            text: CADTextRun? = nil,
            blockName: String? = nil,
            transform: CADTransform = .identity,
            bounds: CADBounds = .empty,
            visibility: CADVisibility = .visible,
            sourceHandle: String? = nil,
            diagnostics: CADDrawingDiagnostics = CADDrawingDiagnostics(),
            unsupportedReason: String? = nil
        ) {
            self.id = id
            self.type = kind
            self.layerId = layerID
            self.layoutId = layoutID
            self.color = color
            self.lineType = lineType
            self.lineWeight = lineWeight
            self.bounds = bounds
            self.transform = transform
            self.visibility = visibility
            self.sourceHandle = sourceHandle
            self.diagnostics = diagnostics
            self.path = path
            self.text = text
            self.blockName = blockName
            self.unsupportedReason = unsupportedReason
        }

        var kind: CADEntityKind {
            get { type }
            set { type = newValue }
        }

        var layerID: String {
            get { layerId }
            set { layerId = newValue }
        }

        var layoutID: String {
            get { layoutId }
            set { layoutId = newValue }
        }

        var rawText: String? {
            text?.rawText
        }

        var displayText: String? {
            text?.displayText
        }

        var textStyleId: String? {
            text?.textStyleId
        }

        var isRenderable: Bool {
            guard visibility == .visible else { return false }
            switch type {
            case .line, .point, .polyline, .lwPolyline, .circle, .arc, .ellipse, .spline, .text, .mtext, .insert, .attrib, .hatch, .dimension, .image, .table, .blockReference:
                return path != nil || text != nil || blockName != nil
            case .xref, .proxy, .unsupported:
                return false
            }
        }
    }
}
