import Foundation

enum SiteKeeperCADKernel {}

extension SiteKeeperCADKernel {
    struct CADUnits: Equatable, Codable {
        var name: String
        var metersPerDrawingUnit: Double?

        init(name: String = "unitless", metersPerDrawingUnit: Double? = nil) {
            self.name = name
            self.metersPerDrawingUnit = metersPerDrawingUnit
        }

        static let unitless = CADUnits()
    }

    struct CADXref: Identifiable, Equatable, Codable {
        var id: String
        var name: String
        var path: String?
        var isResolved: Bool
        var diagnostics: CADDrawingDiagnostics

        init(
            id: String = UUID().uuidString,
            name: String,
            path: String? = nil,
            isResolved: Bool = false,
            diagnostics: CADDrawingDiagnostics = CADDrawingDiagnostics()
        ) {
            self.id = id
            self.name = name
            self.path = path
            self.isResolved = isResolved
            self.diagnostics = diagnostics
        }
    }

    struct CADDatabase: Equatable, Codable {
        var drawingId: UUID
        var sourceFile: CADFile
        var units: CADUnits
        var extents: CADBounds
        var layers: [CADLayer]
        var layouts: [CADLayout]
        var blocks: [CADBlock]
        var entities: [CADEntity]
        var textStyles: [CADTextStyle]
        var viewports: [CADViewport]
        var xrefs: [CADXref]
        var diagnostics: CADDrawingDiagnostics
        var geometryParsed: Bool
        var entityCount: Int
        var drawableEntityCount: Int
        var placeholderEntityCount: Int
        var isMetadataOnly: Bool
        var importSource: String
        var importWarnings: [String]
        var performanceTrace: CADPerformanceTrace
        var textTrace: [CADTextTrace]

        enum CodingKeys: String, CodingKey {
            case drawingId
            case id
            case sourceFile
            case file
            case units
            case extents
            case modelBounds
            case layers
            case layouts
            case blocks
            case entities
            case textStyles
            case viewports
            case xrefs
            case diagnostics
            case geometryParsed
            case entityCount
            case drawableEntityCount
            case placeholderEntityCount
            case isMetadataOnly
            case importSource
            case importWarnings
            case performanceTrace
            case textTrace
        }

