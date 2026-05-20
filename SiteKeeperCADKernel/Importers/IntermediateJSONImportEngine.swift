import Foundation

extension SiteKeeperCADKernel {
    struct IntermediateJSONImportEngine: CADImportEngine {
        let id = "sitekeeper.intermediate-json"
        let supportedFormats: Set<CADFileFormat> = [.intermediateJSON]

        func canImport(file: CADFile) -> Bool {
            supportedFormats.contains(file.format)
        }

        func importDrawing(file: CADFile) async throws -> CADDatabase {
            do {
                let data = try Data(contentsOf: file.url)
                if var database = try? JSONDecoder().decode(CADDatabase.self, from: data) {
                    database.sourceFile = file
                    database.setImportMetadata(
                        geometryParsed: database.geometryParsed || database.drawableEntityCount > 0,
                        importSource: id
                    )
                    return database
                }
                let payload = try JSONDecoder().decode(IntermediateJSONPayload.self, from: data)
                var database = CADDatabase(
                    id: payload.drawingId.flatMap(UUID.init(uuidString:)) ?? UUID(),
                    file: file,
                    units: payload.units ?? .unitless,
                    extents: payload.extents ?? .empty,
                    layers: payload.layers.map {
                        CADLayer(
                            id: $0.id,
                            name: $0.name,
                            isVisible: $0.isVisible ?? true,
                            isLocked: $0.isLocked ?? false,
                            colorARGB: $0.colorARGB ?? 0xFF2F3437,
                            lineWeight: $0.lineWeight ?? 0.25
                        )
                    },
                    layouts: payload.layouts?.map {
                        CADLayout(
                            id: $0.id,
                            name: $0.name,
                            isModelSpace: $0.isModelSpace,
                            paperBounds: $0.paperBounds ?? .empty,
                            viewportIDs: $0.viewportIDs ?? []
                        )
                    } ?? [.modelSpace],
                    blocks: payload.blocks?.map { $0.makeBlock() } ?? [],
                    textStyles: payload.textStyles?.map {
                        CADTextStyle(
                            id: $0.id,
                            name: $0.name,
                            fontName: $0.fontName,
                            bigFontName: $0.bigFontName,
                            fixedHeight: $0.fixedHeight,
                            widthFactor: $0.widthFactor ?? 1,
                            obliqueAngleRadians: $0.obliqueAngleRadians ?? 0
                        )
                    } ?? [.default],
                    xrefs: payload.xrefs ?? []
                )
                payload.entities.forEach { item in
                    database.append(item.makeEntity())
                }
                if let diagnostics = payload.diagnostics {
                    database.diagnostics = database.diagnostics.merging(diagnostics)
                }
                if let performanceTrace = payload.performanceTrace {
                    database.performanceTrace = performanceTrace
                }
                if let textTrace = payload.textTrace {
                    database.textTrace = textTrace
                }
                let hasDrawableGeometry = database.drawableEntityCount > 0
                database.setImportMetadata(
                    geometryParsed: payload.geometryParsed ?? hasDrawableGeometry,
                    isMetadataOnly: payload.isMetadataOnly ?? !hasDrawableGeometry,
                    importSource: payload.importSource ?? id,
                    importWarnings: payload.importWarnings ?? database.importWarnings
                )
                return database
            } catch let error as CADImportError {
                throw error
            } catch {
                throw CADImportError.invalidIntermediateJSON
            }
        }
    }

    struct IntermediateJSONPayload: Decodable {
        var schema: String?
        var drawingId: String?
        var importSource: String?
        var geometryParsed: Bool?
        var isMetadataOnly: Bool?
        var diagnostics: CADDrawingDiagnostics?
        var performanceTrace: CADPerformanceTrace?
        var textTrace: [CADTextTrace]?
        var importWarnings: [String]?

        struct Layer: Decodable {
            var id: String
            var name: String
            var isVisible: Bool?
            var isLocked: Bool?
            var colorARGB: UInt32?
            var lineWeight: Double?
        }

        struct Layout: Decodable {
            var id: String
            var name: String
            var isModelSpace: Bool
            var paperBounds: CADBounds?
            var viewportIDs: [String]?
        }

