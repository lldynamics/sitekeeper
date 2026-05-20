import Foundation

extension SiteKeeperCADKernel {
    protocol CADExternalSDKAdapter {
        var id: String { get }

        func canImport(file: CADFile) -> Bool
        func importDrawing(file: CADFile) async throws -> CADExternalSDKDrawing
    }

    struct ExternalCADSDKImportEngine: CADImportEngine {
        let id = "sitekeeper.external-cad-sdk"
        private let adapter: (any CADExternalSDKAdapter)?

        init(adapter: (any CADExternalSDKAdapter)? = nil) {
            self.adapter = adapter
        }

        func canImport(file: CADFile) -> Bool {
            adapter?.canImport(file: file) ?? false
        }

        func importDrawing(file: CADFile) async throws -> CADDatabase {
            guard let adapter else {
                throw CADImportError.importerNotReady("External CAD SDK adapter is not installed")
            }
            guard adapter.canImport(file: file) else {
                throw CADImportError.unsupportedFormat(file.format)
            }
            let drawing = try await adapter.importDrawing(file: file)
            return drawing.makeDatabase(file: file, adapterID: adapter.id)
        }
    }

    struct CADExternalSDKDrawing: Equatable, Codable {
        var units: CADUnits
        var extents: CADBounds
        var layers: [CADLayer]
        var layouts: [CADLayout]
        var entities: [CADExternalSDKEntity]
        var blocks: [CADExternalSDKBlock]
        var textStyles: [CADTextStyle]
        var xrefs: [CADXref]
        var renderSnapshot: CADExternalSDKRenderSnapshot?
        var diagnostics: CADDrawingDiagnostics
        var performanceTrace: CADPerformanceTrace?
        var textTrace: [CADTextTrace]

        init(
            units: CADUnits = .unitless,
            extents: CADBounds = .empty,
            layers: [CADLayer] = [.default],
            layouts: [CADLayout] = [.modelSpace],
            entities: [CADExternalSDKEntity] = [],
            blocks: [CADExternalSDKBlock] = [],
            textStyles: [CADTextStyle] = [.default],
            xrefs: [CADXref] = [],
            renderSnapshot: CADExternalSDKRenderSnapshot? = nil,
            diagnostics: CADDrawingDiagnostics = CADDrawingDiagnostics(),
            performanceTrace: CADPerformanceTrace? = nil,
            textTrace: [CADTextTrace] = []
        ) {
            self.units = units
            self.extents = extents
            self.layers = layers
            self.layouts = layouts
            self.entities = entities
            self.blocks = blocks
            self.textStyles = textStyles
            self.xrefs = xrefs
            self.renderSnapshot = renderSnapshot
            self.diagnostics = diagnostics
            self.performanceTrace = performanceTrace
            self.textTrace = textTrace
        }

        func makeDatabase(file: CADFile, adapterID: String) -> CADDatabase {
            let convertedEntities = entities.map { $0.makeEntity() }
            let convertedBlocks = blocks.map { $0.makeBlock() }
            var database = CADDatabase(
                file: file,
                units: units,
                extents: extents,
                layers: layers.isEmpty ? [.default] : layers,
                layouts: layouts.isEmpty ? [.modelSpace] : layouts,
                blocks: convertedBlocks,
                entities: convertedEntities,
                textStyles: textStyles.isEmpty ? [.default] : textStyles,
                xrefs: xrefs,
                diagnostics: diagnostics
            )
            database.diagnostics.append(
                CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_EXTERNAL_ADAPTER_USED",
                    message: "External CAD adapter imported drawing into CADDatabase.",
                    detail: adapterID
                )
            )

            if let renderSnapshot {
                database.diagnostics.append(
                    CADDrawingDiagnostics.Entry(
                        severity: .info,
                        code: "CAD_EXTERNAL_RENDER_SNAPSHOT_AVAILABLE",
                        message: "External CAD adapter supplied a render snapshot.",
                        detail: renderSnapshot.snapshotID
                    )
                )
                if database.entities.isEmpty {
                    database.append(renderSnapshot.makeImagePlaceholderEntity())
                }
            }