        init(
            id: UUID = UUID(),
            file: CADFile,
            units: CADUnits = .unitless,
            extents: CADBounds = .empty,
            layers: [CADLayer] = [.default],
            layouts: [CADLayout] = [.modelSpace],
            blocks: [CADBlock] = [],
            entities: [CADEntity] = [],
            textStyles: [CADTextStyle] = [.default],
            viewports: [CADViewport] = [],
            xrefs: [CADXref] = [],
            diagnostics: CADDrawingDiagnostics = CADDrawingDiagnostics(),
            modelBounds: CADBounds = .empty,
            geometryParsed: Bool? = nil,
            entityCount: Int? = nil,
            drawableEntityCount: Int? = nil,
            placeholderEntityCount: Int? = nil,
            isMetadataOnly: Bool? = nil,
            importSource: String = "unknown",
            importWarnings: [String] = [],
            performanceTrace: CADPerformanceTrace = CADPerformanceTrace(),
            textTrace: [CADTextTrace] = []
        ) {
            self.drawingId = id
            self.sourceFile = file
            self.units = units
            self.extents = modelBounds.isEmpty ? extents : modelBounds
            self.layers = layers
            self.layouts = layouts
            self.blocks = blocks
            self.entities = entities
            self.textStyles = textStyles
            self.viewports = viewports
            self.xrefs = xrefs
            self.diagnostics = diagnostics
            self.geometryParsed = false
            self.entityCount = 0
            self.drawableEntityCount = 0
            self.placeholderEntityCount = 0
            self.isMetadataOnly = false
            self.importSource = importSource
            self.importWarnings = importWarnings
            self.performanceTrace = performanceTrace
            self.textTrace = textTrace

            applyImportMetadata(
                geometryParsed: geometryParsed,
                entityCount: entityCount,
                drawableEntityCount: drawableEntityCount,
                placeholderEntityCount: placeholderEntityCount,
                isMetadataOnly: isMetadataOnly,
                importWarnings: importWarnings
            )
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let drawingId = try container.decodeIfPresent(UUID.self, forKey: .drawingId)
                ?? container.decodeIfPresent(UUID.self, forKey: .id)
                ?? UUID()
            let sourceFile = try container.decodeIfPresent(CADFile.self, forKey: .sourceFile)
                ?? container.decode(CADFile.self, forKey: .file)
            let units = try container.decodeIfPresent(CADUnits.self, forKey: .units) ?? .unitless
            let extents = try container.decodeIfPresent(CADBounds.self, forKey: .extents)
                ?? container.decodeIfPresent(CADBounds.self, forKey: .modelBounds)
                ?? .empty
            let layers = try container.decodeIfPresent([CADLayer].self, forKey: .layers) ?? [.default]
            let layouts = try container.decodeIfPresent([CADLayout].self, forKey: .layouts) ?? [.modelSpace]
            let blocks = try container.decodeIfPresent([CADBlock].self, forKey: .blocks) ?? []
            let entities = try container.decodeIfPresent([CADEntity].self, forKey: .entities) ?? []
            let textStyles = try container.decodeIfPresent([CADTextStyle].self, forKey: .textStyles) ?? [.default]
            let viewports = try container.decodeIfPresent([CADViewport].self, forKey: .viewports) ?? []
            let xrefs = try container.decodeIfPresent([CADXref].self, forKey: .xrefs) ?? []
            let diagnostics = try container.decodeIfPresent(CADDrawingDiagnostics.self, forKey: .diagnostics) ?? CADDrawingDiagnostics()
            let geometryParsed = try container.decodeIfPresent(Bool.self, forKey: .geometryParsed)
            let entityCount = try container.decodeIfPresent(Int.self, forKey: .entityCount)
            let drawableEntityCount = try container.decodeIfPresent(Int.self, forKey: .drawableEntityCount)
            let placeholderEntityCount = try container.decodeIfPresent(Int.self, forKey: .placeholderEntityCount)
            let isMetadataOnly = try container.decodeIfPresent(Bool.self, forKey: .isMetadataOnly)
            let importSource = try container.decodeIfPresent(String.self, forKey: .importSource) ?? "unknown"
            let importWarnings = try container.decodeIfPresent([String].self, forKey: .importWarnings) ?? []
            let performanceTrace = try container.decodeIfPresent(CADPerformanceTrace.self, forKey: .performanceTrace)
                ?? CADPerformanceTrace()
            let textTrace = try container.decodeIfPresent([CADTextTrace].self, forKey: .textTrace) ?? []

            self.init(
                id: drawingId,
                file: sourceFile,
                units: units,
                extents: extents,
                layers: layers,
                layouts: layouts,
                blocks: blocks,
                entities: entities,
                textStyles: textStyles,
                viewports: viewports,
                xrefs: xrefs,
                diagnostics: diagnostics,
                modelBounds: extents,
                geometryParsed: geometryParsed,
                entityCount: entityCount,
                drawableEntityCount: drawableEntityCount,
                placeholderEntityCount: placeholderEntityCount,
                isMetadataOnly: isMetadataOnly,
                importSource: importSource,
                importWarnings: importWarnings,
                performanceTrace: performanceTrace,
                textTrace: textTrace
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(drawingId, forKey: .drawingId)
            try container.encode(sourceFile, forKey: .sourceFile)
            try container.encode(units, forKey: .units)
            try container.encode(extents, forKey: .extents)
            try container.encode(layers, forKey: .layers)
            try container.encode(layouts, forKey: .layouts)
            try container.encode(blocks, forKey: .blocks)
            try container.encode(entities, forKey: .entities)
            try container.encode(textStyles, forKey: .textStyles)
            try container.encode(viewports, forKey: .viewports)
            try container.encode(xrefs, forKey: .xrefs)
            try container.encode(diagnostics, forKey: .diagnostics)
            try container.encode(geometryParsed, forKey: .geometryParsed)
            try container.encode(entityCount, forKey: .entityCount)
            try container.encode(drawableEntityCount, forKey: .drawableEntityCount)
            try container.encode(placeholderEntityCount, forKey: .placeholderEntityCount)
            try container.encode(isMetadataOnly, forKey: .isMetadataOnly)
            try container.encode(importSource, forKey: .importSource)
            try container.encode(importWarnings, forKey: .importWarnings)
            try container.encode(performanceTrace, forKey: .performanceTrace)
            try container.encode(textTrace, forKey: .textTrace)
        }

        var id: UUID {
            drawingId
        }

        var file: CADFile {
            sourceFile
        }

        var modelBounds: CADBounds {
            get { extents }
            set { extents = newValue }
        }

        var visibleLayerIDs: Set<String> {
            Set(layers.filter(\.isVisible).map(\.id))
        }

        var hasRenderableContent: Bool {
            geometryParsed && drawableEntityCount > 0
        }

        func layer(id: String) -> CADLayer? {
            layers.first { $0.id == id }
        }

        func textStyle(id: String) -> CADTextStyle? {
            textStyles.first { $0.id == id }
        }

        mutating func append(_ entity: CADEntity) {
            entities.append(entity)
            modelBounds = modelBounds.union(entity.bounds)
            applyImportMetadata(
                geometryParsed: nil,
                entityCount: nil,
                drawableEntityCount: nil,
                placeholderEntityCount: nil,
                isMetadataOnly: nil,
                importWarnings: importWarnings
            )
        }

        mutating func setImportMetadata(
            geometryParsed: Bool? = nil,
            isMetadataOnly: Bool? = nil,
            importSource: String? = nil,
            importWarnings: [String]? = nil
        ) {
            if let importSource {
                self.importSource = importSource
            }
            applyImportMetadata(
                geometryParsed: geometryParsed,
                entityCount: nil,
                drawableEntityCount: nil,
                placeholderEntityCount: nil,
                isMetadataOnly: isMetadataOnly,
                importWarnings: importWarnings ?? self.importWarnings
            )
        }

        static func isPlaceholderEntity(_ entity: CADEntity) -> Bool {
            if entity.kind == .unsupported || entity.kind == .proxy || entity.kind == .xref {
                return true
            }
            if entity.kind == .image, !entity.isRenderable {
                return true
            }
            if let reason = entity.unsupportedReason?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               reason.contains("placeholder") || reason.contains("占位") {
                return true
            }
            return entity.diagnostics.entries.contains { $0.code.localizedCaseInsensitiveContains("PLACEHOLDER") }
        }

        private mutating func applyImportMetadata(
            geometryParsed: Bool?,
            entityCount: Int?,
            drawableEntityCount: Int?,
            placeholderEntityCount: Int?,
            isMetadataOnly: Bool?,
            importWarnings: [String]
        ) {
            let computedEntityCount = entities.count
            let computedDrawableCount = entities.filter { entity in
                entity.visibility == .visible && entity.isRenderable && !Self.isPlaceholderEntity(entity)
            }.count
            let computedPlaceholderCount = entities.filter(Self.isPlaceholderEntity).count
            let inferredGeometryParsed = entities.contains { !Self.isPlaceholderEntity($0) && $0.kind != .unsupported }
            let resolvedGeometryParsed = geometryParsed ?? inferredGeometryParsed
            let resolvedMetadataOnly = isMetadataOnly
                ?? (!resolvedGeometryParsed || (computedDrawableCount == 0 && computedPlaceholderCount > 0))

            self.geometryParsed = resolvedGeometryParsed
            self.entityCount = entityCount ?? computedEntityCount
            self.drawableEntityCount = drawableEntityCount ?? computedDrawableCount
            self.placeholderEntityCount = placeholderEntityCount ?? computedPlaceholderCount
            self.isMetadataOnly = resolvedMetadataOnly
            self.importWarnings = Self.mergeImportWarnings(
                explicit: importWarnings,
                diagnostics: diagnostics
            )
        }

        private static func mergeImportWarnings(
            explicit: [String],
            diagnostics: CADDrawingDiagnostics
        ) -> [String] {
            var merged = explicit
            var seen = Set(explicit)
            for entry in diagnostics.entries where entry.severity != .info {
                let warning = (entry.detail ?? "").isEmpty
                    ? "\(entry.code): \(entry.message)"
                    : "\(entry.code): \(entry.message) (\(entry.detail ?? ""))"
                guard !warning.isEmpty, !seen.contains(warning) else { continue }
                seen.insert(warning)
                merged.append(warning)
            }
            return merged
        }
    }
}