        struct Block: Decodable {
            var id: String?
            var name: String
            var basePoint: CADPoint?
            var entities: [Entity]?
            var bounds: CADBounds?
            var sourceHandle: String?

            func makeBlock() -> CADBlock {
                let blockEntities = (entities ?? []).map { $0.makeEntity() }
                let resolvedBounds = bounds ?? blockEntities.reduce(CADBounds.empty) { $0.union($1.bounds) }
                return CADBlock(
                    id: id ?? name,
                    name: name,
                    basePoint: basePoint ?? .zero,
                    entities: blockEntities,
                    bounds: resolvedBounds,
                    sourceHandle: sourceHandle
                )
            }
        }

        struct Entity: Decodable {
            var id: String?
            var handle: String?
            var sourceHandle: String?
            var layerID: String?
            var layerId: String?
            var layoutID: String?
            var layoutId: String?
            var type: CADEntityKind?
            var start: CADPoint?
            var end: CADPoint?
            var points: [CADPoint]?
            var isClosed: Bool?
            var center: CADPoint?
            var radius: Double?
            var insertionPoint: CADPoint?
            var transform: CADTransform?
            var scale: Double?
            var scaleX: Double?
            var scaleY: Double?
            var rotationRadians: Double?
            var rotationDegrees: Double?
            var rawText: String?
            var displayText: String?
            var textStyleId: String?
            var textStyleName: String?
            var blockName: String?
            var color: UInt32?
            var lineType: String?
            var lineWeight: Double?
            var bounds: CADBounds?
            var visibility: CADVisibility?
            var diagnostics: CADDrawingDiagnostics?
            var unsupportedReason: String?

            enum CodingKeys: String, CodingKey {
                case id
                case handle
                case sourceHandle
                case layerID
                case layerId
                case layoutID
                case layoutId
                case type
                case entityType
                case start
                case end
                case points
                case isClosed
                case center
                case radius
                case insertionPoint
                case transform
                case scale
                case scaleX
                case scaleY
                case rotationRadians
                case rotationDegrees
                case rawText
                case displayText
                case textStyleId
                case textStyleName
                case blockName
                case color
                case lineType
                case lineWeight
                case bounds
                case visibility
                case diagnostics
                case unsupportedReason
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decodeIfPresent(String.self, forKey: .id)
                handle = try container.decodeIfPresent(String.self, forKey: .handle)
                sourceHandle = try container.decodeIfPresent(String.self, forKey: .sourceHandle)
                layerID = try container.decodeIfPresent(String.self, forKey: .layerID)
                layerId = try container.decodeIfPresent(String.self, forKey: .layerId)
                layoutID = try container.decodeIfPresent(String.self, forKey: .layoutID)
                layoutId = try container.decodeIfPresent(String.self, forKey: .layoutId)
                let rawType = try container.decodeIfPresent(String.self, forKey: .type)
                    ?? (try container.decodeIfPresent(String.self, forKey: .entityType))
                type = Self.parseEntityKind(rawType)
                start = try container.decodeIfPresent(CADPoint.self, forKey: .start)
                end = try container.decodeIfPresent(CADPoint.self, forKey: .end)
                points = try container.decodeIfPresent([CADPoint].self, forKey: .points)
                isClosed = try container.decodeIfPresent(Bool.self, forKey: .isClosed)
                center = try container.decodeIfPresent(CADPoint.self, forKey: .center)
                radius = try container.decodeIfPresent(Double.self, forKey: .radius)
                insertionPoint = try container.decodeIfPresent(CADPoint.self, forKey: .insertionPoint)
                transform = try container.decodeIfPresent(CADTransform.self, forKey: .transform)
                scale = try container.decodeIfPresent(Double.self, forKey: .scale)
                scaleX = try container.decodeIfPresent(Double.self, forKey: .scaleX)
                scaleY = try container.decodeIfPresent(Double.self, forKey: .scaleY)
                rotationRadians = try container.decodeIfPresent(Double.self, forKey: .rotationRadians)
                rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees)
                rawText = try container.decodeIfPresent(String.self, forKey: .rawText)
                displayText = try container.decodeIfPresent(String.self, forKey: .displayText)
                textStyleId = try container.decodeIfPresent(String.self, forKey: .textStyleId)
                textStyleName = try container.decodeIfPresent(String.self, forKey: .textStyleName)
                blockName = try container.decodeIfPresent(String.self, forKey: .blockName)
                color = Self.decodeColor(from: container)
                lineType = try container.decodeIfPresent(String.self, forKey: .lineType)
                lineWeight = try container.decodeIfPresent(Double.self, forKey: .lineWeight)
                bounds = try container.decodeIfPresent(CADBounds.self, forKey: .bounds)
                visibility = Self.parseVisibility(try container.decodeIfPresent(String.self, forKey: .visibility))
                diagnostics = try container.decodeIfPresent(CADDrawingDiagnostics.self, forKey: .diagnostics)
                unsupportedReason = try container.decodeIfPresent(String.self, forKey: .unsupportedReason)
            }