            let parsedGeometry = database.entities.contains { !CADDatabase.isPlaceholderEntity($0) }
            database.setImportMetadata(
                geometryParsed: parsedGeometry,
                importSource: adapterID
            )
            database.textTrace = textTrace.isEmpty
                ? database.entities.compactMap { entity in
                    guard let text = entity.text else { return nil }
                    return text.makeTrace(entityId: entity.id.uuidString, entityType: entity.kind)
                }
                : textTrace
            if let performanceTrace {
                database.performanceTrace = performanceTrace
            } else {
                database.performanceTrace = CADPerformanceTrace(
                    fileSizeBytes: file.byteCount ?? 0,
                    entityCount: database.entityCount,
                    visibleEntityCount: database.drawableEntityCount,
                    renderCommandCount: 0,
                    drawCallCount: 0,
                    spatialIndexBuildMs: 0,
                    resolveMs: 0,
                    renderMs: 0,
                    firstFrameMs: 0,
                    peakMemoryMB: 0,
                    skippedEntityCount: database.placeholderEntityCount,
                    warnings: database.importWarnings
                )
            }

            return database
        }
    }

    struct CADExternalSDKBlock: Equatable, Codable {
        var id: String
        var name: String
        var basePoint: CADPoint
        var entities: [CADExternalSDKEntity]
        var bounds: CADBounds
        var sourceHandle: String?

        init(
            id: String? = nil,
            name: String,
            basePoint: CADPoint = .zero,
            entities: [CADExternalSDKEntity] = [],
            bounds: CADBounds = .empty,
            sourceHandle: String? = nil
        ) {
            self.id = id ?? name
            self.name = name
            self.basePoint = basePoint
            self.entities = entities
            self.bounds = bounds
            self.sourceHandle = sourceHandle
        }

        func makeBlock() -> CADBlock {
            let converted = entities.map { $0.makeEntity() }
            let resolvedBounds = bounds.isEmpty
                ? converted.reduce(CADBounds.empty) { $0.union($1.bounds) }
                : bounds
            return CADBlock(
                id: id,
                name: name,
                basePoint: basePoint,
                entities: converted,
                bounds: resolvedBounds,
                sourceHandle: sourceHandle
            )
        }
    }

    struct CADExternalSDKEntity: Equatable, Codable {
        var type: CADEntityKind
        var layerId: String
        var layoutId: String
        var color: UInt32
        var lineType: String
        var lineWeight: Double
        var geometry: CADExternalSDKGeometry?
        var text: CADExternalSDKText?
        var blockName: String?
        var visibility: CADVisibility
        var sourceHandle: String?
        var diagnostics: CADDrawingDiagnostics
        var unsupportedReason: String?

        init(
            type: CADEntityKind,
            layerId: String = CADLayer.default.id,
            layoutId: String = CADLayout.modelSpace.id,
            color: UInt32 = 0x00000000,
            lineType: String = "ByLayer",
            lineWeight: Double = -1,
            geometry: CADExternalSDKGeometry? = nil,
            text: CADExternalSDKText? = nil,
            blockName: String? = nil,
            visibility: CADVisibility = .visible,
            sourceHandle: String? = nil,
            diagnostics: CADDrawingDiagnostics = CADDrawingDiagnostics(),
            unsupportedReason: String? = nil
        ) {
            self.type = type
            self.layerId = layerId
            self.layoutId = layoutId
            self.color = color
            self.lineType = lineType
            self.lineWeight = lineWeight
            self.geometry = geometry
            self.text = text
            self.blockName = blockName
            self.visibility = visibility
            self.sourceHandle = sourceHandle
            self.diagnostics = diagnostics
            self.unsupportedReason = unsupportedReason
        }

        func makeEntity() -> CADEntity {
            CADEntity(
                kind: type,
                layerID: layerId,
                layoutID: layoutId,
                color: color,
                lineType: lineType,
                lineWeight: lineWeight,
                path: geometry?.path,
                text: text?.makeTextRun(),
                blockName: blockName,
                bounds: geometry?.bounds ?? text?.bounds ?? .empty,
                visibility: visibility,
                sourceHandle: sourceHandle,
                diagnostics: diagnostics,
                unsupportedReason: unsupportedReason
            )
        }
    }

    enum CADExternalSDKGeometry: Equatable, Codable {
        case path(CADPath)
        case circle(center: CADPoint, radius: Double)
        case arc(center: CADPoint, radius: Double, startAngleRadians: Double, endAngleRadians: Double)
        case ellipse(center: CADPoint, radiusX: Double, radiusY: Double, rotationRadians: Double)
        case bounds(CADBounds)

        var path: CADPath? {
            if case let .path(path) = self {
                return path
            }
            return nil
        }

        var bounds: CADBounds {
            switch self {
            case let .path(path):
                return path.bounds
            case let .circle(center, radius):
                return CADBounds(
                    minX: center.x - radius,
                    minY: center.y - radius,
                    maxX: center.x + radius,
                    maxY: center.y + radius
                )
            case let .arc(center, radius, _, _):
                return CADBounds(
                    minX: center.x - radius,
                    minY: center.y - radius,
                    maxX: center.x + radius,
                    maxY: center.y + radius
                )
            case let .ellipse(center, radiusX, radiusY, _):
                return CADBounds(
                    minX: center.x - radiusX,
                    minY: center.y - radiusY,
                    maxX: center.x + radiusX,
                    maxY: center.y + radiusY
                )
            case let .bounds(bounds):
                return bounds
            }
        }
    }

    struct CADExternalSDKText: Equatable, Codable {
        var rawText: String
        var decodedText: String?
        var normalizedText: String?
        var displayText: String?
        var styleName: String
        var fontFile: String?
        var bigFontFile: String?
        var selectedFontName: String
        var decodeMethod: String
        var warnings: [String]
        var insertionPoint: CADPoint
        var textStyleId: String
        var height: Double
        var rotationRadians: Double

        init(
            rawText: String,
            decodedText: String? = nil,
            normalizedText: String? = nil,
            displayText: String? = nil,
            styleName: String = CADTextStyle.default.name,
            fontFile: String? = nil,
            bigFontFile: String? = nil,
            selectedFontName: String = "System",
            decodeMethod: String = "externalSDK",
            warnings: [String] = [],
            insertionPoint: CADPoint,
            textStyleId: String = CADTextStyle.default.id,
            height: Double = 2.5,
            rotationRadians: Double = 0
        ) {
            self.rawText = rawText
            self.decodedText = decodedText
            self.normalizedText = normalizedText
            self.displayText = displayText
            self.styleName = styleName
            self.fontFile = fontFile
            self.bigFontFile = bigFontFile
            self.selectedFontName = selectedFontName
            self.decodeMethod = decodeMethod
            self.warnings = warnings
            self.insertionPoint = insertionPoint
            self.textStyleId = textStyleId
            self.height = height
            self.rotationRadians = rotationRadians
        }

        var bounds: CADBounds {
            CADBounds(
                minX: insertionPoint.x,
                minY: insertionPoint.y,
                maxX: insertionPoint.x,
                maxY: insertionPoint.y
            )
        }

        func makeTextRun() -> CADTextRun {
            CADTextRun(
                rawText: rawText,
                decodedText: decodedText,
                normalizedText: normalizedText,
                displayText: displayText,
                styleName: styleName,
                fontFile: fontFile,
                bigFontFile: bigFontFile,
                selectedFontName: selectedFontName,
                decodeMethod: decodeMethod,
                warnings: warnings,
                insertionPoint: insertionPoint,
                textStyleId: textStyleId,
                height: height,
                rotationRadians: rotationRadians
            )
        }
    }

    struct CADExternalSDKRenderSnapshot: Equatable, Codable {
        var snapshotID: String
        var bounds: CADBounds
        var pixelWidth: Int
        var pixelHeight: Int
        var mimeType: String
        var byteCount: Int?

        init(
            snapshotID: String = UUID().uuidString,
            bounds: CADBounds,
            pixelWidth: Int,
            pixelHeight: Int,
            mimeType: String = "image/png",
            byteCount: Int? = nil
        ) {
            self.snapshotID = snapshotID
            self.bounds = bounds
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.mimeType = mimeType
            self.byteCount = byteCount
        }

        func makeImagePlaceholderEntity() -> CADEntity {
            CADEntity(
                kind: .image,
                layerID: CADLayer.default.id,
                bounds: bounds,
                sourceHandle: snapshotID,
                diagnostics: CADDrawingDiagnostics(entries: [
                    CADDrawingDiagnostics.Entry(
                        severity: .info,
                        code: "CAD_EXTERNAL_RENDER_SNAPSHOT_PLACEHOLDER",
                        message: "External adapter supplied a render snapshot placeholder.",
                        detail: "\(pixelWidth)x\(pixelHeight) \(mimeType)"
                    )
                ]),
                unsupportedReason: "External render snapshot placeholder"
            )
        }
    }
}
