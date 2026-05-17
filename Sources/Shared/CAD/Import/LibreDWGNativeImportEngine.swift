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
        private let baseID = "sitekeeper.poc.dwg-libredwg-ios.basic2d-v2"
        var preferredTextCodePage: Int32?
        var preferredTextBigFont: Int32?
        var fontMappings: [CADRendererFontMapping]

        init(
            preferredTextCodePage: Int32? = nil,
            preferredTextBigFont: Int32? = nil,
            fontMappings: [CADRendererFontMapping] = []
        ) {
            self.preferredTextCodePage = preferredTextCodePage == 0 ? nil : preferredTextCodePage
            self.preferredTextBigFont = preferredTextBigFont == 0 ? nil : preferredTextBigFont
            self.fontMappings = fontMappings
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

            var diagnostics = Kernel.CADDrawingDiagnostics()
            diagnostics.append(
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_POC_LIBREDWG_IOS_NATIVE_USED",
                    message: "LibreDWG was called inside the iOS process and converted basic 2D geometry into CADEntity.",
                    detail: "status=\(status), rawEntityCount=\(rawEntityCount), rawInsertCount=\(rawInsertCount), rawTextCount=\(rawTextCount), rawEllipseCount=\(rawEllipseCount), rawSplineCount=\(rawSplineCount), rawFilledShapeCount=\(rawFilledShapeCount), rawDimensionCount=\(rawDimensionCount), rawHatchCount=\(rawHatchCount), rawProxyEntityCount=\(rawProxyEntityCount), rawTianzhengProxyCount=\(rawTianzhengProxyCount), exportedEntityCount=\(entityCount), expandedInsertEntityCount=\(expandedInsertEntityCount), exportedEllipseCount=\(exportedEllipseCount), exportedSplineCount=\(exportedSplineCount), exportedFilledShapeCount=\(exportedFilledShapeCount), exportedDimensionCount=\(exportedDimensionCount), exportedHatchCount=\(exportedHatchCount), exportedProxyEntityCount=\(exportedProxyEntityCount), exportedTianzhengProxyCount=\(exportedTianzhengProxyCount)"
                )
            )
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
                let text = Kernel.CADTextEngine().makeTextRun(
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
                    text = Kernel.CADTextEngine().makeTextRun(
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
            let records = parsed.records
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

private enum DXFBasic2DParser {
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

    private struct PolylineVertex {
        var point: Kernel.CADPoint
        var bulge: Double
    }

    static func parse(_ contents: String) -> ParseResult {
        let pairs = decodePairs(contents)
        let tablePairs = tablesSection(from: pairs)
        let layersByID = parseLayers(from: tablePairs)
        let textStylesByID = parseTextStyles(from: tablePairs)
        let blocksByName = parseBlocks(from: blocksSection(from: pairs), textStylesByID: textStylesByID)
        let entityPairs = entitiesSection(from: pairs)
        let rawRecords = parseEntityRecords(from: entityPairs, textStylesByID: textStylesByID)
        let records = expandInsertRecords(rawRecords, blocksByName: blocksByName)
        let diagnostics = records.flatMap(\.diagnostics)
        let layouts = buildLayouts(from: records)
        return ParseResult(
            records: records,
            layersByID: layersByID,
            layouts: layouts,
            textStylesByID: textStylesByID,
            diagnostics: diagnostics
        )
    }

    private static func parseEntityRecords(
        from entityPairs: [Pair],
        textStylesByID: [String: Kernel.CADTextStyle]
    ) -> [EntityRecord] {
        var records: [EntityRecord] = []
        var index = 0
        while index < entityPairs.count {
            let pair = entityPairs[index]
            guard pair.code == 0 else {
                index += 1
                continue
            }

            let type = pair.value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            index += 1
            var recordPairs: [Pair] = []
            while index < entityPairs.count, entityPairs[index].code != 0 {
                recordPairs.append(entityPairs[index])
                index += 1
            }

            let record: EntityRecord?
            if type == "POLYLINE" {
                let vertexPairs = consumePolylineVertices(from: entityPairs, index: &index)
                record = makePolyline(from: recordPairs, vertexPairs: vertexPairs)
            } else if type == "INSERT" || type == "MINSERT" {
                if var insert = makeInsert(type: type, from: recordPairs) {
                    insert.attachedAttributes = consumeInsertAttributes(
                        from: entityPairs,
                        index: &index,
                        textStylesByID: textStylesByID
                    )
                    record = insert
                } else {
                    record = nil
                }
            } else {
                record = makeEntity(type: type, pairs: recordPairs, textStylesByID: textStylesByID)
            }
            guard var record else { continue }
            record.lineType = lineType(from: recordPairs) ?? record.lineType
            record.layoutID = layoutID(from: recordPairs) ?? record.layoutID
            records.append(record)
        }
        return records
    }

    private static func decodePairs(_ contents: String) -> [Pair] {
        let lines = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var pairs: [Pair] = []
        var index = 0
        while index + 1 < lines.count {
            let codeText = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            if let code = Int(codeText) {
                pairs.append(Pair(code: code, value: value))
            }
            index += 2
        }
        return pairs
    }

    private static func tablesSection(from pairs: [Pair]) -> [Pair] {
        var index = 0
        while index < pairs.count {
            if pairs[index].code == 0,
               normalized(pairs[index].value) == "SECTION",
               index + 1 < pairs.count,
               pairs[index + 1].code == 2,
               normalized(pairs[index + 1].value) == "TABLES" {
                index += 2
                var section: [Pair] = []
                while index < pairs.count {
                    if pairs[index].code == 0, normalized(pairs[index].value) == "ENDSEC" {
                        break
                    }
                    section.append(pairs[index])
                    index += 1
                }
                return section
            }
            index += 1
        }
        return []
    }

    private static func blocksSection(from pairs: [Pair]) -> [Pair] {
        var index = 0
        while index < pairs.count {
            if pairs[index].code == 0,
               normalized(pairs[index].value) == "SECTION",
               index + 1 < pairs.count,
               pairs[index + 1].code == 2,
               normalized(pairs[index + 1].value) == "BLOCKS" {
                index += 2
                var section: [Pair] = []
                while index < pairs.count {
                    if pairs[index].code == 0, normalized(pairs[index].value) == "ENDSEC" {
                        break
                    }
                    section.append(pairs[index])
                    index += 1
                }
                return section
            }
            index += 1
        }
        return []
    }

    private static func entitiesSection(from pairs: [Pair]) -> [Pair] {
        var index = 0
        while index < pairs.count {
            if pairs[index].code == 0,
               normalized(pairs[index].value) == "SECTION",
               index + 1 < pairs.count,
               pairs[index + 1].code == 2,
               normalized(pairs[index + 1].value) == "ENTITIES" {
                index += 2
                var section: [Pair] = []
                while index < pairs.count {
                    if pairs[index].code == 0,
                       normalized(pairs[index].value) == "ENDSEC" {
                        break
                    }
                    section.append(pairs[index])
                    index += 1
                }
                return section
            }
            index += 1
        }
        return pairs
    }

    private static func parseBlocks(
        from blockPairs: [Pair],
        textStylesByID: [String: Kernel.CADTextStyle]
    ) -> [String: BlockDefinition] {
        var blocksByName: [String: BlockDefinition] = [:]
        var index = 0
        while index < blockPairs.count {
            guard blockPairs[index].code == 0, normalized(blockPairs[index].value) == "BLOCK" else {
                index += 1
                continue
            }

            index += 1
            var headerPairs: [Pair] = []
            while index < blockPairs.count, blockPairs[index].code != 0 {
                headerPairs.append(blockPairs[index])
                index += 1
            }

            var bodyPairs: [Pair] = []
            while index < blockPairs.count {
                if blockPairs[index].code == 0, normalized(blockPairs[index].value) == "ENDBLK" {
                    index += 1
                    while index < blockPairs.count, blockPairs[index].code != 0 {
                        index += 1
                    }
                    break
                }
                bodyPairs.append(blockPairs[index])
                index += 1
            }

            guard let name = blockName(from: headerPairs) else { continue }
            let base = point(in: headerPairs, xCode: 10, yCode: 20) ?? .zero
            let flags = firstInt(code: 70, in: headerPairs) ?? 0
            blocksByName[name] = BlockDefinition(
                name: name,
                basePoint: base,
                records: parseEntityRecords(from: bodyPairs, textStylesByID: textStylesByID),
                isXref: (flags & 4) == 4 || (flags & 8) == 8 || (flags & 16) == 16,
                xrefPath: firstString(code: 1, in: headerPairs)
            )
        }
        return blocksByName
    }

    private static func parseLayers(from tablePairs: [Pair]) -> [String: Kernel.CADLayer] {
        var layersByID: [String: Kernel.CADLayer] = [:]
        var index = 0
        while index < tablePairs.count {
            guard tablePairs[index].code == 0, normalized(tablePairs[index].value) == "TABLE" else {
                index += 1
                continue
            }
            index += 1
            let tableName = index < tablePairs.count && tablePairs[index].code == 2
                ? normalized(tablePairs[index].value)
                : ""
            if index < tablePairs.count, tablePairs[index].code == 2 {
                index += 1
            }

            var body: [Pair] = []
            while index < tablePairs.count {
                if tablePairs[index].code == 0, normalized(tablePairs[index].value) == "ENDTAB" {
                    break
                }
                body.append(tablePairs[index])
                index += 1
            }

            if tableName == "LAYER" {
                for layer in parseLayerRecords(from: body) {
                    layersByID[layer.id] = layer
                }
            }
            index += 1
        }
        return layersByID
    }

    private static func parseLayerRecords(from pairs: [Pair]) -> [Kernel.CADLayer] {
        var layers: [Kernel.CADLayer] = []
        var index = 0
        while index < pairs.count {
            guard pairs[index].code == 0, normalized(pairs[index].value) == "LAYER" else {
                index += 1
                continue
            }
            index += 1
            var recordPairs: [Pair] = []
            while index < pairs.count, pairs[index].code != 0 {
                recordPairs.append(pairs[index])
                index += 1
            }

            let name = firstString(code: 2, in: recordPairs)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty else { continue }

            let flags = firstInt(code: 70, in: recordPairs) ?? 0
            let aci = firstInt(code: 62, in: recordPairs) ?? 7
            let color = colorARGB(from: recordPairs, defaultACI: abs(aci)) ?? 0xFF2F3437
            let layerLineType = lineType(from: recordPairs) ?? "Continuous"
            layers.append(
                Kernel.CADLayer(
                    id: name,
                    name: name,
                    isVisible: aci >= 0 && (flags & 1) == 0,
                    isLocked: (flags & 4) == 4,
                    colorARGB: color,
                    lineWeight: lineWeight(from: recordPairs) ?? 0.25,
                    lineType: layerLineType
                )
            )
        }
        return layers
    }

    private static func parseTextStyles(from tablePairs: [Pair]) -> [String: Kernel.CADTextStyle] {
        var stylesByID: [String: Kernel.CADTextStyle] = [:]
        var index = 0
        while index < tablePairs.count {
            guard tablePairs[index].code == 0, normalized(tablePairs[index].value) == "TABLE" else {
                index += 1
                continue
            }
            index += 1
            let tableName = index < tablePairs.count && tablePairs[index].code == 2
                ? normalized(tablePairs[index].value)
                : ""
            if index < tablePairs.count, tablePairs[index].code == 2 {
                index += 1
            }

            var body: [Pair] = []
            while index < tablePairs.count {
                if tablePairs[index].code == 0, normalized(tablePairs[index].value) == "ENDTAB" {
                    break
                }
                body.append(tablePairs[index])
                index += 1
            }

            if tableName == "STYLE" {
                for style in parseTextStyleRecords(from: body) {
                    stylesByID[style.id] = style
                }
            }
            index += 1
        }
        return stylesByID
    }

    private static func parseTextStyleRecords(from pairs: [Pair]) -> [Kernel.CADTextStyle] {
        var styles: [Kernel.CADTextStyle] = []
        var index = 0
        while index < pairs.count {
            guard pairs[index].code == 0, normalized(pairs[index].value) == "STYLE" else {
                index += 1
                continue
            }
            index += 1
            var recordPairs: [Pair] = []
            while index < pairs.count, pairs[index].code != 0 {
                recordPairs.append(pairs[index])
                index += 1
            }

            let name = firstString(code: 2, in: recordPairs)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty else { continue }
            styles.append(
                Kernel.CADTextStyle(
                    id: name,
                    name: name,
                    fontName: firstString(code: 3, in: recordPairs)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    bigFontName: firstString(code: 4, in: recordPairs)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    fixedHeight: positiveOrNil(firstDouble(code: 40, in: recordPairs)),
                    widthFactor: positiveOrNil(firstDouble(code: 41, in: recordPairs)) ?? 1,
                    obliqueAngleRadians: (firstDouble(code: 50, in: recordPairs) ?? 0) * .pi / 180
                )
            )
        }
        return styles
    }

    private static func buildLayouts(from records: [EntityRecord]) -> [Kernel.CADLayout] {
        let layoutIDs = records
            .map(\.layoutID)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var seen = Set<String>()
        var layouts: [Kernel.CADLayout] = []
        for layoutID in [Kernel.CADLayout.modelSpace.id] + layoutIDs {
            let normalizedID = normalized(layoutID)
            guard seen.insert(normalizedID).inserted else { continue }
            if normalizedID == normalized(Kernel.CADLayout.modelSpace.id) {
                layouts.append(.modelSpace)
            } else {
                layouts.append(Kernel.CADLayout(id: layoutID, name: layoutID, isModelSpace: false))
            }
        }
        return layouts.isEmpty ? [.modelSpace] : layouts
    }

    private static func makeEntity(
        type: String,
        pairs: [Pair],
        textStylesByID: [String: Kernel.CADTextStyle]
    ) -> EntityRecord? {
        let record: EntityRecord?
        switch type {
        case "LINE":
            record = makeLine(from: pairs)
        case "POINT":
            record = makePoint(from: pairs)
        case "XLINE", "RAY":
            record = makeInfiniteLine(type: type, from: pairs)
        case "LWPOLYLINE":
            record = makeLWPolyline(from: pairs)
        case "CIRCLE":
            record = makeCircle(from: pairs)
        case "ARC":
            record = makeArc(from: pairs)
        case "ELLIPSE":
            record = makeEllipse(from: pairs)
        case "SPLINE":
            record = makeSpline(from: pairs)
        case "DIMENSION":
            record = makeDimension(from: pairs, textStylesByID: textStylesByID)
        case "TEXT", "MTEXT", "ATTRIB", "ATTDEF":
            record = makeText(type: type, from: pairs, textStylesByID: textStylesByID)
        case "INSERT", "MINSERT":
            record = makeInsert(type: type, from: pairs)
        case "HATCH":
            record = makeHatch(from: pairs)
        case "LEADER", "MLEADER":
            record = makeLeader(type: type, from: pairs)
        case "MLINE":
            record = makeMLine(from: pairs)
        case "SOLID", "TRACE", "3DFACE":
            record = makeFilledShape(type: type, from: pairs)
        case "IMAGE", "PDFUNDERLAY", "DWFUNDERLAY", "DGNUNDERLAY", "UNDERLAY":
            record = makeImagePlaceholder(type: type, from: pairs)
        case "WIPEOUT":
            record = makeWipeout(from: pairs)
        default:
            record = unsupportedRecord(
                type: type,
                pairs: pairs,
                code: "CAD_POC_DXF_UNSUPPORTED_ENTITY",
                reason: "\(type) is not supported by the CAD Metal PoC."
            )
        }
        guard var record else {
            return nil
        }
        record.lineType = lineType(from: pairs) ?? record.lineType
        return record
    }

    private static func consumePolylineVertices(from pairs: [Pair], index: inout Int) -> [[Pair]] {
        var vertexPairs: [[Pair]] = []
        while index < pairs.count, pairs[index].code == 0 {
            let childType = pairs[index].value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if childType == "VERTEX" {
                index += 1
                var childPairs: [Pair] = []
                while index < pairs.count, pairs[index].code != 0 {
                    childPairs.append(pairs[index])
                    index += 1
                }
                vertexPairs.append(childPairs)
                continue
            }
            if childType == "SEQEND" {
                index += 1
                while index < pairs.count, pairs[index].code != 0 {
                    index += 1
                }
                break
            }
            break
        }
        return vertexPairs
    }

    private static func consumeInsertAttributes(
        from pairs: [Pair],
        index: inout Int,
        textStylesByID: [String: Kernel.CADTextStyle]
    ) -> [EntityRecord] {
        var attributes: [EntityRecord] = []
        while index < pairs.count, pairs[index].code == 0 {
            let childType = normalized(pairs[index].value)
            if childType == "ATTRIB" || childType == "ATTDEF" {
                index += 1
                var childPairs: [Pair] = []
                while index < pairs.count, pairs[index].code != 0 {
                    childPairs.append(pairs[index])
                    index += 1
                }
                if var attribute = makeText(
                    type: childType,
                    from: childPairs,
                    textStylesByID: textStylesByID
                ) {
                    attribute.lineType = lineType(from: childPairs) ?? attribute.lineType
                    attribute.layoutID = layoutID(from: childPairs) ?? attribute.layoutID
                    attributes.append(attribute)
                }
                continue
            }
            if childType == "SEQEND" {
                index += 1
                while index < pairs.count, pairs[index].code != 0 {
                    index += 1
                }
                break
            }
            break
        }
        return attributes
    }

    private static func makeLine(from pairs: [Pair]) -> EntityRecord? {
        guard
            let startX = firstDouble(code: 10, in: pairs),
            let startY = firstDouble(code: 20, in: pairs),
            let endX = firstDouble(code: 11, in: pairs),
            let endY = firstDouble(code: 21, in: pairs)
        else {
            return nil
        }
        let path = Kernel.CADPath(elements: [
            .move(to: Kernel.CADPoint(x: startX, y: startY)),
            .line(to: Kernel.CADPoint(x: endX, y: endY))
        ])
        return EntityRecord(
            kind: .line,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: nil,
            bounds: path.bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: "LINE"
        )
    }

    private static func makePoint(from pairs: [Pair]) -> EntityRecord? {
        guard let point = point(in: pairs, xCode: 10, yCode: 20) else {
            return unsupportedRecord(
                type: "POINT",
                pairs: pairs,
                code: "CAD_POC_POINT_GEOMETRY_UNRESOLVED",
                reason: "POINT geometry cannot be resolved by the CAD Metal PoC."
            )
        }
        let bounds = Kernel.CADBounds(
            minX: point.x - 0.5,
            minY: point.y - 0.5,
            maxX: point.x + 0.5,
            maxY: point.y + 0.5
        )
        let path = Kernel.CADPath(elements: [
            .move(to: Kernel.CADPoint(x: point.x - 0.5, y: point.y)),
            .line(to: Kernel.CADPoint(x: point.x + 0.5, y: point.y))
        ])
        return EntityRecord(
            kind: .point,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: nil,
            bounds: bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: "POINT"
        )
    }

    private static func makeInfiniteLine(type: String, from pairs: [Pair]) -> EntityRecord? {
        guard let base = point(in: pairs, xCode: 10, yCode: 20),
              let direction = point(in: pairs, xCode: 11, yCode: 21) else {
            return unsupportedRecord(
                type: type,
                pairs: pairs,
                code: "CAD_POC_INFINITE_LINE_GEOMETRY_UNRESOLVED",
                reason: "\(type) geometry cannot be resolved by the CAD Metal PoC."
            )
        }
        let length = hypot(direction.x, direction.y)
        guard length > 0 else {
            return unsupportedRecord(
                type: type,
                pairs: pairs,
                code: "CAD_POC_INFINITE_LINE_GEOMETRY_UNRESOLVED",
                reason: "\(type) direction cannot be resolved by the CAD Metal PoC."
            )
        }
        let dx = direction.x / length
        let dy = direction.y / length
        let previewLength = 100_000.0
        let start: Kernel.CADPoint
        let end: Kernel.CADPoint
        if type == "XLINE" {
            start = Kernel.CADPoint(x: base.x - dx * previewLength, y: base.y - dy * previewLength)
            end = Kernel.CADPoint(x: base.x + dx * previewLength, y: base.y + dy * previewLength)
        } else {
            start = base
            end = Kernel.CADPoint(x: base.x + dx * previewLength, y: base.y + dy * previewLength)
        }
        let path = Kernel.CADPath(elements: [.move(to: start), .line(to: end)])
        return EntityRecord(
            kind: .line,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: nil,
            bounds: path.bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: type,
            diagnostics: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_POC_INFINITE_LINE_CLIPPED",
                    message: "\(type) imported as a finite preview segment.",
                    detail: firstString(code: 5, in: pairs)
                )
            ]
        )
    }

    private static func makeLWPolyline(from pairs: [Pair]) -> EntityRecord? {
        let vertices = orderedPolylineVertices(in: pairs, xCode: 10, yCode: 20, bulgeCode: 42)
        guard vertices.count >= 2 else { return nil }

        let isClosed = (firstInt(code: 70, in: pairs) ?? 0) & 1 == 1
        let points = tessellatedPolylinePoints(vertices: vertices, closed: isClosed)
        let path = makePath(from: points, closed: isClosed)
        let hasBulge = vertices.contains { abs($0.bulge) > 0.000001 }

        return EntityRecord(
            kind: .lwPolyline,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: nil,
            bounds: path.bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: "LWPOLYLINE",
            diagnostics: hasBulge ? [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_POC_LWPOLYLINE_BULGE_TESSELLATED",
                    message: "LWPOLYLINE bulge arcs were tessellated into polyline segments.",
                    detail: firstString(code: 5, in: pairs)
                )
            ] : []
        )
    }

    private static func makePolyline(from pairs: [Pair], vertexPairs: [[Pair]]) -> EntityRecord? {
        let vertices = vertexPairs.compactMap { pairs -> PolylineVertex? in
            guard let point = point(in: pairs, xCode: 10, yCode: 20) else { return nil }
            return PolylineVertex(point: point, bulge: firstDouble(code: 42, in: pairs) ?? 0)
        }
        guard vertices.count >= 2 else { return nil }

        let isClosed = (firstInt(code: 70, in: pairs) ?? 0) & 1 == 1
        let points = tessellatedPolylinePoints(vertices: vertices, closed: isClosed)
        let path = makePath(from: points, closed: isClosed)
        let hasBulge = vertices.contains { abs($0.bulge) > 0.000001 }
        return EntityRecord(
            kind: .polyline,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: nil,
            bounds: path.bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: "POLYLINE",
            diagnostics: hasBulge ? [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_POC_POLYLINE_BULGE_TESSELLATED",
                    message: "POLYLINE vertex bulge arcs were tessellated into polyline segments.",
                    detail: firstString(code: 5, in: pairs)
                )
            ] : []
        )
    }

    private static func makeCircle(from pairs: [Pair]) -> EntityRecord? {
        guard
            let center = point(in: pairs, xCode: 10, yCode: 20),
            let radius = firstDouble(code: 40, in: pairs),
            radius > 0
        else {
            return nil
        }
        let path = tessellatedArcPath(
            center: center,
            radius: radius,
            startDegrees: 0,
            endDegrees: 360,
            closed: true
        )
        return EntityRecord(
            kind: .circle,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: nil,
            bounds: path.bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: "CIRCLE"
        )
    }

    private static func makeArc(from pairs: [Pair]) -> EntityRecord? {
        guard
            let center = point(in: pairs, xCode: 10, yCode: 20),
            let radius = firstDouble(code: 40, in: pairs),
            let startDegrees = firstDouble(code: 50, in: pairs),
            let endDegrees = firstDouble(code: 51, in: pairs),
            radius > 0
        else {
            return nil
        }
        let path = tessellatedArcPath(
            center: center,
            radius: radius,
            startDegrees: startDegrees,
            endDegrees: endDegrees,
            closed: false
        )
        return EntityRecord(
            kind: .arc,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: nil,
            bounds: path.bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: "ARC"
        )
    }

    private static func makeEllipse(from pairs: [Pair]) -> EntityRecord? {
        guard
            let center = point(in: pairs, xCode: 10, yCode: 20),
            let majorVector = point(in: pairs, xCode: 11, yCode: 21)
        else {
            return unsupportedRecord(
                type: "ELLIPSE",
                pairs: pairs,
                code: "CAD_POC_ELLIPSE_GEOMETRY_UNRESOLVED",
                reason: "ELLIPSE geometry cannot be resolved by the CAD Metal PoC."
            )
        }

        let majorRadius = hypot(majorVector.x, majorVector.y)
        let ratio = positiveOrNil(firstDouble(code: 40, in: pairs)) ?? 1
        guard majorRadius > 0, ratio > 0 else {
            return unsupportedRecord(
                type: "ELLIPSE",
                pairs: pairs,
                code: "CAD_POC_ELLIPSE_GEOMETRY_UNRESOLVED",
                reason: "ELLIPSE geometry cannot be resolved by the CAD Metal PoC."
            )
        }

        let start = firstDouble(code: 41, in: pairs) ?? 0
        var end = firstDouble(code: 42, in: pairs) ?? (2 * Double.pi)
        while end < start {
            end += 2 * Double.pi
        }
        var sweep = end - start
        if sweep <= 0.000001 {
            sweep = 2 * Double.pi
        }

        let fullEllipse = abs(sweep - 2 * Double.pi) < 0.0001 || sweep >= 2 * Double.pi
        let rotation = atan2(majorVector.y, majorVector.x)
        let cosRotation = cos(rotation)
        let sinRotation = sin(rotation)
        let minorRadius = majorRadius * ratio
        let segmentCount = max(16, min(128, Int(ceil(abs(sweep) / (Double.pi / 32)))))
        let pointRange = fullEllipse ? 0..<segmentCount : 0..<(segmentCount + 1)
        let points = pointRange.map { index -> Kernel.CADPoint in
            let divisor = Double(max(segmentCount, 1))
            let parameter = start + sweep * Double(index) / divisor
            let localX = cos(parameter) * majorRadius
            let localY = sin(parameter) * minorRadius
            return Kernel.CADPoint(
                x: center.x + localX * cosRotation - localY * sinRotation,
                y: center.y + localX * sinRotation + localY * cosRotation
            )
        }
        let path = makePath(from: points, closed: fullEllipse)

        return EntityRecord(
            kind: .ellipse,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: nil,
            bounds: path.bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: "ELLIPSE",
            diagnostics: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_POC_ELLIPSE_TESSELLATED",
                    message: "ELLIPSE imported as tessellated polyline for the CAD Metal PoC.",
                    detail: firstString(code: 5, in: pairs)
                )
            ]
        )
    }

    private static func makeSpline(from pairs: [Pair]) -> EntityRecord? {
        var points = orderedPoints(in: pairs, xCode: 10, yCode: 20)
        if points.count < 2 {
            points = orderedPoints(in: pairs, xCode: 11, yCode: 21)
        }

        guard points.count >= 2 else {
            return unsupportedRecord(
                type: "SPLINE",
                pairs: pairs,
                code: "CAD_POC_SPLINE_POINTS_UNRESOLVED",
                reason: "SPLINE control points cannot be resolved by the CAD Metal PoC."
            )
        }

        let isClosed = (firstInt(code: 70, in: pairs) ?? 0) & 1 == 1
        let path = makePath(from: points, closed: isClosed)
        return EntityRecord(
            kind: .spline,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: nil,
            bounds: path.bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: "SPLINE",
            diagnostics: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: "CAD_POC_SPLINE_DEGRADED_TO_POLYLINE",
                    message: "SPLINE imported as control-point polyline for the CAD Metal PoC.",
                    detail: firstString(code: 5, in: pairs)
                )
            ]
        )
    }

    private static func makeDimension(
        from pairs: [Pair],
        textStylesByID: [String: Kernel.CADTextStyle]
    ) -> EntityRecord? {
        let endpoints = dimensionEndpoints(from: pairs)
        guard let endpoints else {
            return unsupportedRecord(
                type: "DIMENSION",
                pairs: pairs,
                code: "CAD_POC_DIMENSION_GEOMETRY_UNRESOLVED",
                reason: "DIMENSION geometry cannot be resolved by the CAD Metal PoC."
            )
        }

        let height = positiveOrNil(firstDouble(code: 40, in: pairs))
            ?? positiveOrNil(firstDouble(code: 140, in: pairs))
            ?? 2.5
        let explicitTextPoint = point(in: pairs, xCode: 11, yCode: 21)
        let dimensionLinePoint = point(in: pairs, xCode: 10, yCode: 20) ?? explicitTextPoint
        let explicitAxisAngle = firstDouble(code: 50, in: pairs).map { $0 * .pi / 180 }
        let geometry = dimensionGeometry(
            start: endpoints.start,
            end: endpoints.end,
            dimensionLinePoint: dimensionLinePoint,
            textPoint: explicitTextPoint,
            axisAngle: explicitAxisAngle,
            textHeight: height
        )
        let path = geometry.path
        let textPoint = explicitTextPoint ?? geometry.defaultTextPoint
        let measurement = firstDouble(code: 42, in: pairs)
            ?? distance(from: endpoints.start, to: endpoints.end)
        let measurementText = formattedMeasurement(measurement)
        let rawText = dimensionDisplayText(from: pairs, measurementText: measurementText)
        let styleName = firstString(code: 7, in: pairs)
            ?? firstString(code: 3, in: pairs)
            ?? Kernel.CADTextStyle.default.id
        let style = textStylesByID[styleName] ?? Kernel.CADTextStyle(id: styleName, name: styleName)
        let textRotation = explicitAxisAngle
            ?? atan2(geometry.dimensionEnd.y - geometry.dimensionStart.y, geometry.dimensionEnd.x - geometry.dimensionStart.x)
        let text = Kernel.CADTextEngine().makeTextRun(
            rawText: rawText,
            insertionPoint: textPoint,
            style: style,
            height: height,
            rotationRadians: textRotation,
            widthFactor: style.widthFactor,
            horizontalAlignmentCode: 1,
            verticalAlignmentCode: 2
        )
        let bounds = path.bounds.union(textBounds(for: text, insertion: textPoint, height: height))

        return EntityRecord(
            kind: .dimension,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: text,
            bounds: bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: "DIMENSION",
            diagnostics: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: "CAD_POC_DIMENSION_SIMPLIFIED",
                    message: "DIMENSION imported with extension lines, dimension line, arrowheads, positioned text, and simplified scale style for the CAD Metal PoC.",
                    detail: firstString(code: 5, in: pairs)
                ),
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_POC_DIMENSION_STYLE_SIMPLIFIED",
                    message: "DIMENSION style was simplified to text height, arrow scale, and line color.",
                    detail: styleName
                )
            ]
        )
    }

    private struct DimensionGeometry {
        var path: Kernel.CADPath
        var dimensionStart: Kernel.CADPoint
        var dimensionEnd: Kernel.CADPoint
        var defaultTextPoint: Kernel.CADPoint
    }

    private static func dimensionGeometry(
        start: Kernel.CADPoint,
        end: Kernel.CADPoint,
        dimensionLinePoint: Kernel.CADPoint?,
        textPoint: Kernel.CADPoint?,
        axisAngle: Double?,
        textHeight: Double
    ) -> DimensionGeometry {
        let measuredLength = distance(from: start, to: end)
        guard measuredLength > 0.000001 else {
            let path = Kernel.CADPath(elements: [.move(to: start), .line(to: end)])
            return DimensionGeometry(
                path: path,
                dimensionStart: start,
                dimensionEnd: end,
                defaultTextPoint: midpoint(start, end)
            )
        }

        let axis: Kernel.CADPoint
        if let axisAngle, axisAngle.isFinite {
            axis = Kernel.CADPoint(x: cos(axisAngle), y: sin(axisAngle))
        } else {
            axis = Kernel.CADPoint(
                x: (end.x - start.x) / measuredLength,
                y: (end.y - start.y) / measuredLength
            )
        }

        let reference = dimensionLinePoint ?? textPoint ?? midpoint(start, end)
        let dimensionStart = projectedPoint(start, ontoLineThrough: reference, axis: axis)
        let dimensionEnd = projectedPoint(end, ontoLineThrough: reference, axis: axis)
        let dimensionLength = distance(from: dimensionStart, to: dimensionEnd)
        guard dimensionLength > 0.000001 else {
            let path = Kernel.CADPath(elements: [.move(to: start), .line(to: end)])
            return DimensionGeometry(
                path: path,
                dimensionStart: start,
                dimensionEnd: end,
                defaultTextPoint: midpoint(start, end)
            )
        }

        let path = Kernel.CADPath(elements: [
            .move(to: start),
            .line(to: dimensionStart),
            .line(to: dimensionEnd),
            .line(to: end)
        ])
        let normal = Kernel.CADPoint(x: -axis.y, y: axis.x)
        let labelOffset = max(textHeight * 0.35, 0)
        let defaultTextPoint = Kernel.CADPoint(
            x: (dimensionStart.x + dimensionEnd.x) / 2 + normal.x * labelOffset,
            y: (dimensionStart.y + dimensionEnd.y) / 2 + normal.y * labelOffset
        )
        return DimensionGeometry(
            path: path,
            dimensionStart: dimensionStart,
            dimensionEnd: dimensionEnd,
            defaultTextPoint: defaultTextPoint
        )
    }

    private static func projectedPoint(
        _ point: Kernel.CADPoint,
        ontoLineThrough linePoint: Kernel.CADPoint,
        axis: Kernel.CADPoint
    ) -> Kernel.CADPoint {
        let dx = point.x - linePoint.x
        let dy = point.y - linePoint.y
        let distanceAlongAxis = dx * axis.x + dy * axis.y
        return Kernel.CADPoint(
            x: linePoint.x + axis.x * distanceAlongAxis,
            y: linePoint.y + axis.y * distanceAlongAxis
        )
    }

    private static func makeText(
        type: String,
        from pairs: [Pair],
        textStylesByID: [String: Kernel.CADTextStyle]
    ) -> EntityRecord? {
        let rawText = joinedText(from: pairs, acceptedCodes: Set([1, 3]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return nil }

        let insertion = point(in: pairs, xCode: 10, yCode: 20) ?? .zero
        let styleName = firstString(code: 7, in: pairs) ?? Kernel.CADTextStyle.default.id
        let style = textStylesByID[styleName] ?? Kernel.CADTextStyle(id: styleName, name: styleName)
        let height = positiveOrNil(firstDouble(code: 40, in: pairs)) ?? style.fixedHeight ?? 2.5
        let rotation = (firstDouble(code: 50, in: pairs) ?? 0) * .pi / 180
        let widthFactor = type == "MTEXT"
            ? style.widthFactor
            : positiveOrNil(firstDouble(code: 41, in: pairs)) ?? style.widthFactor
        let boxWidth = type == "MTEXT" ? positiveOrNil(firstDouble(code: 41, in: pairs)) : nil
        let boxHeight = type == "MTEXT" ? positiveOrNil(firstDouble(code: 46, in: pairs)) : nil
        let attachmentCode = firstInt(code: 71, in: pairs)
        let text = Kernel.CADTextEngine().makeTextRun(
            rawText: rawText,
            insertionPoint: insertion,
            style: style,
            height: height,
            rotationRadians: rotation,
            widthFactor: widthFactor,
            boxWidth: boxWidth,
            boxHeight: boxHeight,
            horizontalAlignmentCode: firstInt(code: 72, in: pairs) ?? attachmentCode,
            verticalAlignmentCode: firstInt(code: 73, in: pairs) ?? attachmentCode
        )
        let bounds = textBounds(for: text, insertion: insertion, height: height)
        let kind: Kernel.CADEntityKind = type == "MTEXT"
            ? .mtext
            : ((type == "ATTRIB" || type == "ATTDEF") ? .attrib : .text)
        return EntityRecord(
            kind: kind,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: nil,
            text: text,
            bounds: bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            attributeTag: attributeTag(type: type, pairs: pairs),
            sourceType: type
        )
    }

    private static func makeInsert(type: String, from pairs: [Pair]) -> EntityRecord? {
        guard let blockName = blockName(from: pairs) else { return nil }
        let insertion = point(in: pairs, xCode: 10, yCode: 20) ?? .zero
        let scaleX = firstDouble(code: 41, in: pairs) ?? 1
        let scaleY = firstDouble(code: 42, in: pairs) ?? 1
        let rotation = (firstDouble(code: 50, in: pairs) ?? 0) * .pi / 180
        let transform = Kernel.CADTransform
            .translation(x: insertion.x, y: insertion.y)
            .concatenating(.rotation(rotation))
            .concatenating(.scale(x: scaleX, y: scaleY))
        return EntityRecord(
            kind: .insert,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: nil,
            text: nil,
            bounds: .empty,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            blockName: blockName,
            insertTransform: transform,
            insertColumnCount: max(firstInt(code: 70, in: pairs) ?? 1, 1),
            insertRowCount: max(firstInt(code: 71, in: pairs) ?? 1, 1),
            insertColumnSpacing: firstDouble(code: 44, in: pairs) ?? 0,
            insertRowSpacing: firstDouble(code: 45, in: pairs) ?? 0,
            sourceType: type
        )
    }

    private static func makeHatch(from pairs: [Pair]) -> EntityRecord? {
        let boundary = orderedPoints(in: pairs, xCode: 10, yCode: 20)
        let boundaryPathCount = firstInt(code: 91, in: pairs) ?? 1
        let hasEdgeMetadata = pairs.contains { $0.code == 72 || $0.code == 92 || $0.code == 93 }
        let isComplexBoundary = boundaryPathCount > 1 || hasEdgeMetadata
        guard boundary.count >= 3 else {
            let reason = isComplexBoundary
                ? "Complex HATCH boundary cannot be resolved by the CAD Metal PoC."
                : "HATCH boundary cannot be resolved by the CAD Metal PoC."
            return EntityRecord(
                kind: .unsupported,
                layerID: layerID(from: pairs),
                handle: firstString(code: 5, in: pairs),
                path: nil,
                text: nil,
                bounds: .empty,
                colorARGB: colorARGB(from: pairs, defaultACI: nil),
                lineWeight: lineWeight(from: pairs),
                visibility: visibility(from: pairs),
                sourceType: "HATCH",
                diagnostics: [
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: isComplexBoundary
                            ? "CAD_POC_HATCH_COMPLEX_BOUNDARY_UNRESOLVED"
                            : "CAD_POC_HATCH_BOUNDARY_UNRESOLVED",
                        message: reason,
                        detail: firstString(code: 5, in: pairs)
                    )
                ],
                unsupportedReason: reason
            )
        }

        var elements: [Kernel.CADPath.Element] = [.move(to: boundary[0])]
        elements.append(contentsOf: boundary.dropFirst().map { .line(to: $0) })
        elements.append(.close)
        let path = Kernel.CADPath(elements: elements)
        return EntityRecord(
            kind: .hatch,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: nil,
            bounds: path.bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: "HATCH",
            diagnostics: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: isComplexBoundary ? .warning : .info,
                    code: isComplexBoundary
                        ? "CAD_POC_HATCH_COMPLEX_BOUNDARY_DEGRADED"
                        : "CAD_POC_HATCH_SIMPLE_FILL",
                    message: isComplexBoundary
                        ? "Complex HATCH imported as boundary-only geometry; inner loops and fill patterns are skipped to keep rendering responsive."
                        : "Simple closed HATCH imported as a filled polygon for the CAD Metal PoC.",
                    detail: firstString(code: 5, in: pairs)
                )
            ]
        )
    }

    private static func makeLeader(type: String, from pairs: [Pair]) -> EntityRecord? {
        let vertices = orderedPoints(in: pairs, xCode: 10, yCode: 20)
        guard vertices.count >= 2 else {
            return unsupportedRecord(
                type: type,
                pairs: pairs,
                code: "CAD_POC_LEADER_GEOMETRY_UNRESOLVED",
                reason: "\(type) vertices cannot be resolved by the CAD Metal PoC."
            )
        }
        let path = makePath(from: vertices, closed: false)
        return EntityRecord(
            kind: .polyline,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: nil,
            bounds: path.bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: type,
            diagnostics: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_POC_LEADER_DEGRADED_TO_POLYLINE",
                    message: "\(type) imported as a polyline.",
                    detail: firstString(code: 5, in: pairs)
                )
            ]
        )
    }

    private static func makeMLine(from pairs: [Pair]) -> EntityRecord? {
        let vertices = orderedPoints(in: pairs, xCode: 11, yCode: 21)
        guard vertices.count >= 2 else {
            return unsupportedRecord(
                type: "MLINE",
                pairs: pairs,
                code: "CAD_POC_MLINE_GEOMETRY_UNRESOLVED",
                reason: "MLINE vertices cannot be resolved by the CAD Metal PoC."
            )
        }
        let isClosed = (firstInt(code: 70, in: pairs) ?? 0) & 2 == 2
        let path = makePath(from: vertices, closed: isClosed)
        return EntityRecord(
            kind: .polyline,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: nil,
            bounds: path.bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: "MLINE",
            diagnostics: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_POC_MLINE_DEGRADED_TO_CENTERLINE",
                    message: "MLINE imported as its vertex centerline.",
                    detail: firstString(code: 5, in: pairs)
                )
            ]
        )
    }

    private static func makeFilledShape(type: String, from pairs: [Pair]) -> EntityRecord? {
        let pointCodes: [(Int, Int)] = [(10, 20), (11, 21), (12, 22), (13, 23)]
        let vertices = pointCodes.compactMap { point(in: pairs, xCode: $0.0, yCode: $0.1) }
        let uniqueVertices = vertices.reduce(into: [Kernel.CADPoint]()) { partial, point in
            guard !partial.contains(point) else { return }
            partial.append(point)
        }
        guard uniqueVertices.count >= 3 else {
            return unsupportedRecord(
                type: type,
                pairs: pairs,
                code: "CAD_POC_FILLED_SHAPE_GEOMETRY_UNRESOLVED",
                reason: "\(type) boundary cannot be resolved by the CAD Metal PoC."
            )
        }
        let path = makePath(from: uniqueVertices, closed: true)
        return EntityRecord(
            kind: .hatch,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: nil,
            bounds: path.bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: type,
            diagnostics: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: "CAD_POC_FILLED_SHAPE_DEGRADED_TO_BOUNDARY",
                    message: "\(type) imported as a closed boundary.",
                    detail: firstString(code: 5, in: pairs)
                )
            ]
        )
    }

    private static func makeImagePlaceholder(type: String, from pairs: [Pair]) -> EntityRecord? {
        let base = point(in: pairs, xCode: 10, yCode: 20) ?? .zero
        let uVector = point(in: pairs, xCode: 11, yCode: 21) ?? Kernel.CADPoint(x: 1, y: 0)
        let vVector = point(in: pairs, xCode: 12, yCode: 22) ?? Kernel.CADPoint(x: 0, y: 1)
        let width = positiveOrNil(firstDouble(code: 13, in: pairs)) ?? positiveOrNil(firstDouble(code: 41, in: pairs)) ?? 1
        let height = positiveOrNil(firstDouble(code: 23, in: pairs)) ?? positiveOrNil(firstDouble(code: 42, in: pairs)) ?? 1
        let points = [
            base,
            Kernel.CADPoint(x: base.x + uVector.x * width, y: base.y + uVector.y * width),
            Kernel.CADPoint(
                x: base.x + uVector.x * width + vVector.x * height,
                y: base.y + uVector.y * width + vVector.y * height
            ),
            Kernel.CADPoint(x: base.x + vVector.x * height, y: base.y + vVector.y * height)
        ]
        let path = makePath(from: points, closed: true)
        return EntityRecord(
            kind: .image,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: nil,
            bounds: path.bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: type,
            diagnostics: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: "CAD_POC_IMAGE_PLACEHOLDER",
                    message: "\(type) imported as a frame placeholder.",
                    detail: firstString(code: 5, in: pairs)
                )
            ],
            unsupportedReason: "\(type) placeholder; referenced image or underlay content is not rendered in the CAD Metal PoC."
        )
    }

    private static func makeWipeout(from pairs: [Pair]) -> EntityRecord? {
        let boundary = orderedPoints(in: pairs, xCode: 14, yCode: 24)
        if boundary.count >= 3 {
            let path = makePath(from: boundary, closed: true)
            return EntityRecord(
                kind: .hatch,
                layerID: layerID(from: pairs),
                handle: firstString(code: 5, in: pairs),
                path: path,
                text: nil,
                bounds: path.bounds,
                colorARGB: colorARGB(from: pairs, defaultACI: nil),
                lineWeight: lineWeight(from: pairs),
                visibility: visibility(from: pairs),
                sourceType: "WIPEOUT",
                diagnostics: [
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_WIPEOUT_DEGRADED_TO_BOUNDARY",
                        message: "WIPEOUT imported as a boundary frame; masking is not implemented in this PoC.",
                        detail: firstString(code: 5, in: pairs)
                    )
                ]
            )
        }
        return makeImagePlaceholder(type: "WIPEOUT", from: pairs)
    }

    private static func dimensionEndpoints(from pairs: [Pair]) -> (start: Kernel.CADPoint, end: Kernel.CADPoint)? {
        if let start = point(in: pairs, xCode: 13, yCode: 23),
           let end = point(in: pairs, xCode: 14, yCode: 24) {
            return (start, end)
        }
        if let start = point(in: pairs, xCode: 10, yCode: 20),
           let end = point(in: pairs, xCode: 11, yCode: 21),
           distance(from: start, to: end) > 0 {
            return (start, end)
        }
        return nil
    }

    private static func dimensionDisplayText(from pairs: [Pair], measurementText: String) -> String {
        let explicitText = firstString(code: 1, in: pairs)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let explicitText, !explicitText.isEmpty else {
            return measurementText
        }
        if explicitText == "<>" {
            return measurementText
        }
        return explicitText.replacingOccurrences(of: "<>", with: measurementText)
    }

    private static func textBounds(
        for text: Kernel.CADTextRun,
        insertion: Kernel.CADPoint,
        height: Double
    ) -> Kernel.CADBounds {
        let widthFactor = text.widthFactor ?? 1
        let measuredWidth = text.boxWidth.flatMap { $0 > 0 ? $0 : nil }
            ?? Double(text.displayText.count) * max(height * 0.6 * widthFactor, 0.6)
        let width = max(measuredWidth, max(height, 0.6))
        let boxHeight = max(text.boxHeight ?? height, height, 0.6)
        let anchorX = textHorizontalOffset(width: width, text: text)
        let anchorY = textVerticalOffset(height: boxHeight, text: text)
        return rotatedTextBounds(
            insertion: insertion,
            width: width,
            height: boxHeight,
            anchorX: anchorX,
            anchorY: anchorY,
            rotationRadians: text.rotationRadians
        )
    }

    private static func textHorizontalOffset(width: Double, text: Kernel.CADTextRun) -> Double {
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

    private static func textVerticalOffset(height: Double, text: Kernel.CADTextRun) -> Double {
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

    private static func rotatedTextBounds(
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

    private static func midpoint(_ first: Kernel.CADPoint, _ second: Kernel.CADPoint) -> Kernel.CADPoint {
        Kernel.CADPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }

    private static func distance(from start: Kernel.CADPoint, to end: Kernel.CADPoint) -> Double {
        hypot(end.x - start.x, end.y - start.y)
    }

    private static func formattedMeasurement(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if abs(rounded - rounded.rounded()) < 0.0001 {
            return String(Int(rounded.rounded()))
        }
        var text = String(format: "%.3f", rounded)
        while text.last == "0" {
            text.removeLast()
        }
        if text.last == "." {
            text.removeLast()
        }
        return text
    }

    private static func makePath(from points: [Kernel.CADPoint], closed: Bool) -> Kernel.CADPath {
        guard let first = points.first else { return Kernel.CADPath() }
        var elements: [Kernel.CADPath.Element] = [.move(to: first)]
        elements.append(contentsOf: points.dropFirst().map { .line(to: $0) })
        if closed {
            elements.append(.close)
        }
        return Kernel.CADPath(elements: elements)
    }

    private static func orderedPolylineVertices(
        in pairs: [Pair],
        xCode: Int,
        yCode: Int,
        bulgeCode: Int
    ) -> [PolylineVertex] {
        var vertices: [PolylineVertex] = []
        var index = 0
        while index < pairs.count {
            guard pairs[index].code == xCode,
                  let x = Double(pairs[index].value.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                index += 1
                continue
            }

            var y: Double?
            var bulge: Double = 0
            var cursor = index + 1
            while cursor < pairs.count, pairs[cursor].code != xCode {
                if pairs[cursor].code == yCode {
                    y = Double(pairs[cursor].value.trimmingCharacters(in: .whitespacesAndNewlines))
                } else if pairs[cursor].code == bulgeCode {
                    bulge = Double(pairs[cursor].value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                }
                cursor += 1
            }

            if let y {
                vertices.append(PolylineVertex(point: Kernel.CADPoint(x: x, y: y), bulge: bulge))
            }
            index += 1
        }
        return vertices
    }

    private static func tessellatedPolylinePoints(
        vertices: [PolylineVertex],
        closed: Bool
    ) -> [Kernel.CADPoint] {
        guard let first = vertices.first else { return [] }
        var points = [first.point]
        guard vertices.count >= 2 else { return points }

        for index in 0..<(vertices.count - 1) {
            appendBulgeSegment(
                from: vertices[index],
                to: vertices[index + 1].point,
                into: &points
            )
        }
        if closed, vertices.count > 2 {
            appendBulgeSegment(
                from: vertices[vertices.count - 1],
                to: first.point,
                into: &points
            )
        }
        return points
    }

    private static func appendBulgeSegment(
        from startVertex: PolylineVertex,
        to end: Kernel.CADPoint,
        into points: inout [Kernel.CADPoint]
    ) {
        let start = startVertex.point
        let bulge = startVertex.bulge
        guard abs(bulge) > 0.000001 else {
            appendDistinct(end, into: &points)
            return
        }

        let dx = end.x - start.x
        let dy = end.y - start.y
        let chord = hypot(dx, dy)
        guard chord.isFinite, chord > .ulpOfOne else {
            return
        }

        let theta = 4 * atan(bulge)
        let radius = chord * (1 + bulge * bulge) / (4 * abs(bulge))
        let centerOffset = chord * (1 - bulge * bulge) / (4 * bulge)
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        let normalX = -dy / chord
        let normalY = dx / chord
        let center = Kernel.CADPoint(
            x: midX + normalX * centerOffset,
            y: midY + normalY * centerOffset
        )
        guard radius.isFinite, radius > 0, center.x.isFinite, center.y.isFinite else {
            appendDistinct(end, into: &points)
            return
        }

        let startAngle = atan2(start.y - center.y, start.x - center.x)
        let endAngle = atan2(end.y - center.y, end.x - center.x)
        var sweep = endAngle - startAngle
        if theta > 0 {
            while sweep <= 0 {
                sweep += 2 * .pi
            }
        } else {
            while sweep >= 0 {
                sweep -= 2 * .pi
            }
        }

        let segmentCount = min(max(Int(ceil(abs(sweep) / (.pi / 24))), 4), 96)
        for index in 1...segmentCount {
            let t = Double(index) / Double(segmentCount)
            let angle = startAngle + sweep * t
            appendDistinct(
                Kernel.CADPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                ),
                into: &points
            )
        }
    }

    private static func appendDistinct(_ point: Kernel.CADPoint, into points: inout [Kernel.CADPoint]) {
        guard point.x.isFinite, point.y.isFinite else { return }
        if let previous = points.last,
           abs(previous.x - point.x) < 0.000001,
           abs(previous.y - point.y) < 0.000001 {
            return
        }
        points.append(point)
    }

    private static func unsupportedRecord(
        type: String,
        pairs: [Pair],
        code: String,
        reason: String
    ) -> EntityRecord {
        EntityRecord(
            kind: .unsupported,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: nil,
            text: nil,
            bounds: .empty,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: type,
            diagnostics: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: code,
                    message: reason,
                    detail: firstString(code: 5, in: pairs)
                )
            ],
            unsupportedReason: reason
        )
    }

    private static func tessellatedArcPath(
        center: Kernel.CADPoint,
        radius: Double,
        startDegrees: Double,
        endDegrees: Double,
        closed: Bool
    ) -> Kernel.CADPath {
        var resolvedEnd = endDegrees
        while resolvedEnd < startDegrees {
            resolvedEnd += 360
        }
        let sweep = max(resolvedEnd - startDegrees, 0.001)
        let segmentCount = max(8, min(96, Int(ceil(sweep / 8))))
        let points = (0...segmentCount).map { index -> Kernel.CADPoint in
            let t = Double(index) / Double(segmentCount)
            let degrees = startDegrees + sweep * t
            let radians = degrees * .pi / 180
            return Kernel.CADPoint(
                x: center.x + cos(radians) * radius,
                y: center.y + sin(radians) * radius
            )
        }
        guard let first = points.first else { return Kernel.CADPath() }
        var elements: [Kernel.CADPath.Element] = [.move(to: first)]
        elements.append(contentsOf: points.dropFirst().map { .line(to: $0) })
        if closed {
            elements.append(.close)
        }
        return Kernel.CADPath(elements: elements)
    }

    private static func expandInsertRecords(
        _ records: [EntityRecord],
        blocksByName: [String: BlockDefinition],
        transform: Kernel.CADTransform = .identity,
        inheritedLayoutID: String? = nil,
        inheritedLayerID: String? = nil,
        inheritedColorARGB: UInt32? = nil,
        inheritedLineWeight: Double? = nil,
        inheritedLineType: String? = nil,
        activeBlocks: Set<String> = []
    ) -> [EntityRecord] {
        records.flatMap { record -> [EntityRecord] in
            if record.kind == .insert {
                guard let name = record.blockName?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty else {
                    return [
                        unresolvedInsertRecord(
                            for: record,
                            transform: transform,
                            inheritedLayoutID: inheritedLayoutID,
                            inheritedLayerID: inheritedLayerID,
                            inheritedColorARGB: inheritedColorARGB,
                            inheritedLineWeight: inheritedLineWeight,
                            inheritedLineType: inheritedLineType,
                            code: "CAD_POC_INSERT_BLOCK_NAME_MISSING",
                            reason: "INSERT has no block name.",
                            detail: record.handle
                        )
                    ]
                }
                let normalizedBlockName = normalized(name)
                guard !activeBlocks.contains(normalizedBlockName) else {
                    return [
                        unresolvedInsertRecord(
                            for: record,
                            transform: transform,
                            inheritedLayoutID: inheritedLayoutID,
                            inheritedLayerID: inheritedLayerID,
                            inheritedColorARGB: inheritedColorARGB,
                            inheritedLineWeight: inheritedLineWeight,
                            inheritedLineType: inheritedLineType,
                            code: "CAD_POC_INSERT_BLOCK_CYCLE",
                            reason: "Nested block cycle detected.",
                            detail: (Array(activeBlocks) + [normalizedBlockName]).joined(separator: " -> ")
                        )
                    ]
                }
                guard let block = blockDefinition(named: name, in: blocksByName) else {
                    return [
                        unresolvedInsertRecord(
                            for: record,
                            transform: transform,
                            inheritedLayoutID: inheritedLayoutID,
                            inheritedLayerID: inheritedLayerID,
                            inheritedColorARGB: inheritedColorARGB,
                            inheritedLineWeight: inheritedLineWeight,
                            inheritedLineType: inheritedLineType,
                            code: "CAD_POC_INSERT_BLOCK_MISSING",
                            reason: "Referenced block is missing.",
                            detail: name
                        )
                    ]
                }
                let insertLayoutID = record.layoutID == Kernel.CADLayout.modelSpace.id
                    ? (inheritedLayoutID ?? record.layoutID)
                    : record.layoutID
                let insertLayerID = record.layerID == Kernel.CADLayer.default.id
                    ? inheritedLayerID
                    : record.layerID
                let insertColorARGB = record.colorARGB ?? inheritedColorARGB
                let insertLineWeight = record.lineWeight ?? inheritedLineWeight
                let insertLineType = resolvedInheritedLineType(
                    record.lineType,
                    inheritedLineType: inheritedLineType
                )
                let blockBaseTransform = Kernel.CADTransform.translation(
                    x: -block.basePoint.x,
                    y: -block.basePoint.y
                )
                let attachedAttributeTags = Set(record.attachedAttributes.compactMap {
                    $0.attributeTag.map(normalized)
                })
                let blockRecords = block.records.filter { blockRecord in
                    guard normalized(blockRecord.sourceType ?? "") == "ATTDEF",
                          let tag = blockRecord.attributeTag.map(normalized) else {
                        return true
                    }
                    return !attachedAttributeTags.contains(tag)
                }

                return insertArrayTransforms(for: record).flatMap { arrayTransform in
                    let insertTransform = arrayTransform.concatenating(blockBaseTransform)
                    let combinedTransform = transform.concatenating(insertTransform)
                    if block.isXref {
                        return [
                            xrefRecord(
                                for: record,
                                block: block,
                                transform: combinedTransform,
                                inheritedLayoutID: insertLayoutID,
                                inheritedLayerID: insertLayerID,
                                inheritedColorARGB: insertColorARGB,
                                inheritedLineWeight: insertLineWeight,
                                inheritedLineType: insertLineType
                            )
                        ]
                    }

                    let expandedBlockRecords = expandInsertRecords(
                        blockRecords,
                        blocksByName: blocksByName,
                        transform: combinedTransform,
                        inheritedLayoutID: insertLayoutID,
                        inheritedLayerID: insertLayerID,
                        inheritedColorARGB: insertColorARGB,
                        inheritedLineWeight: insertLineWeight,
                        inheritedLineType: insertLineType,
                        activeBlocks: activeBlocks.union([normalizedBlockName])
                    )
                    let expandedAttributes = record.attachedAttributes.map {
                        $0.applying(
                            combinedTransform,
                            inheritedLayoutID: insertLayoutID,
                            inheritedLayerID: insertLayerID,
                            inheritedColorARGB: insertColorARGB,
                            inheritedLineWeight: insertLineWeight,
                            inheritedLineType: insertLineType
                        )
                    }
                    return expandedBlockRecords + expandedAttributes
                }
            }

            guard record.kind != .insert else { return [] }
            return [
                record.applying(
                    transform,
                    inheritedLayoutID: inheritedLayoutID,
                    inheritedLayerID: inheritedLayerID,
                    inheritedColorARGB: inheritedColorARGB,
                    inheritedLineWeight: inheritedLineWeight,
                    inheritedLineType: inheritedLineType
                )
            ]
        }
    }

    private static func xrefRecord(
        for insert: EntityRecord,
        block: BlockDefinition,
        transform: Kernel.CADTransform,
        inheritedLayoutID: String?,
        inheritedLayerID: String?,
        inheritedColorARGB: UInt32?,
        inheritedLineWeight: Double?,
        inheritedLineType: String?
    ) -> EntityRecord {
        let anchor = transform.apply(to: .zero)
        let bounds = Kernel.CADBounds(
            minX: anchor.x - 0.5,
            minY: anchor.y - 0.5,
            maxX: anchor.x + 0.5,
            maxY: anchor.y + 0.5
        )
        let reason = "XREF \(block.name) is referenced but not loaded by the CAD Metal PoC."
        return EntityRecord(
            kind: .xref,
            layerID: insert.layerID == Kernel.CADLayer.default.id
                ? (inheritedLayerID ?? Kernel.CADLayer.default.id)
                : insert.layerID,
            handle: insert.handle,
            path: nil,
            text: nil,
            bounds: bounds,
            layoutID: insert.layoutID == Kernel.CADLayout.modelSpace.id
                ? (inheritedLayoutID ?? insert.layoutID)
                : insert.layoutID,
            colorARGB: insert.colorARGB ?? inheritedColorARGB,
            lineWeight: insert.lineWeight ?? inheritedLineWeight,
            lineType: resolvedInheritedLineType(insert.lineType, inheritedLineType: inheritedLineType),
            visibility: insert.visibility,
            sourceType: "XREF",
            diagnostics: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: "CAD_POC_XREF_NOT_LOADED",
                    message: reason,
                    detail: block.xrefPath ?? block.name
                )
            ],
            unsupportedReason: reason
        )
    }

    private static func resolvedInheritedLineType(
        _ lineType: String?,
        inheritedLineType: String?
    ) -> String? {
        let trimmed = lineType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.caseInsensitiveCompare("ByBlock") == .orderedSame || trimmed.isEmpty {
            return inheritedLineType
        }
        return trimmed
    }

    private static func blockDefinition(
        named name: String,
        in blocksByName: [String: BlockDefinition]
    ) -> BlockDefinition? {
        if let block = blocksByName[name] {
            return block
        }
        let normalizedName = normalized(name)
        return blocksByName.first { normalized($0.key) == normalizedName }?.value
    }

    private static func insertArrayTransforms(for record: EntityRecord) -> [Kernel.CADTransform] {
        let base = record.insertTransform ?? .identity
        let columnCount = max(record.insertColumnCount, 1)
        let rowCount = max(record.insertRowCount, 1)
        let maxExpandedInserts = 4_096
        let requestedCount = columnCount * rowCount
        let expandedCount = min(requestedCount, maxExpandedInserts)
        var transforms: [Kernel.CADTransform] = []
        transforms.reserveCapacity(expandedCount)

        for row in 0..<rowCount {
            for column in 0..<columnCount {
                if transforms.count >= maxExpandedInserts {
                    return transforms
                }
                let offset = Kernel.CADTransform.translation(
                    x: Double(column) * record.insertColumnSpacing,
                    y: Double(row) * record.insertRowSpacing
                )
                transforms.append(base.concatenating(offset))
            }
        }
        return transforms.isEmpty ? [base] : transforms
    }

    private static func unresolvedInsertRecord(
        for insert: EntityRecord,
        transform: Kernel.CADTransform,
        inheritedLayoutID: String?,
        inheritedLayerID: String?,
        inheritedColorARGB: UInt32?,
        inheritedLineWeight: Double?,
        inheritedLineType: String?,
        code: String,
        reason: String,
        detail: String?
    ) -> EntityRecord {
        let insertTransform = insert.insertTransform ?? .identity
        let combinedTransform = transform.concatenating(insertTransform)
        let anchor = combinedTransform.apply(to: .zero)
        let bounds = Kernel.CADBounds(
            minX: anchor.x - 0.5,
            minY: anchor.y - 0.5,
            maxX: anchor.x + 0.5,
            maxY: anchor.y + 0.5
        )
        return EntityRecord(
            kind: .unsupported,
            layerID: insert.layerID == Kernel.CADLayer.default.id
                ? (inheritedLayerID ?? Kernel.CADLayer.default.id)
                : insert.layerID,
            handle: insert.handle,
            path: nil,
            text: nil,
            bounds: bounds,
            layoutID: insert.layoutID == Kernel.CADLayout.modelSpace.id
                ? (inheritedLayoutID ?? insert.layoutID)
                : insert.layoutID,
            colorARGB: insert.colorARGB ?? inheritedColorARGB,
            lineWeight: insert.lineWeight ?? inheritedLineWeight,
            lineType: resolvedInheritedLineType(insert.lineType, inheritedLineType: inheritedLineType),
            visibility: insert.visibility,
            sourceType: insert.sourceType,
            diagnostics: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: code,
                    message: reason,
                    detail: detail
                )
            ],
            unsupportedReason: reason
        )
    }

    private static func rotationRadians(from transform: Kernel.CADTransform) -> Double {
        atan2(transform.matrix.b, transform.matrix.a)
    }

    private static func orderedPoints(in pairs: [Pair], xCode: Int, yCode: Int) -> [Kernel.CADPoint] {
        var points: [Kernel.CADPoint] = []
        var index = 0
        while index < pairs.count {
            guard pairs[index].code == xCode,
                  let x = Double(pairs[index].value.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                index += 1
                continue
            }

            var y: Double?
            var cursor = index + 1
            while cursor < pairs.count, pairs[cursor].code != xCode {
                if pairs[cursor].code == yCode {
                    y = Double(pairs[cursor].value.trimmingCharacters(in: .whitespacesAndNewlines))
                    break
                }
                cursor += 1
            }
            if let y {
                points.append(Kernel.CADPoint(x: x, y: y))
            }
            index += 1
        }
        return points
    }

    private static func point(in pairs: [Pair], xCode: Int, yCode: Int) -> Kernel.CADPoint? {
        guard let x = firstDouble(code: xCode, in: pairs),
              let y = firstDouble(code: yCode, in: pairs) else {
            return nil
        }
        return Kernel.CADPoint(x: x, y: y)
    }

    private static func firstInt(code: Int, in pairs: [Pair]) -> Int? {
        guard let value = pairs.first(where: { $0.code == code })?.value else { return nil }
        return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func firstDouble(code: Int, in pairs: [Pair]) -> Double? {
        guard let value = pairs.first(where: { $0.code == code })?.value else { return nil }
        return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func positiveOrNil(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func lineWeight(from pairs: [Pair]) -> Double? {
        guard let raw = firstInt(code: 370, in: pairs), raw >= 0 else { return nil }
        return Double(raw) / 100
    }

    private static func lineType(from pairs: [Pair]) -> String? {
        let value = firstString(code: 6, in: pairs)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func colorARGB(from pairs: [Pair], defaultACI: Int?) -> UInt32? {
        if let trueColor = firstInt(code: 420, in: pairs), trueColor > 0 {
            return 0xFF000000 | UInt32(trueColor & 0x00FF_FFFF)
        }
        if let aci = firstInt(code: 62, in: pairs) {
            if aci == 0 || abs(aci) == 256 {
                return nil
            }
            return aciToARGB(abs(aci))
        }
        if let defaultACI {
            return aciToARGB(abs(defaultACI))
        }
        return nil
    }

    private static func aciToARGB(_ index: Int) -> UInt32 {
        switch index {
        case 1:
            return 0xFFFF0000
        case 2:
            return 0xFFFFFF00
        case 3:
            return 0xFF00FF00
        case 4:
            return 0xFF00FFFF
        case 5:
            return 0xFF0000FF
        case 6:
            return 0xFFFF00FF
        case 7:
            return 0xFF2F3437
        case 8:
            return 0xFF808080
        case 9:
            return 0xFFC0C0C0
        default:
            let normalized = Double((index - 1) % 24) / 24
            let hue = normalized * 6
            let c = 1.0
            let x = c * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
            let rgb: (Double, Double, Double)
            switch hue {
            case 0..<1: rgb = (c, x, 0)
            case 1..<2: rgb = (x, c, 0)
            case 2..<3: rgb = (0, c, x)
            case 3..<4: rgb = (0, x, c)
            case 4..<5: rgb = (x, 0, c)
            default: rgb = (c, 0, x)
            }
            let r = UInt32(max(0, min(255, Int(rgb.0 * 255))))
            let g = UInt32(max(0, min(255, Int(rgb.1 * 255))))
            let b = UInt32(max(0, min(255, Int(rgb.2 * 255))))
            return 0xFF000000 | (r << 16) | (g << 8) | b
        }
    }

    private static func visibility(from pairs: [Pair]) -> Kernel.CADVisibility {
        if (firstInt(code: 60, in: pairs) ?? 0) == 1 {
            return .hidden
        }
        if let aci = firstInt(code: 62, in: pairs), aci < 0 {
            return .hidden
        }
        return .visible
    }

    private static func firstString(code: Int, in pairs: [Pair]) -> String? {
        pairs.first(where: { $0.code == code })?.value
    }

    private static func joinedText(from pairs: [Pair], acceptedCodes: Set<Int>) -> String {
        pairs
            .filter { acceptedCodes.contains($0.code) }
            .map(\.value)
            .joined()
    }

    private static func attributeTag(type: String, pairs: [Pair]) -> String? {
        guard type == "ATTRIB" || type == "ATTDEF" else { return nil }
        let value = firstString(code: 2, in: pairs)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private static func layerID(from pairs: [Pair]) -> String {
        let layer = firstString(code: 8, in: pairs)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (layer?.isEmpty == false ? layer : nil) ?? Kernel.CADLayer.default.id
    }

    private static func layoutID(from pairs: [Pair]) -> String? {
        if let layoutName = firstString(code: 410, in: pairs)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !layoutName.isEmpty {
            return normalized(layoutName) == "MODEL" ? Kernel.CADLayout.modelSpace.id : layoutName
        }
        if (firstInt(code: 67, in: pairs) ?? 0) == 1 {
            return "paper"
        }
        return nil
    }

    private static func blockName(from pairs: [Pair]) -> String? {
        let name = (firstString(code: 2, in: pairs) ?? firstString(code: 3, in: pairs))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
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
            #if DEBUG
            print("CADImportResultCache store failed: \(error)")
            #endif
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

private extension DXFBasic2DParser.EntityRecord {
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

    var stableCADImportHash: String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