            func makeEntity() -> CADEntity {
                let entityType = type ?? .line
                let path = makePath(for: entityType)
                let textPoint = insertionPoint ?? start ?? bounds?.center ?? .zero
                let sourceText = rawText ?? displayText
                let textRun = sourceText.map {
                    CADTextRun(
                        rawText: $0,
                        displayText: displayText,
                        styleName: textStyleName ?? CADTextStyle.default.name,
                        insertionPoint: textPoint,
                        textStyleId: textStyleId ?? CADTextStyle.default.id
                    )
                }
                let entityBounds = makeBounds(entityType: entityType, path: path, textPoint: textPoint)
                let entityDiagnostics = makeDiagnostics()
                let entityTransform = makeTransform(for: entityType)
                return CADEntity(
                    id: id.flatMap(UUID.init(uuidString:)) ?? UUID(),
                    kind: entityType,
                    layerID: layerID ?? layerId ?? CADLayer.default.id,
                    layoutID: layoutID ?? layoutId ?? CADLayout.modelSpace.id,
                    color: color ?? 0x00000000,
                    lineType: lineType ?? "ByLayer",
                    lineWeight: lineWeight ?? -1,
                    path: textRun == nil ? path : nil,
                    text: textRun,
                    blockName: blockName,
                    transform: entityTransform,
                    bounds: entityBounds,
                    visibility: visibility ?? .visible,
                    sourceHandle: sourceHandle ?? handle ?? id,
                    diagnostics: entityDiagnostics,
                    unsupportedReason: unsupportedReason ?? entityDiagnostics.entries.first?.message
                )
            }

            private func makePath(for entityType: CADEntityKind) -> CADPath? {
                if let points, !points.isEmpty {
                    var elements: [CADPath.Element] = [.move(to: points[0])]
                    elements.append(contentsOf: points.dropFirst().map { .line(to: $0) })
                    if isClosed == true {
                        elements.append(.close)
                    }
                    return CADPath(elements: elements)
                }
                guard let start, let end else { return nil }
                switch entityType {
                case .line, .polyline, .lwPolyline, .spline, .dimension, .hatch, .table, .unsupported, .proxy:
                    return CADPath(elements: [.move(to: start), .line(to: end)])
                default:
                    return nil
                }
            }

            private func makeBounds(entityType: CADEntityKind, path: CADPath?, textPoint: CADPoint) -> CADBounds {
                if let bounds {
                    return bounds
                }
                if let path, !path.bounds.isEmpty {
                    return path.bounds
                }
                if (entityType == .circle || entityType == .arc), let center, let radius {
                    return CADBounds(
                        minX: center.x - radius,
                        minY: center.y - radius,
                        maxX: center.x + radius,
                        maxY: center.y + radius
                    )
                }
                if entityType == .insert || entityType == .blockReference,
                   let insertionPoint {
                    return CADBounds(
                        minX: insertionPoint.x,
                        minY: insertionPoint.y,
                        maxX: insertionPoint.x,
                        maxY: insertionPoint.y
                    )
                }
                if rawText != nil || displayText != nil {
                    return CADBounds(minX: textPoint.x, minY: textPoint.y, maxX: textPoint.x, maxY: textPoint.y)
                }
                if let start, let end {
                    return CADBounds(
                        minX: min(start.x, end.x),
                        minY: min(start.y, end.y),
                        maxX: max(start.x, end.x),
                        maxY: max(start.y, end.y)
                    )
                }
                return .empty
            }

