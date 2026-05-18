import Foundation
import CoreFoundation

extension CADPoC {
    struct CADImportResult: Codable {
        var database: SiteKeeperCADKernel.CADDatabase
        var trace: CADOpenTrace
    }

    struct LibreDWGNativeImportEngine: SiteKeeperCADKernel.CADImportEngine {
        typealias Kernel = SiteKeeperCADKernel

        private static let nativePaperLayoutID = "paper"
        private let baseID = "sitekeeper.poc.dwg-libredwg-ios.basic2d-v13"
        var preferredTextCodePage: Int32?
        var preferredTextBigFont: Int32?
        var fontMappings: [CADRendererFontMapping]
        var preferredDisplayFontName: String?

        init(
            preferredTextCodePage: Int32? = nil,
            preferredTextBigFont: Int32? = nil,
            fontMappings: [CADRendererFontMapping] = [],
            preferredDisplayFontName: String? = nil
        ) {
            self.preferredTextCodePage = preferredTextCodePage == 0 ? nil : preferredTextCodePage
            self.preferredTextBigFont = preferredTextBigFont == 0 ? nil : preferredTextBigFont
            self.fontMappings = fontMappings
            let displayFont = preferredDisplayFontName?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.preferredDisplayFontName = displayFont?.isEmpty == false ? displayFont : nil
        }

        var id: String {
            let textKey = textOptionCacheKey
            return textKey.isEmpty ? baseID : "\(baseID).\(textKey)"
        }

        func canImport(file: Kernel.CADFile) -> Bool {
            switch file.format {
            case .dxf:
                return true
            case .dwg:
                return true
            case .intermediateJSON, .unknown:
                return false
            }
        }

        func importDrawing(file: Kernel.CADFile) async throws -> Kernel.CADDatabase {
            try await importDrawingWithTrace(file: file).database
        }

        func importDrawingWithTrace(file: Kernel.CADFile) async throws -> CADImportResult {
            if var cached = await CADImportResultCache.shared.result(for: file, engineID: id) {
                cached.trace.importCacheHit = true
                cached.trace.importMilliseconds = 0
                return cached
            }

            let importStart = Date()
            let result: CADImportResult
            switch file.format {
            case .dxf:
                result = try importDXFGeometry(
                    dxfFile: file,
                    sourceFile: file,
                    importSource: id,
                    convertedFromDWG: nil
                )
            case .dwg:
                result = try importNativeDWGBasic2DGeometry(file: file)
            case .intermediateJSON, .unknown:
                throw Kernel.CADImportError.unsupportedFormat(file.format)
            }

            var tracedResult = result
            tracedResult.trace.importCacheHit = false
            tracedResult.trace.importMilliseconds = Date().timeIntervalSince(importStart) * 1000
            await CADImportResultCache.shared.store(tracedResult, for: file, engineID: id)
            return tracedResult
        }

        private func importNativeDWGBasic2DGeometry(file: Kernel.CADFile) throws -> CADImportResult {
            var nativeResult = SiteKeeperLibreDWGEntityResult()
            let status = file.url.path.withCString { path in
                SiteKeeperLibreDWGReadBasic2D(path, &nativeResult)
            }
            defer {
                SiteKeeperLibreDWGFreeBasic2D(&nativeResult)
            }

            let rawLineCount = Int(nativeResult.trace.rawLineCount)
            let rawPolylineCount = Int(nativeResult.trace.rawPolylineCount)
            let rawCircleCount = Int(nativeResult.trace.rawCircleCount)
            let rawArcCount = Int(nativeResult.trace.rawArcCount)
            let rawInsertCount = Int(nativeResult.trace.rawInsertCount)
            let rawTextCount = Int(nativeResult.trace.rawTextCount)
            let rawDimensionCount = Int(nativeResult.trace.rawDimensionCount)
            let rawHatchCount = Int(nativeResult.trace.rawHatchCount)
            let rawEllipseCount = Int(nativeResult.trace.rawEllipseCount)
            let rawSplineCount = Int(nativeResult.trace.rawSplineCount)
            let rawFilledShapeCount = Int(nativeResult.trace.rawFilledShapeCount)
            let rawProxyEntityCount = Int(nativeResult.trace.rawProxyEntityCount)
            let rawTianzhengProxyCount = Int(nativeResult.trace.rawTianzhengProxyCount)
            let expandedInsertEntityCount = Int(nativeResult.trace.exportedInsertEntityCount)
            let exportedDimensionCount = Int(nativeResult.trace.exportedDimensionCount)
            let exportedHatchCount = Int(nativeResult.trace.exportedHatchCount)
            let exportedEllipseCount = Int(nativeResult.trace.exportedEllipseCount)
            let exportedSplineCount = Int(nativeResult.trace.exportedSplineCount)
            let exportedFilledShapeCount = Int(nativeResult.trace.exportedFilledShapeCount)
            let exportedProxyEntityCount = Int(nativeResult.trace.exportedProxyEntityCount)
            let exportedTianzhengProxyCount = Int(nativeResult.trace.exportedTianzhengProxyCount)
            let rawEntityCount = Int(nativeResult.trace.rawEntityCount)
            let entityCount = Int(nativeResult.entityCount)
            let nativeEntities = UnsafeBufferPointer(
                start: nativeResult.entities,
                count: max(0, entityCount)
            )

            let entities: [Kernel.CADEntity] = nativeEntities.compactMap { nativeEntity in
                makeNativeEntity(nativeEntity)
            }
            let textTrace = Self.textTraces(from: entities)
            let importedTextSummary = Self.importedTextSummary(
                entities: entities,
                traces: textTrace
            )
            let proxyTextCandidateSummary = Self.proxyTextCandidateSummary(entities: entities)

            var diagnostics = Kernel.CADDrawingDiagnostics()
            diagnostics.append(
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_POC_LIBREDWG_IOS_NATIVE_USED",
                    message: "LibreDWG was called inside the iOS process and converted basic 2D geometry into CADEntity.",
                    detail: "status=\(status), rawEntityCount=\(rawEntityCount), rawInsertCount=\(rawInsertCount), rawTextCount=\(rawTextCount), rawEllipseCount=\(rawEllipseCount), rawSplineCount=\(rawSplineCount), rawFilledShapeCount=\(rawFilledShapeCount), rawDimensionCount=\(rawDimensionCount), rawHatchCount=\(rawHatchCount), rawProxyEntityCount=\(rawProxyEntityCount), rawTianzhengProxyCount=\(rawTianzhengProxyCount), exportedEntityCount=\(entityCount), expandedInsertEntityCount=\(expandedInsertEntityCount), exportedTextCount=\(Int(nativeResult.trace.exportedTextCount)), exportedEllipseCount=\(exportedEllipseCount), exportedSplineCount=\(exportedSplineCount), exportedFilledShapeCount=\(exportedFilledShapeCount), exportedDimensionCount=\(exportedDimensionCount), exportedHatchCount=\(exportedHatchCount), exportedProxyEntityCount=\(exportedProxyEntityCount), exportedTianzhengProxyCount=\(exportedTianzhengProxyCount)"
                )
            )
            diagnostics.append(
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_POC_TEXT_IMPORT_SUMMARY",
                    message: "CAD text import summary for LibreDWG native PoC.",
                    detail: importedTextSummary
                )
            )
            if rawTextCount > 0, textTrace.isEmpty {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_TEXT_RAW_BUT_NOT_IMPORTED",
                        message: "LibreDWG reported raw text objects, but no text entities reached CADDatabase.",
                        detail: "rawTextCount=\(rawTextCount), exportedTextCount=\(Int(nativeResult.trace.exportedTextCount))"
                    )
                )
            }
            if status != 0 {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_READ_WARNING",
                        message: "LibreDWG returned a non-zero read status.",
                        detail: "\(status)"
                    )
                )
            }
            if rawEntityCount > 0, entityCount == 0 {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_NO_SUPPORTED_BASIC_2D_ENTITY",
                        message: "LibreDWG parsed entities, but this PoC only exports LINE, POINT, XLINE, RAY, LWPOLYLINE, POLYLINE, CIRCLE, ARC, ELLIPSE, SPLINE, SOLID, TRACE, 3DFACE, LEADER, MLINE, TEXT, MTEXT, ATTRIB, ATTDEF, simplified DIMENSION, degraded HATCH/WIPEOUT boundaries, IMAGE/UNDERLAY placeholders, and INSERT/BLOCK-expanded basic geometry.",
                        detail: "rawEntityCount=\(rawEntityCount)"
                    )
                )
            }
            if rawEllipseCount > exportedEllipseCount {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_ELLIPSE_PARTIALLY_UNSUPPORTED",
                        message: "Some DWG ELLIPSE entities could not be tessellated by the native LibreDWG PoC importer.",
                        detail: "rawEllipseCount=\(rawEllipseCount), exportedEllipseCount=\(exportedEllipseCount)"
                    )
                )
            }
            if exportedEllipseCount > 0 {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_ELLIPSE_TESSELLATED",
                        message: "DWG ELLIPSE entities were imported as tessellated polylines.",
                        detail: "exportedEllipseCount=\(exportedEllipseCount)"
                    )
                )
            }
            if rawSplineCount > exportedSplineCount {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_SPLINE_PARTIALLY_UNSUPPORTED",
                        message: "Some DWG SPLINE entities could not be degraded by the native LibreDWG PoC importer.",
                        detail: "rawSplineCount=\(rawSplineCount), exportedSplineCount=\(exportedSplineCount)"
                    )
                )
            }
            if exportedSplineCount > 0 {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_SPLINE_DEGRADED_TO_POLYLINE",
                        message: "DWG SPLINE entities were imported as fit/control-point polylines.",
                        detail: "exportedSplineCount=\(exportedSplineCount)"
                    )
                )
            }
            if rawFilledShapeCount > exportedFilledShapeCount {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_FILLED_SHAPE_PARTIALLY_UNSUPPORTED",
                        message: "Some DWG SOLID, TRACE, or 3DFACE entities could not be degraded by the native LibreDWG PoC importer.",
                        detail: "rawFilledShapeCount=\(rawFilledShapeCount), exportedFilledShapeCount=\(exportedFilledShapeCount)"
                    )
                )
            }
            if exportedFilledShapeCount > 0 {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_FILLED_SHAPE_DEGRADED_TO_BOUNDARY",
                        message: "DWG SOLID, TRACE, and 3DFACE entities were imported as closed boundary paths.",
                        detail: "exportedFilledShapeCount=\(exportedFilledShapeCount)"
                    )
                )
            }
            if rawDimensionCount > exportedDimensionCount {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_DIMENSION_PARTIALLY_UNSUPPORTED",
                        message: "Some DWG DIMENSION entities could not be simplified by the native LibreDWG PoC importer.",
                        detail: "rawDimensionCount=\(rawDimensionCount), exportedDimensionCount=\(exportedDimensionCount)"
                    )
                )
            }
            if exportedDimensionCount > 0 {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_DIMENSION_SIMPLIFIED",
                        message: "DWG DIMENSION entities were imported as simplified dimension lines and text.",
                        detail: "exportedDimensionCount=\(exportedDimensionCount)"
                    )
                )
            }
            if rawHatchCount > exportedHatchCount {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_HATCH_PARTIALLY_UNSUPPORTED",
                        message: "Some DWG HATCH entities could not be converted to safe fill or boundary geometry by the native LibreDWG PoC importer.",
                        detail: "rawHatchCount=\(rawHatchCount), exportedHatchCount=\(exportedHatchCount)"
                    )
                )
            }
            if exportedHatchCount > 0 {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_HATCH_SAFE_RENDERING",
                        message: "DWG HATCH entities use simple fills only when safe; complex HATCH entities render as boundary-only geometry.",
                        detail: "exportedHatchCount=\(exportedHatchCount)"
                    )
                )
            }
            if rawProxyEntityCount > 0 {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_PROXY_ENTITY_PRESERVED",
                        message: "DWG proxy entities were preserved as diagnostics and are not counted as drawable geometry.",
                        detail: "rawProxyEntityCount=\(rawProxyEntityCount), exportedProxyEntityCount=\(exportedProxyEntityCount)"
                    )
                )
            }
            if let proxyTextCandidateSummary {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_PROXY_TEXT_CANDIDATE_SUMMARY",
                        message: "Proxy/Tianzheng custom objects contain possible text bytes; they are diagnostic-only until geometry and anchors are decoded.",
                        detail: proxyTextCandidateSummary
                    )
                )
            }
            if rawTianzhengProxyCount > 0 {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_TIANZHENG_PROXY_PRESERVED",
                        message: "Tianzheng/TCH proxy entities were preserved as diagnostics; custom object geometry is not decoded by the CAD Metal PoC.",
                        detail: "rawTianzhengProxyCount=\(rawTianzhengProxyCount), exportedTianzhengProxyCount=\(exportedTianzhengProxyCount)"
                    )
                )
            }
            if rawEntityCount == 0 {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_NO_RAW_ENTITIES",
                        message: "LibreDWG did not return drawable entities for this DWG.",
                        detail: file.displayName
                    )
                )
            }
            Self.appendTextDiagnostics(from: textTrace, to: &diagnostics)
            if rawEntityCount > 0, !entities.contains(where: \.isRenderable) {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_NO_DRAWABLE_GEOMETRY",
                        message: "LibreDWG returned entities, but none were drawable by the CAD Metal PoC.",
                        detail: "rawEntityCount=\(rawEntityCount), exportedEntityCount=\(entityCount), rawProxyEntityCount=\(rawProxyEntityCount), rawTianzhengProxyCount=\(rawTianzhengProxyCount)"
                    )
                )
            }

            let bounds = entities.reduce(Kernel.CADBounds.empty) { $0.union($1.bounds) }
            let layerIDs = Set(entities.map(\.layerID))
            let layerColors = Self.layerColors(from: entities)
            let layers = layerIDs.isEmpty
                ? [Kernel.CADLayer.default]
                : layerIDs.sorted().map { layerID in
                    Kernel.CADLayer(
                        id: layerID,
                        name: layerID,
                        colorARGB: layerColors[layerID] ?? Kernel.CADLayer.default.colorARGB
                    )
                }

            let layouts = Self.nativeLayouts(from: entities)
            var database = Kernel.CADDatabase(
                file: file,
                extents: bounds,
                layers: layers,
                layouts: layouts,
                entities: entities,
                diagnostics: diagnostics,
                importSource: id,
                textTrace: textTrace
            )
            let hasDrawableGeometry = entities.contains(where: \.isRenderable)
            database.setImportMetadata(
                geometryParsed: hasDrawableGeometry,
                isMetadataOnly: !hasDrawableGeometry,
                importSource: id
            )
            let layersByID = Dictionary(uniqueKeysWithValues: database.layers.map { ($0.id, $0) })
            let renderCommandCount = CADRenderPipeline()
                .commands(from: database.entities, layersByID: layersByID)
                .count

            let trace = CADOpenTrace(
                fileName: file.displayName,
                importSource: id,
                rawLineCount: rawLineCount,
                rawPolylineCount: rawPolylineCount,
                rawCircleCount: rawCircleCount,
                rawArcCount: rawArcCount,
                rawInsertCount: rawInsertCount,
                rawEllipseCount: rawEllipseCount,
                rawSplineCount: rawSplineCount,
                rawFilledShapeCount: rawFilledShapeCount,
                rawDimensionCount: rawDimensionCount,
                rawHatchCount: rawHatchCount,
                rawTextCount: rawTextCount,
                rawProxyEntityCount: rawProxyEntityCount,
                rawTianzhengProxyCount: rawTianzhengProxyCount,
                expandedInsertEntityCount: expandedInsertEntityCount,
                exportedProxyEntityCount: exportedProxyEntityCount,
                exportedTianzhengProxyCount: exportedTianzhengProxyCount,
                entityCount: database.entityCount,
                drawableEntityCount: database.drawableEntityCount,
                renderCommandCount: renderCommandCount,
                bounds: database.extents,
                openedForRender: database.geometryParsed && database.drawableEntityCount > 0 && renderCommandCount > 0
            )
            return CADImportResult(database: database, trace: trace)
        }

        private func entityKind(for nativeKind: Int32) -> Kernel.CADEntityKind? {
            guard nativeKind >= 0 else { return nil }
            switch UInt32(nativeKind) {
            case SiteKeeperLibreDWGEntityKindLine.rawValue:
                return .line
            case SiteKeeperLibreDWGEntityKindPoint.rawValue:
                return .point
            case SiteKeeperLibreDWGEntityKindRay.rawValue,
                 SiteKeeperLibreDWGEntityKindXLine.rawValue:
                return .line
            case SiteKeeperLibreDWGEntityKindPolyline.rawValue:
                return .polyline
            case SiteKeeperLibreDWGEntityKindLWPolyline.rawValue:
                return .lwPolyline
            case SiteKeeperLibreDWGEntityKindCircle.rawValue:
                return .circle
            case SiteKeeperLibreDWGEntityKindArc.rawValue:
                return .arc
            case SiteKeeperLibreDWGEntityKindText.rawValue:
                return .text
            case SiteKeeperLibreDWGEntityKindMText.rawValue:
                return .mtext
            case SiteKeeperLibreDWGEntityKindAttrib.rawValue:
                return .attrib
            case SiteKeeperLibreDWGEntityKindDimension.rawValue:
                return .dimension
            case SiteKeeperLibreDWGEntityKindHatch.rawValue:
                return .hatch
            case SiteKeeperLibreDWGEntityKindEllipse.rawValue:
                return .ellipse
            case SiteKeeperLibreDWGEntityKindSpline.rawValue:
                return .spline
            case SiteKeeperLibreDWGEntityKindFilledShape.rawValue:
                return .hatch
            case SiteKeeperLibreDWGEntityKindLeader.rawValue,
                 SiteKeeperLibreDWGEntityKindMLine.rawValue:
                return .polyline
            case SiteKeeperLibreDWGEntityKindImage.rawValue,
                 SiteKeeperLibreDWGEntityKindUnderlay.rawValue:
                return .image
            case SiteKeeperLibreDWGEntityKindWipeout.rawValue:
                return .hatch
            case SiteKeeperLibreDWGEntityKindProxy.rawValue,
                 SiteKeeperLibreDWGEntityKindTianzhengProxy.rawValue:
                return .proxy
            default:
                return nil
            }
        }

        func entityKindForNativeKindForTesting(_ nativeKind: Int32) -> Kernel.CADEntityKind? {
            entityKind(for: nativeKind)
        }

        func makeNativeEntityForTesting(_ nativeEntity: SiteKeeperLibreDWGEntity) -> Kernel.CADEntity? {
            makeNativeEntity(nativeEntity)
        }

        func proxyTextCandidateSummaryForTesting(entities: [Kernel.CADEntity]) -> String? {
            Self.proxyTextCandidateSummary(entities: entities)
        }

        private func makeNativeEntity(_ nativeEntity: SiteKeeperLibreDWGEntity) -> Kernel.CADEntity? {
            guard let kind = entityKind(for: nativeEntity.kind) else {
                return nil
            }
            let layerID = decodedNativeString(nativeEntity.layerName) ?? Kernel.CADLayer.default.id
            let normalizedLayerID = layerID.isEmpty ? Kernel.CADLayer.default.id : layerID
            let sourceHandle = decodedNativeString(nativeEntity.sourceHandle)
            let layoutID = nativeLayoutID(for: nativeEntity)

            switch kind {
            case .proxy:
                return makeNativeProxyEntity(
                    nativeEntity,
                    layerID: normalizedLayerID,
                    layoutID: layoutID,
                    sourceHandle: sourceHandle
                )
            case .text, .mtext, .attrib:
                guard let rawTextPointer = nativeEntity.rawText else { return nil }
                let rawText = decodedNativeString(rawTextPointer) ?? String(cString: rawTextPointer)
                let styleName = decodedNativeString(nativeEntity.textStyleName) ?? Kernel.CADTextStyle.default.name
                let fontName = decodedNativeString(nativeEntity.fontName)
                let bigFontName = resolvedBigFontName(
                    nativeBigFontName: decodedNativeString(nativeEntity.bigFontName),
                    fontName: fontName,
                    styleName: styleName
                )
                let height = nativeEntity.textHeight.isFinite && nativeEntity.textHeight > 0
                    ? nativeEntity.textHeight
                    : 2.5
                let insertion = Kernel.CADPoint(x: nativeEntity.textX, y: nativeEntity.textY)
                let style = Kernel.CADTextStyle(
                    id: styleName,
                    name: styleName,
                    fontName: fontName,
                    bigFontName: bigFontName,
                    widthFactor: nativeTextWidthFactor(nativeEntity)
                )
                let text = applyPreferredDisplayFont(
                    to: Kernel.CADTextEngine().makeTextRun(
                    rawText: rawText,
                    insertionPoint: insertion,
                    style: style,
                    height: height,
                    rotationRadians: nativeEntity.textRotation,
                    widthFactor: nativeTextWidthFactor(nativeEntity),
                    boxWidth: nativeEntity.textBoxWidth > 0 ? nativeEntity.textBoxWidth : nil,
                    boxHeight: nativeEntity.textBoxHeight > 0 ? nativeEntity.textBoxHeight : nil,
                    horizontalAlignmentCode: Int(nativeEntity.textHorizontalAlignment),
                    verticalAlignmentCode: Int(nativeEntity.textVerticalAlignment)
                    )
                )
                let bounds = nativeTextBounds(for: text, insertion: insertion, height: height)
                return Kernel.CADEntity(
                    kind: kind,
                    layerID: normalizedLayerID,
                    layoutID: layoutID,
                    color: nativeEntity.colorARGB,
                    lineType: "Continuous",
                    lineWeight: max(nativeEntity.lineWeight, 2),
                    text: text,
                    bounds: bounds,
                    sourceHandle: sourceHandle
                )
            case .dimension:
                let path = path(for: nativeEntity)
                var text: Kernel.CADTextRun?
                var bounds = path?.bounds ?? .empty
                if let rawTextPointer = nativeEntity.rawText {
                    let rawText = decodedNativeString(rawTextPointer) ?? String(cString: rawTextPointer)
                    let styleName = decodedNativeString(nativeEntity.textStyleName) ?? Kernel.CADTextStyle.default.name
                    let fontName = decodedNativeString(nativeEntity.fontName)
                    let bigFontName = resolvedBigFontName(
                        nativeBigFontName: decodedNativeString(nativeEntity.bigFontName),
                        fontName: fontName,
                        styleName: styleName
                    )
                    let height = nativeEntity.textHeight.isFinite && nativeEntity.textHeight > 0
                        ? nativeEntity.textHeight
                        : 2.5
                    let insertion = Kernel.CADPoint(x: nativeEntity.textX, y: nativeEntity.textY)
                    let style = Kernel.CADTextStyle(
                        id: styleName,
                        name: styleName,
                        fontName: fontName,
                        bigFontName: bigFontName,
                        widthFactor: nativeTextWidthFactor(nativeEntity)
                    )
                    text = applyPreferredDisplayFont(
                        to: Kernel.CADTextEngine().makeTextRun(
                        rawText: rawText,
                        insertionPoint: insertion,
                        style: style,
                        height: height,
                        rotationRadians: nativeEntity.textRotation,
                        widthFactor: nativeTextWidthFactor(nativeEntity),
                        boxWidth: nativeEntity.textBoxWidth > 0 ? nativeEntity.textBoxWidth : nil,
                        boxHeight: nativeEntity.textBoxHeight > 0 ? nativeEntity.textBoxHeight : nil,
                        horizontalAlignmentCode: Int(nativeEntity.textHorizontalAlignment),
                        verticalAlignmentCode: Int(nativeEntity.textVerticalAlignment)
                        )
                    )
                    bounds = bounds.union(nativeTextBounds(for: text!, insertion: insertion, height: height))
                }
                guard path != nil || text != nil else {
                    return nil
                }
                return Kernel.CADEntity(
                    kind: .dimension,
                    layerID: normalizedLayerID,
                    layoutID: layoutID,
                    color: nativeEntity.colorARGB,
                    lineType: "Continuous",
                    lineWeight: max(nativeEntity.lineWeight, 2),
                    path: path,
                    text: text,
                    bounds: bounds,
                    sourceHandle: sourceHandle,
                    diagnostics: Kernel.CADDrawingDiagnostics(entries: [
                        Kernel.CADDrawingDiagnostics.Entry(
                            severity: .warning,
                            code: "CAD_POC_DIMENSION_SIMPLIFIED",
                            message: "DWG DIMENSION imported as a simplified dimension line and text for the CAD Metal PoC.",
                            detail: sourceHandle
                        )
                    ])
                )
            default:
                guard let path = path(for: nativeEntity) else {
                    return nil
                }
                return Kernel.CADEntity(
                    kind: kind,
                    layerID: normalizedLayerID,
                    layoutID: layoutID,
                    color: nativeEntity.colorARGB,
                    lineType: "Continuous",
                    lineWeight: max(nativeEntity.lineWeight, 2),
                    path: path,
                    bounds: path.bounds,
                    sourceHandle: sourceHandle,
                    diagnostics: nativeDiagnostics(
                        for: nativeEntity,
                        path: path,
                        sourceHandle: sourceHandle
                    ),
                    unsupportedReason: nativeUnsupportedReason(for: nativeEntity.kind)
                )
            }
        }

        private func makeNativeProxyEntity(
            _ nativeEntity: SiteKeeperLibreDWGEntity,
            layerID: String,
            layoutID: String,
            sourceHandle: String?
        ) -> Kernel.CADEntity {
            let objectName = decodedNativeString(nativeEntity.objectName) ?? "DWG_PROXY_ENTITY"
            let reason = decodedNativeString(nativeEntity.unsupportedReason)
                ?? nativeUnsupportedReason(for: nativeEntity.kind)
                ?? "DWG proxy entity preserved as diagnostic metadata."
            let isTianzheng = UInt32(nativeEntity.kind) == SiteKeeperLibreDWGEntityKindTianzhengProxy.rawValue
            let code = isTianzheng
                ? "CAD_POC_LIBREDWG_TIANZHENG_PROXY_ENTITY"
                : "CAD_POC_LIBREDWG_PROXY_ENTITY"
            let message = isTianzheng
                ? "Tianzheng/TCH proxy object was preserved as non-renderable diagnostic metadata."
                : "DWG proxy object was preserved as non-renderable diagnostic metadata."

            return Kernel.CADEntity(
                kind: .proxy,
                layerID: layerID,
                layoutID: layoutID,
                color: nativeEntity.colorARGB,
                lineType: "Continuous",
                lineWeight: max(nativeEntity.lineWeight, 2),
                bounds: .empty,
                sourceHandle: sourceHandle,
                diagnostics: Kernel.CADDrawingDiagnostics(entries: [
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: code,
                        message: message,
                        detail: "handle=\(sourceHandle ?? ""); objectName=\(objectName); reason=\(reason)"
                    )
                ]),
                unsupportedReason: reason
            )
        }

        private func nativeLayoutID(for nativeEntity: SiteKeeperLibreDWGEntity) -> String {
            nativeEntity.layoutSpace == 1 ? Self.nativePaperLayoutID : Kernel.CADLayout.modelSpace.id
        }

        private static func nativeLayouts(from entities: [Kernel.CADEntity]) -> [Kernel.CADLayout] {
            var layouts: [Kernel.CADLayout] = [.modelSpace]
            if entities.contains(where: { $0.layoutID == nativePaperLayoutID }) {
                layouts.append(Kernel.CADLayout(id: nativePaperLayoutID, name: "Paper", isModelSpace: false))
            }
            return layouts
        }

        private func nativeDiagnostics(
            for nativeEntity: SiteKeeperLibreDWGEntity,
            path: Kernel.CADPath,
            sourceHandle: String?
        ) -> Kernel.CADDrawingDiagnostics {
            switch UInt32(nativeEntity.kind) {
            case SiteKeeperLibreDWGEntityKindRay.rawValue,
                 SiteKeeperLibreDWGEntityKindXLine.rawValue:
                return Kernel.CADDrawingDiagnostics(entries: [
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .info,
                        code: "CAD_POC_INFINITE_LINE_CLIPPED",
                        message: "DWG XLINE/RAY imported as a finite preview segment.",
                        detail: sourceHandle
                    )
                ])
            case SiteKeeperLibreDWGEntityKindLeader.rawValue:
                return Kernel.CADDrawingDiagnostics(entries: [
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .info,
                        code: "CAD_POC_LEADER_DEGRADED_TO_POLYLINE",
                        message: "DWG LEADER imported as a polyline.",
                        detail: sourceHandle
                    )
                ])
            case SiteKeeperLibreDWGEntityKindMLine.rawValue:
                return Kernel.CADDrawingDiagnostics(entries: [
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .info,
                        code: "CAD_POC_MLINE_DEGRADED_TO_CENTERLINE",
                        message: "DWG MLINE imported as its vertex centerline.",
                        detail: sourceHandle
                    )
                ])
            case SiteKeeperLibreDWGEntityKindHatch.rawValue:
                let canFill = nativeEntity.hatchFillMode == 1
                    && path.isClosedForImport
                    && path.points.count <= 64
                    && isConvexHatchPolygon(path.points)
                return Kernel.CADDrawingDiagnostics(entries: [
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: canFill ? .info : .warning,
                        code: canFill ? "CAD_POC_HATCH_SIMPLE_FILL" : "CAD_POC_HATCH_BOUNDARY_ONLY",
                        message: canFill
                            ? "DWG HATCH imported as a simple filled polygon."
                            : "DWG HATCH imported as boundary-only geometry to avoid expensive or inaccurate fill rendering.",
                        detail: sourceHandle
                    )
                ])
            case SiteKeeperLibreDWGEntityKindImage.rawValue,
                 SiteKeeperLibreDWGEntityKindUnderlay.rawValue:
                return Kernel.CADDrawingDiagnostics(entries: [
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_IMAGE_PLACEHOLDER",
                        message: "DWG IMAGE/UNDERLAY imported as a frame placeholder.",
                        detail: sourceHandle
                    )
                ])
            case SiteKeeperLibreDWGEntityKindWipeout.rawValue:
                return Kernel.CADDrawingDiagnostics(entries: [
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_WIPEOUT_DEGRADED_TO_BOUNDARY",
                        message: "DWG WIPEOUT imported as a boundary frame; masking is not implemented in this PoC.",
                        detail: sourceHandle
                    )
                ])
            default:
                return Kernel.CADDrawingDiagnostics()
            }
        }

        private func isConvexHatchPolygon(_ points: [Kernel.CADPoint]) -> Bool {
            guard points.count >= 3 else { return false }
            var sign = 0
            for index in points.indices {
                let previous = points[(index + points.count - 1) % points.count]
                let current = points[index]
                let next = points[(index + 1) % points.count]
                let cross = ((current.x - previous.x) * (next.y - current.y))
                    - ((current.y - previous.y) * (next.x - current.x))
                guard abs(cross) > 0.000001 else { continue }
                let currentSign = cross > 0 ? 1 : -1
                if sign == 0 {
                    sign = currentSign
                } else if sign != currentSign {
                    return false
                }
            }
            return sign != 0
        }

        private func nativeUnsupportedReason(for nativeKind: Int32) -> String? {
            switch UInt32(nativeKind) {
            case SiteKeeperLibreDWGEntityKindImage.rawValue:
                return "Image placeholder; raster image drawing is not implemented in the CAD Metal PoC."
            case SiteKeeperLibreDWGEntityKindUnderlay.rawValue:
                return "Underlay placeholder; referenced PDF/DWF/DGN drawing is not rendered in the CAD Metal PoC."
            case SiteKeeperLibreDWGEntityKindTianzhengProxy.rawValue:
                return "Tianzheng/TCH proxy object preserved as diagnostic metadata; custom object geometry is not decoded by the CAD Metal PoC."
            case SiteKeeperLibreDWGEntityKindProxy.rawValue:
                return "DWG proxy entity preserved as diagnostic metadata; proxy graphics are not decoded by the CAD Metal PoC."
            default:
                return nil
            }
        }

        private func nativeTextWidthFactor(_ nativeEntity: SiteKeeperLibreDWGEntity) -> Double {
            nativeEntity.textWidthFactor.isFinite && nativeEntity.textWidthFactor > 0
                ? nativeEntity.textWidthFactor
                : 1
        }

        private func nativeTextBounds(
            for text: Kernel.CADTextRun,
            insertion: Kernel.CADPoint,
            height: Double
        ) -> Kernel.CADBounds {
            let widthFactor = text.widthFactor ?? 1
            let measuredWidth = text.boxWidth.flatMap { $0 > 0 ? $0 : nil }
                ?? Double(text.displayText.count) * max(height * 0.6 * widthFactor, 0.6)
            let width = max(measuredWidth, max(height, 0.6))
            let boxHeight = max(text.boxHeight ?? height, height, 0.6)
            let anchorX = nativeHorizontalTextOffset(width: width, text: text)
            let anchorY = nativeVerticalTextOffset(height: boxHeight, text: text)
            return rotatedTextBounds(
                insertion: insertion,
                width: width,
                height: boxHeight,
                anchorX: anchorX,
                anchorY: anchorY,
                rotationRadians: text.rotationRadians
            )
        }

        private func rotatedTextBounds(
            insertion: Kernel.CADPoint,
            width: Double,
            height: Double,
            anchorX: Double,
            anchorY: Double,
            rotationRadians: Double
        ) -> Kernel.CADBounds {
            let cosine = cos(rotationRadians)
            let sine = sin(rotationRadians)
            let corners = [
                (0.0, 0.0),
                (width, 0.0),
                (width, height),
                (0.0, height)
            ].map { localX, localY in
                let x = localX - anchorX
                let y = localY - anchorY
                return Kernel.CADPoint(
                    x: insertion.x + x * cosine - y * sine,
                    y: insertion.y + x * sine + y * cosine
                )
            }
            return corners.reduce(Kernel.CADBounds.empty) { partial, point in
                partial.including(point)
            }
        }

        private func nativeHorizontalTextOffset(width: Double, text: Kernel.CADTextRun) -> Double {
            if text.boxWidth != nil, let alignmentCode = text.horizontalAlignmentCode {
                switch alignmentCode {
                case 2, 5, 8:
                    return width / 2
                case 3, 6, 9:
                    return width
                default:
                    return 0
                }
            }

            switch text.horizontalAlignmentCode {
            case 1, 3, 4, 5:
                return width / 2
            case 2:
                return width
            default:
                return 0
            }
        }

        private func nativeVerticalTextOffset(height: Double, text: Kernel.CADTextRun) -> Double {
            if text.boxHeight != nil, let alignmentCode = text.verticalAlignmentCode {
                switch alignmentCode {
                case 1, 2, 3:
                    return height
                case 4, 5, 6:
                    return height / 2
                default:
                    return 0
                }
            }

            switch text.verticalAlignmentCode {
            case 2:
                return height / 2
            case 3:
                return height
            default:
                return 0
            }
        }

        private func path(for nativeEntity: SiteKeeperLibreDWGEntity) -> Kernel.CADPath? {
            let pointCount = Int(nativeEntity.pointCount)
            guard pointCount >= 2, let rawPoints = nativeEntity.points else { return nil }

            let points = UnsafeBufferPointer(start: rawPoints, count: pointCount).map {
                Kernel.CADPoint(x: $0.x, y: $0.y)
            }
            guard points.count >= 2 else { return nil }

            var elements: [Kernel.CADPath.Element] = [.move(to: points[0])]
            elements.append(contentsOf: points.dropFirst().map { .line(to: $0) })
            if nativeEntity.isClosed != 0 {
                elements.append(.close)
            }
            return Kernel.CADPath(elements: elements)
        }

        private static func layerColors(from entities: [Kernel.CADEntity]) -> [String: UInt32] {
            var colors: [String: UInt32] = [:]
            for entity in entities where colors[entity.layerID] == nil {
                colors[entity.layerID] = entity.color
            }
            return colors
        }

        private func decodedNativeString(_ pointer: UnsafePointer<CChar>?) -> String? {
            guard let pointer else { return nil }
            let length = strlen(pointer)
            guard length > 0 else { return nil }

            let data = Data(bytes: pointer, count: length)
            for encoding in nativeTextEncodings {
                guard let decoded = String(data: data, encoding: encoding),
                      !decoded.containsUnicodeReplacementCharacter else {
                    continue
                }
                let trimmed = decoded.trimmingCharacters(in: .controlCharacters)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }

            let fallback = String(cString: pointer)
                .trimmingCharacters(in: .controlCharacters)
            return fallback.isEmpty ? nil : fallback
        }

        private func resolvedBigFontName(
            nativeBigFontName: String?,
            fontName: String?,
            styleName: String
        ) -> String? {
            if let mapped = mappedBigFontName(
                nativeBigFontName: nativeBigFontName,
                fontName: fontName,
                styleName: styleName
            ) {
                return mapped
            }
            if let preferred = bigFontName(forBridgeCode: preferredTextBigFont) {
                return preferred
            }
            return nativeBigFontName
        }

        private func mappedBigFontName(
            nativeBigFontName: String?,
            fontName: String?,
            styleName: String
        ) -> String? {
            for mapping in fontMappings where !mapping.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let pattern = mapping.pattern
                let candidate: String
                switch mapping.sourceKind {
                case "bigfont":
                    candidate = nativeBigFontName ?? ""
                case "font":
                    candidate = fontName ?? ""
                case "style":
                    candidate = styleName
                case "any":
                    candidate = [nativeBigFontName, fontName, styleName]
                        .compactMap { $0 }
                        .joined(separator: " ")
                default:
                    candidate = [nativeBigFontName, fontName, styleName]
                        .compactMap { $0 }
                        .joined(separator: " ")
                }
                guard candidate.localizedCaseInsensitiveContains(pattern),
                      let bigFont = bigFontName(forBridgeCode: mapping.bigFont) else {
                    continue
                }
                return bigFont
            }
            return nil
        }

        private func bigFontName(forBridgeCode bridgeCode: Int32?) -> String? {
            switch bridgeCode {
            case 1:
                return "gbcbig.shx"
            case 2:
                return "hztxt.shx"
            case 3:
                return "hzfs.shx"
            case 4:
                return "big5.shx"
            default:
                return nil
            }
        }

        private func applyPreferredDisplayFont(to text: Kernel.CADTextRun) -> Kernel.CADTextRun {
            guard let preferredDisplayFontName else { return text }
            var next = text
            next.selectedFontName = preferredDisplayFontName
            next.fontWasAvailable = true
            next.fallbackReason = "user-display-font"
            let warning = "CAD_TEXT_DISPLAY_FONT_OVERRIDE:\(preferredDisplayFontName)"
            if !next.warnings.contains(warning) {
                next.warnings.append(warning)
            }
            return next
        }

        private static let gb18030Encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )

        private static let gbkEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GBK_95.rawValue)
            )
        )

        private static let gb2312Encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue)
            )
        )

        private static let big5Encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue)
            )
        )

        private var nativeTextEncodings: [String.Encoding] {
            var encodings: [String.Encoding] = []
            if let preferred = preferredNativeTextEncoding {
                encodings.append(preferred)
            }
            encodings.append(contentsOf: [
                .utf8,
                Self.gb18030Encoding,
                Self.gbkEncoding,
                Self.gb2312Encoding,
                Self.big5Encoding,
                .isoLatin1
            ])
            var seen = Set<UInt>()
            return encodings.filter { encoding in
                seen.insert(encoding.rawValue).inserted
            }
        }

        private var preferredNativeTextEncoding: String.Encoding? {
            switch preferredTextCodePage {
            case 936:
                return Self.gbkEncoding
            case 54936:
                return Self.gb18030Encoding
            case 950:
                return Self.big5Encoding
            default:
                if preferredTextBigFont == 1
                    || preferredTextBigFont == 2
                    || preferredTextBigFont == 3 {
                    return Self.gb18030Encoding
                }
                if preferredTextBigFont == 4 {
                    return Self.big5Encoding
                }
                return nil
            }
        }

        private var textOptionCacheKey: String {
            var parts: [String] = []
            if let preferredTextCodePage {
                parts.append("cp\(preferredTextCodePage)")
            }
            if let preferredTextBigFont {
                parts.append("bf\(preferredTextBigFont)")
            }
            if !fontMappings.isEmpty {
                let mappingKey = fontMappings
                    .map { "\($0.sourceKind):\($0.pattern):\($0.bigFont)" }
                    .sorted()
                    .joined(separator: ",")
                    .stableCADImportHash
                parts.append("fm\(mappingKey)")
            }
            if let preferredDisplayFontName {
                parts.append("df\(preferredDisplayFontName.stableCADImportHash)")
            }
            return parts.joined(separator: "-")
        }

        private func importDXFGeometry(
            dxfFile: Kernel.CADFile,
            sourceFile: Kernel.CADFile,
            importSource: String,
            convertedFromDWG dxfURL: URL?
        ) throws -> CADImportResult {
            let data = try Data(contentsOf: dxfFile.url)
            let contents = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? String(decoding: data, as: UTF8.self)
            let parsed = DXFBasic2DParser.parse(contents)
            let records = parsed.records.map { applyingPreferredDisplayFont(to: $0) }
            let layerIDs = Set(records.map(\.layerID)).union(parsed.layersByID.keys)
            let layers = layerIDs.isEmpty
                ? [Kernel.CADLayer.default]
                : layerIDs.sorted().map { layerID in
                    parsed.layersByID[layerID] ?? Kernel.CADLayer(id: layerID, name: layerID)
                }
            let layerByID = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
            let entities = records.map { makeEntity(record: $0, layer: layerByID[$0.layerID]) }
            let textTrace = Self.textTraces(from: entities)
            let bounds = entities.reduce(Kernel.CADBounds.empty) { $0.union($1.bounds) }
            var diagnostics = records.isEmpty
                ? noDrawableDiagnostics(file: sourceFile)
                : Kernel.CADDrawingDiagnostics(entries: parsed.diagnostics)
            if let dxfURL {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .info,
                        code: "CAD_POC_DWG_CONVERTED_DXF_USED",
                        message: "The CAD Metal PoC used a LibreDWG-generated DXF artifact.",
                        detail: dxfURL.path
                    )
                )
            }
            diagnostics.append(
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_POC_TEXT_IMPORT_SUMMARY",
                    message: "CAD text import summary for LibreDWG native PoC.",
                    detail: Self.importedTextSummary(entities: entities, traces: textTrace)
                )
            )
            Self.appendTextDiagnostics(from: textTrace, to: &diagnostics)

            var database = Kernel.CADDatabase(
                file: sourceFile,
                extents: bounds,
                layers: layers,
                layouts: parsed.layouts.isEmpty ? [.modelSpace] : parsed.layouts,
                entities: entities,
                textStyles: parsed.textStylesByID.isEmpty
                    ? [.default]
                    : parsed.textStylesByID.values.sorted { $0.id < $1.id },
                diagnostics: diagnostics,
                importSource: importSource,
                textTrace: textTrace
            )
            let hasDrawableGeometry = entities.contains(where: \.isRenderable)
            database.setImportMetadata(
                geometryParsed: hasDrawableGeometry,
                isMetadataOnly: !hasDrawableGeometry,
                importSource: importSource
            )
            let layersByID = Dictionary(uniqueKeysWithValues: database.layers.map { ($0.id, $0) })
            let renderCommandCount = CADRenderPipeline()
                .commands(from: database.entities, layersByID: layersByID)
                .count

            let trace = CADOpenTrace(
                fileName: sourceFile.displayName,
                importSource: importSource,
                rawLineCount: records.filter { $0.kind == .line }.count,
                rawPolylineCount: records.filter { $0.kind == .lwPolyline || $0.kind == .polyline }.count,
                rawCircleCount: records.filter { $0.kind == .circle }.count,
                rawArcCount: records.filter { $0.kind == .arc }.count,
                rawEllipseCount: records.filter { $0.kind == .ellipse || $0.sourceType == "ELLIPSE" }.count,
                rawSplineCount: records.filter { $0.kind == .spline || $0.sourceType == "SPLINE" }.count,
                rawDimensionCount: records.filter { $0.kind == .dimension || $0.sourceType == "DIMENSION" }.count,
                rawHatchCount: records.filter { $0.sourceType == "HATCH" }.count,
                rawTextCount: records.filter { $0.kind == .text || $0.kind == .mtext || $0.kind == .attrib }.count,
                entityCount: database.entityCount,
                drawableEntityCount: database.drawableEntityCount,
                renderCommandCount: renderCommandCount,
                bounds: database.extents,
                openedForRender: database.drawableEntityCount > 0 && renderCommandCount > 0
            )
            return CADImportResult(database: database, trace: trace)
        }

        private func applyingPreferredDisplayFont(
            to record: DXFBasic2DParser.EntityRecord
        ) -> DXFBasic2DParser.EntityRecord {
            guard preferredDisplayFontName != nil else { return record }
            var next = record
            if let text = next.text {
                next.text = applyPreferredDisplayFont(to: text)
            }
            if !next.attachedAttributes.isEmpty {
                next.attachedAttributes = next.attachedAttributes.map { applyingPreferredDisplayFont(to: $0) }
            }
            return next
        }

        private func makeEntity(record: DXFBasic2DParser.EntityRecord, layer: Kernel.CADLayer?) -> Kernel.CADEntity {
            return Kernel.CADEntity(
                id: UUID(),
                kind: record.kind,
                layerID: record.layerID,
                layoutID: record.layoutID,
                color: record.colorARGB ?? layer?.colorARGB ?? 0xFF0A84FF,
                lineType: resolvedLineType(entityLineType: record.lineType, layer: layer),
                lineWeight: record.lineWeight ?? layer?.lineWeight ?? 2,
                path: record.path,
                text: record.text,
                bounds: record.bounds,
                visibility: record.visibility,
                sourceHandle: record.handle,
                diagnostics: Kernel.CADDrawingDiagnostics(entries: record.diagnostics),
                unsupportedReason: record.unsupportedReason
            )
        }

        private func resolvedLineType(entityLineType: String?, layer: Kernel.CADLayer?) -> String {
            let trimmed = entityLineType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty ||
                trimmed.caseInsensitiveCompare("ByLayer") == .orderedSame ||
                trimmed.caseInsensitiveCompare("ByBlock") == .orderedSame {
                return layer?.lineType ?? "Continuous"
            }
            return trimmed
        }

        private static func textTraces(from entities: [Kernel.CADEntity]) -> [Kernel.CADTextTrace] {
            entities.compactMap { entity in
                guard let text = entity.text else { return nil }
                return text.makeTrace(
                    entityId: entity.sourceHandle ?? entity.id.uuidString,
                    entityType: entity.kind
                )
            }
        }

        private static func importedTextSummary(
            entities: [Kernel.CADEntity],
            traces: [Kernel.CADTextTrace]
        ) -> String {
            let orderedKinds: [Kernel.CADEntityKind] = [.text, .mtext, .attrib, .dimension, .table]
            let counts = entities.reduce(into: [Kernel.CADEntityKind: Int]()) { partial, entity in
                guard entity.text != nil else { return }
                partial[entity.kind, default: 0] += 1
            }
            let countSummary = orderedKinds
                .map { "\($0.rawValue)=\(counts[$0, default: 0])" }
                .joined(separator: ",")
            let emptyDisplayCount = traces.filter {
                $0.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
            let replacementCount = traces.reduce(0) { partial, trace in
                partial + trace.displayText.unicodeScalars.filter { scalar in
                    scalar.value == 0xFFFD || scalar.value == 0x25A1 || scalar.value == 0x25A0
                }.count
            }
            let warningCount = traces.reduce(0) { $0 + $1.warnings.count }
            let firstCJK = traces.first {
                $0.displayText.cadContainsCJKScalars || $0.rawText.cadContainsCJKScalars
            }
            let sample = firstCJK ?? traces.first
            let sampleSummary = sample.map {
                "sampleType=\($0.entityType), raw=\(Self.compactDiagnosticText($0.rawText)), display=\(Self.compactDiagnosticText($0.displayText)), style=\($0.textStyleName), font=\($0.fontFile ?? "-"), bigFont=\($0.bigFontFile ?? "-")"
            } ?? "sample=-"
            return "cadTextCount=\(traces.count), kinds=\(countSummary), emptyDisplay=\(emptyDisplayCount), replacement=\(replacementCount), warnings=\(warningCount), \(sampleSummary)"
        }

        private static func compactDiagnosticText(_ value: String) -> String {
            let collapsed = value
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            guard collapsed.count > 24 else { return collapsed }
            return "\(collapsed.prefix(24))..."
        }

        private static func proxyTextCandidateSummary(entities: [Kernel.CADEntity]) -> String? {
            let proxyEntities = entities.filter { $0.kind == .proxy }
            let candidates = proxyEntities.compactMap { entity -> (entity: Kernel.CADEntity, preview: String)? in
                guard let preview = proxyTextCandidatePreview(from: entity.unsupportedReason) else {
                    return nil
                }
                return (entity, preview)
            }
            guard !candidates.isEmpty else {
                return nil
            }

            let tianzhengCount = candidates.filter { candidate in
                candidate.entity.unsupportedReason?.localizedCaseInsensitiveContains("Tianzheng") == true
                    || candidate.entity.unsupportedReason?.localizedCaseInsensitiveContains("TCH") == true
            }.count
            let finiteBoundsCount = candidates.filter { candidate in
                !CADSpatialIndex.effectiveBounds(for: candidate.entity).isEmpty
            }.count
            let sample = candidates
                .prefix(3)
                .map { candidate in
                    let handle = candidate.entity.sourceHandle.map { "#\($0)" } ?? ""
                    return "\(candidate.entity.layerID)\(handle):\(candidate.preview)"
                }
                .joined(separator: " | ")
            return "proxyTextCandidateCount=\(candidates.count), proxyEntityCount=\(proxyEntities.count), tianzhengTextCandidateCount=\(tianzhengCount), finiteBounds=\(finiteBoundsCount), sample=\(sample)"
        }

        private static func proxyTextCandidatePreview(from reason: String?) -> String? {
            guard let reason,
                  let range = reason.range(of: "textCandidate=", options: [.caseInsensitive]) else {
                return nil
            }
            let suffix = reason[range.upperBound...]
            let value = suffix
                .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init) ?? String(suffix)
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            return compactDiagnosticText(trimmed)
        }

        private static func appendTextDiagnostics(
            from traces: [Kernel.CADTextTrace],
            to diagnostics: inout Kernel.CADDrawingDiagnostics
        ) {
            var warningsByCode: [String: (count: Int, samples: [String])] = [:]
            for trace in traces {
                if !trace.fontWasAvailable {
                    appendTextWarning(
                        "CAD_TEXT_SELECTED_FONT_UNAVAILABLE:\(trace.selectedFontName)",
                        text: trace.displayText,
                        into: &warningsByCode
                    )
                }
                if let fallbackReason = trace.fallbackReason, !fallbackReason.isEmpty {
                    appendTextWarning(
                        "CAD_TEXT_FONT_FALLBACK_USED:\(fallbackReason)",
                        text: trace.displayText,
                        into: &warningsByCode
                    )
                }
                for warning in trace.warnings {
                    appendTextWarning(warning, text: trace.displayText, into: &warningsByCode)
                }
            }

            for code in warningsByCode.keys.sorted() {
                guard let bucket = warningsByCode[code] else { continue }
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        id: "\(code)-\(bucket.count)-\(bucket.samples.joined(separator: "|"))",
                        severity: .warning,
                        code: code,
                        message: textDiagnosticMessage(for: code),
                        detail: "count=\(bucket.count); samples=\(bucket.samples.joined(separator: ", "))"
                    )
                )
            }
        }

        private static func appendTextWarning(
            _ warning: String,
            text: String,
            into warningsByCode: inout [String: (count: Int, samples: [String])]
        ) {
            let parts = warning.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let code = parts.first.map(String.init) ?? warning
            var bucket = warningsByCode[code] ?? (count: 0, samples: [])
            bucket.count += 1
            let sample = parts.count > 1
                ? "\(parts[1])"
                : text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !sample.isEmpty, !bucket.samples.contains(sample), bucket.samples.count < 6 {
                bucket.samples.append(sample)
            }
            warningsByCode[code] = bucket
        }

        private static func textDiagnosticMessage(for code: String) -> String {
            switch code {
            case "CAD_TEXT_FONT_MISSING":
                return "A CAD text object did not specify a font; runtime fallback was used."
            case "CAD_TEXT_FONT_UNAVAILABLE":
                return "A requested CAD font is not available at runtime."
            case "CAD_TEXT_FONT_LACKS_GLYPHS":
                return "A requested runtime font exists but lacks glyphs for the CAD text."
            case "CAD_TEXT_BIGFONT_MISSING":
                return "A CJK CAD text object did not specify a BigFont."
            case "CAD_TEXT_BIGFONT_UNAVAILABLE":
                return "A requested CAD BigFont is not available at runtime."
            case "CAD_TEXT_SHX_SKIPPED_FOR_UNICODE":
                return "Unicode CJK text skipped the SHX pseudo-glyph path and used a runtime font."
            case "CAD_TEXT_SHX_MAPPED_TO_SYSTEM_FONT":
                return "An SHX font was mapped to a runtime system font for display."
            case "CAD_TEXT_BIGFONT_CIF_DECODED":
                return "CAD BigFont CIF text escapes were decoded for display."
            case "CAD_TEXT_BIGFONT_CIF_UNICODE_DECODED":
                return "CAD BigFont CIF Unicode text escapes were decoded for display."
            case "CAD_TEXT_INVALID_CIF_ESCAPE":
                return "CAD BigFont CIF text escapes could not be decoded."
            case "CAD_TEXT_FONT_FALLBACK_USED":
                return "CAD text used a fallback runtime font."
            case "CAD_TEXT_SELECTED_FONT_UNAVAILABLE":
                return "CAD text selected a font name that could not be created at runtime."
            default:
                return "CAD text import produced a text/font diagnostic."
            }
        }

        private func noDrawableDiagnostics(file: Kernel.CADFile) -> Kernel.CADDrawingDiagnostics {
            Kernel.CADDrawingDiagnostics(entries: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: "CAD_POC_NO_BASIC_2D_ENTITIES",
                    message: "The CAD Metal PoC imported no supported 2D CAD entities.",
                    detail: file.displayName
                )
            ])
        }
    }
}