            private func makeTransform(for entityType: CADEntityKind) -> CADTransform {
                var resolved = transform ?? .identity
                guard entityType == .insert || entityType == .blockReference else {
                    return resolved
                }

                if let insertionPoint {
                    resolved = resolved.concatenating(
                        .translation(x: insertionPoint.x, y: insertionPoint.y)
                    )
                }
                let radians = rotationRadians
                    ?? rotationDegrees.map { $0 * .pi / 180 }
                    ?? 0
                if radians != 0 {
                    resolved = resolved.concatenating(.rotation(radians))
                }
                let sx = scaleX ?? scale ?? 1
                let sy = scaleY ?? scale ?? 1
                if sx != 1 || sy != 1 {
                    resolved = resolved.concatenating(.scale(x: sx, y: sy))
                }
                return resolved
            }

            private func makeDiagnostics() -> CADDrawingDiagnostics {
                var resolved = diagnostics ?? CADDrawingDiagnostics()
                if let unsupportedReason, resolved.entries.isEmpty {
                    resolved.append(
                        CADDrawingDiagnostics.Entry(
                            severity: .warning,
                            code: "CAD_INTERMEDIATE_ENTITY_UNSUPPORTED",
                            message: unsupportedReason,
                            detail: sourceHandle ?? handle ?? id
                        )
                    )
                }
                return resolved
            }

            private static func parseEntityKind(_ raw: String?) -> CADEntityKind? {
                guard let raw else { return nil }
                let normalized = raw
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .replacingOccurrences(of: "_", with: "")
                    .replacingOccurrences(of: "-", with: "")
                switch normalized {
                case "point":
                    return .point
                case "line":
                    return .line
                case "polyline":
                    return .polyline
                case "lwpolyline":
                    return .lwPolyline
                case "circle":
                    return .circle
                case "arc":
                    return .arc
                case "ellipse":
                    return .ellipse
                case "spline":
                    return .spline
                case "text":
                    return .text
                case "mtext":
                    return .mtext
                case "insert", "block":
                    return .insert
                case "blockreference":
                    return .blockReference
                case "attrib", "attribute":
                    return .attrib
                case "dimension", "dim":
                    return .dimension
                case "hatch":
                    return .hatch
                case "image":
                    return .image
                case "table":
                    return .table
                case "xref":
                    return .xref
                case "proxy":
                    return .proxy
                case "unsupported":
                    return .unsupported
                default:
                    return nil
                }
            }

            private static func parseVisibility(_ raw: String?) -> CADVisibility? {
                guard let raw else { return nil }
                switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "visible":
                    return .visible
                case "hidden":
                    return .hidden
                default:
                    return nil
                }
            }

            private static func decodeColor(
                from container: KeyedDecodingContainer<CodingKeys>
            ) -> UInt32? {
                if let direct = try? container.decode(UInt32.self, forKey: .color) {
                    return direct
                }
                if let number = try? container.decode(UInt64.self, forKey: .color) {
                    return UInt32(truncatingIfNeeded: number)
                }
                if let string = try? container.decode(String.self, forKey: .color) {
                    let trimmed = string
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    if let hex = UInt32(trimmed.replacingOccurrences(of: "0x", with: ""), radix: 16) {
                        return hex
                    }
                    if let decimal = UInt32(trimmed) {
                        return decimal
                    }
                }
                return nil
            }
        }

        struct TextStyle: Decodable {
            var id: String
            var name: String
            var fontName: String?
            var bigFontName: String?
            var fixedHeight: Double?
            var widthFactor: Double?
            var obliqueAngleRadians: Double?
        }

        var units: CADUnits?
        var extents: CADBounds?
        var layers: [Layer]
        var layouts: [Layout]?
        var blocks: [Block]?
        var textStyles: [TextStyle]?
        var entities: [Entity]
        var xrefs: [CADXref]?
    }
}