enum DXFBasic2DParser {
    typealias Kernel = SiteKeeperCADKernel

    struct Pair {
        var code: Int
        var value: String
    }

    struct ParseResult {
        var records: [EntityRecord]
        var layersByID: [String: Kernel.CADLayer]
        var layouts: [Kernel.CADLayout]
        var textStylesByID: [String: Kernel.CADTextStyle]
        var diagnostics: [Kernel.CADDrawingDiagnostics.Entry]
    }

    struct BlockDefinition {
        var name: String
        var basePoint: Kernel.CADPoint
        var records: [EntityRecord]
        var isXref: Bool = false
        var xrefPath: String? = nil
    }

    struct EntityRecord {
        var kind: Kernel.CADEntityKind
        var layerID: String
        var handle: String?
        var path: Kernel.CADPath?
        var text: Kernel.CADTextRun?
        var bounds: Kernel.CADBounds
        var layoutID: String = Kernel.CADLayout.modelSpace.id
        var colorARGB: UInt32? = nil
        var lineWeight: Double? = nil
        var lineType: String? = nil
        var visibility: Kernel.CADVisibility = .visible
        var blockName: String? = nil
        var insertTransform: Kernel.CADTransform? = nil
        var insertColumnCount: Int = 1
        var insertRowCount: Int = 1
        var insertColumnSpacing: Double = 0
        var insertRowSpacing: Double = 0
        var attributeTag: String? = nil
        var sourceType: String? = nil
        var diagnostics: [Kernel.CADDrawingDiagnostics.Entry] = []
        var unsupportedReason: String? = nil
        var attachedAttributes: [EntityRecord] = []
    }

    struct PolylineVertex {
        var point: Kernel.CADPoint
        var bulge: Double
    }

}

private actor CADImportResultCache {
    static let shared = CADImportResultCache()

    private var memory: [String: CADPoC.CADImportResult] = [:]
    private let fileManager = FileManager.default
    private lazy var cacheDirectory: URL = {
        let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return root.appendingPathComponent("sitekeeper-cad-import-cache", isDirectory: true)
    }()

    func result(for file: SiteKeeperCADKernel.CADFile, engineID: String) -> CADPoC.CADImportResult? {
        let key = cacheKey(for: file, engineID: engineID)
        if let cached = memory[key] {
            return cached
        }

        let url = cacheURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode(CADPoC.CADImportResult.self, from: data) else {
            return nil
        }
        memory[key] = result
        return result
    }

    func store(_ result: CADPoC.CADImportResult, for file: SiteKeeperCADKernel.CADFile, engineID: String) {
        let key = cacheKey(for: file, engineID: engineID)
        memory[key] = result
        let url = cacheURL(for: key)
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(result)
            try data.write(to: url, options: [.atomic])
        } catch {
            CADPoC.CADDiagnosticLog.recordEncoded(
                category: "cad.importCache",
                message: "CAD import result cache store failed.",
                payload: [
                    "cachePath": url.path,
                    "error": error.localizedDescription
                ]
            )
        }
    }

    #if DEBUG
    func removeAllForTesting() {
        memory.removeAll()
        try? fileManager.removeItem(at: cacheDirectory)
    }
    #endif

    private func cacheURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent(Self.fnv1a64Hex(key), isDirectory: false)
            .appendingPathExtension("json")
    }

    private func cacheKey(for file: SiteKeeperCADKernel.CADFile, engineID: String) -> String {
        let path = file.url.standardizedFileURL.path
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        let byteCount = (attributes?[.size] as? NSNumber)?.int64Value ?? Int64(file.byteCount ?? -1)
        let modificationTime = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return [
            engineID,
            file.format.rawValue,
            path,
            "\(byteCount)",
            "\(Int64((modificationTime * 1000).rounded()))"
        ].joined(separator: "|")
    }

    private static func fnv1a64Hex(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

extension DXFBasic2DParser.EntityRecord {
    func applying(
        _ transform: SiteKeeperCADKernel.CADTransform,
        inheritedLayoutID: String?,
        inheritedLayerID: String?,
        inheritedColorARGB: UInt32? = nil,
        inheritedLineWeight: Double? = nil,
        inheritedLineType: String? = nil
    ) -> DXFBasic2DParser.EntityRecord {
        var copy = self
        if let inheritedLayoutID, copy.layoutID == SiteKeeperCADKernel.CADLayout.modelSpace.id {
            copy.layoutID = inheritedLayoutID
        }
        if let inheritedLayerID, copy.layerID == SiteKeeperCADKernel.CADLayer.default.id {
            copy.layerID = inheritedLayerID
        }
        if copy.colorARGB == nil {
            copy.colorARGB = inheritedColorARGB
        }
        if copy.lineWeight == nil {
            copy.lineWeight = inheritedLineWeight
        }
        let lineType = copy.lineType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if lineType.isEmpty || lineType.caseInsensitiveCompare("ByBlock") == .orderedSame {
            copy.lineType = inheritedLineType
        }
        if let path {
            let transformedPath = path.applying(transform)
            copy.path = transformedPath
            copy.bounds = transformedPath.bounds
        } else {
            copy.bounds = bounds.applying(transform)
        }

        if var text {
            text.insertionPoint = transform.apply(to: text.insertionPoint)
            text.height *= transform.approximateScale
            text.rotationRadians += DXFBasic2DParser.rotationRadians(from: transform)
            copy.text = text
            let transformedTextBounds = DXFBasic2DParser.textBounds(
                for: text,
                insertion: text.insertionPoint,
                height: text.height
            )
            copy.bounds = copy.path?.bounds.union(transformedTextBounds) ?? transformedTextBounds
        }
        return copy
    }
}

private extension SiteKeeperCADKernel.CADPath {
    var isClosedForImport: Bool {
        elements.contains {
            if case .close = $0 {
                return true
            }
            return false
        }
    }
}

private extension String {
    var containsUnicodeReplacementCharacter: Bool {
        unicodeScalars.contains { $0.value == 0xFFFD }
    }

    var cadContainsCJKScalars: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0x20000...0x2A6DF).contains(scalar.value)
                || (0x2A700...0x2B73F).contains(scalar.value)
                || (0x2B740...0x2B81F).contains(scalar.value)
                || (0x2B820...0x2CEAF).contains(scalar.value)
        }
    }

    var stableCADImportHash: String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
