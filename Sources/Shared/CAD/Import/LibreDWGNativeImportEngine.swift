import Foundation
import CoreFoundation

extension CADPoC {
    struct CADImportResult {
        var database: SiteKeeperCADKernel.CADDatabase
        var trace: CADOpenTrace
    }

    struct LibreDWGNativeImportEngine: SiteKeeperCADKernel.CADImportEngine {
        typealias Kernel = SiteKeeperCADKernel

        let id = "sitekeeper.poc.dwg-libredwg-ios.basic2d-v1"

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
            switch file.format {
            case .dxf:
                return try importDXFGeometry(
                    dxfFile: file,
                    sourceFile: file,
                    importSource: id,
                    convertedFromDWG: nil
                )
            case .dwg:
                return try importNativeDWGBasic2DGeometry(file: file)
            case .intermediateJSON, .unknown:
                throw Kernel.CADImportError.unsupportedFormat(file.format)
            }
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
            let expandedInsertEntityCount = Int(nativeResult.trace.exportedInsertEntityCount)
            let exportedDimensionCount = Int(nativeResult.trace.exportedDimensionCount)
            let exportedHatchCount = Int(nativeResult.trace.exportedHatchCount)
            let exportedEllipseCount = Int(nativeResult.trace.exportedEllipseCount)
            let exportedSplineCount = Int(nativeResult.trace.exportedSplineCount)
            let exportedFilledShapeCount = Int(nativeResult.trace.exportedFilledShapeCount)
            let rawEntityCount = Int(nativeResult.trace.rawEntityCount)
            let entityCount = Int(nativeResult.entityCount)
            let nativeEntities = UnsafeBufferPointer(
                start: nativeResult.entities,
                count: max(0, entityCount)
            )

            let entities: [Kernel.CADEntity] = nativeEntities.compactMap { nativeEntity in
                makeNativeEntity(nativeEntity)
            }

            var diagnostics = Kernel.CADDrawingDiagnostics()
            diagnostics.append(
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_POC_LIBREDWG_IOS_NATIVE_USED",
                    message: "LibreDWG was called inside the iOS process and converted basic 2D geometry into CADEntity.",
                    detail: "status=\(status), rawEntityCount=\(rawEntityCount), rawInsertCount=\(rawInsertCount), rawTextCount=\(rawTextCount), rawEllipseCount=\(rawEllipseCount), rawSplineCount=\(rawSplineCount), rawFilledShapeCount=\(rawFilledShapeCount), rawDimensionCount=\(rawDimensionCount), rawHatchCount=\(rawHatchCount), exportedEntityCount=\(entityCount), expandedInsertEntityCount=\(expandedInsertEntityCount), exportedEllipseCount=\(exportedEllipseCount), exportedSplineCount=\(exportedSplineCount), exportedFilledShapeCount=\(exportedFilledShapeCount), exportedDimensionCount=\(exportedDimensionCount), exportedHatchCount=\(exportedHatchCount)"
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
                        message: "Some DWG HATCH entities could not be degraded to boundary polylines by the native LibreDWG PoC importer.",
                        detail: "rawHatchCount=\(rawHatchCount), exportedHatchCount=\(exportedHatchCount)"
                    )
                )
            }
            if exportedHatchCount > 0 {
                diagnostics.append(
                    Kernel.CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_POC_LIBREDWG_HATCH_DEGRADED_TO_BOUNDARY",
                        message: "DWG HATCH entities were imported as boundary polylines.",
                        detail: "exportedHatchCount=\(exportedHatchCount)"
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

            var database = Kernel.CADDatabase(
                file: file,
                extents: bounds,
                layers: layers,
                layouts: [.modelSpace],
                entities: entities,
                diagnostics: diagnostics,
                importSource: id
            )
            let hasDrawableGeometry = entities.contains(where: \.isRenderable)
            database.setImportMetadata(
                geometryParsed: hasDrawableGeometry,
                isMetadataOnly: !hasDrawableGeometry,
                importSource: id
            )
            let renderCommandCount = CADRenderPipeline()
                .commands(from: database.entities)
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
                expandedInsertEntityCount: expandedInsertEntityCount,
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
            default:
                return nil
            }
        }

        private func makeNativeEntity(_ nativeEntity: SiteKeeperLibreDWGEntity) -> Kernel.CADEntity? {
            guard let kind = entityKind(for: nativeEntity.kind) else {
                return nil
            }
            let layerID = Self.decodedNativeString(nativeEntity.layerName) ?? Kernel.CADLayer.default.id
            let normalizedLayerID = layerID.isEmpty ? Kernel.CADLayer.default.id : layerID
            let sourceHandle = Self.decodedNativeString(nativeEntity.sourceHandle)

            switch kind {
            case .text, .mtext, .attrib:
                guard let rawTextPointer = nativeEntity.rawText else { return nil }
                let rawText = Self.decodedNativeString(rawTextPointer) ?? String(cString: rawTextPointer)
                let styleName = Self.decodedNativeString(nativeEntity.textStyleName) ?? Kernel.CADTextStyle.default.name
                let fontName = Self.decodedNativeString(nativeEntity.fontName)
                let bigFontName = Self.decodedNativeString(nativeEntity.bigFontName)
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
                    layoutID: Kernel.CADLayout.modelSpace.id,
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
                    let rawText = Self.decodedNativeString(rawTextPointer) ?? String(cString: rawTextPointer)
                    let styleName = Self.decodedNativeString(nativeEntity.textStyleName) ?? Kernel.CADTextStyle.default.name
                    let fontName = Self.decodedNativeString(nativeEntity.fontName)
                    let bigFontName = Self.decodedNativeString(nativeEntity.bigFontName)
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
                    layoutID: Kernel.CADLayout.modelSpace.id,
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
                    layoutID: Kernel.CADLayout.modelSpace.id,
                    color: nativeEntity.colorARGB,
                    lineType: "Continuous",
                    lineWeight: max(nativeEntity.lineWeight, 2),
                    path: path,
                    bounds: path.bounds,
                    sourceHandle: sourceHandle,
                    diagnostics: nativeDiagnostics(
                        for: nativeEntity.kind,
                        sourceHandle: sourceHandle
                    ),
                    unsupportedReason: nativeUnsupportedReason(for: nativeEntity.kind)
                )
            }
        }

        private func nativeDiagnostics(
            for nativeKind: Int32,
            sourceHandle: String?
        ) -> Kernel.CADDrawingDiagnostics {
            switch UInt32(nativeKind) {
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

        private func nativeUnsupportedReason(for nativeKind: Int32) -> String? {
            switch UInt32(nativeKind) {
            case SiteKeeperLibreDWGEntityKindImage.rawValue:
                return "Image placeholder; raster image drawing is not implemented in the CAD Metal PoC."
            case SiteKeeperLibreDWGEntityKindUnderlay.rawValue:
                return "Underlay placeholder; referenced PDF/DWF/DGN drawing is not rendered in the CAD Metal PoC."
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
            let minX = insertion.x - nativeHorizontalTextOffset(width: width, text: text)
            let minY = insertion.y - nativeVerticalTextOffset(height: boxHeight, text: text)
            return Kernel.CADBounds(
                minX: minX,
                minY: minY,
                maxX: minX + width,
                maxY: minY + boxHeight
            )
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

        private static func decodedNativeString(_ pointer: UnsafePointer<CChar>?) -> String? {
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

        private static var nativeTextEncodings: [String.Encoding] {
            [.utf8, gb18030Encoding, gbkEncoding, gb2312Encoding, .isoLatin1]
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

            var database = Kernel.CADDatabase(
                file: sourceFile,
                extents: bounds,
                layers: layers,
                layouts: [.modelSpace],
                entities: entities,
                diagnostics: diagnostics,
                importSource: importSource
            )
            let hasDrawableGeometry = entities.contains(where: \.isRenderable)
            database.setImportMetadata(
                geometryParsed: hasDrawableGeometry,
                isMetadataOnly: !hasDrawableGeometry,
                importSource: importSource
            )
            let renderCommandCount = CADRenderPipeline()
                .commands(from: database.entities)
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
                layoutID: Kernel.CADLayout.modelSpace.id,
                color: record.colorARGB ?? layer?.colorARGB ?? 0xFF0A84FF,
                lineType: "Continuous",
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
        var colorARGB: UInt32? = nil
        var lineWeight: Double? = nil
        var visibility: Kernel.CADVisibility = .visible
        var blockName: String? = nil
        var insertTransform: Kernel.CADTransform? = nil
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
        let layersByID = parseLayers(from: tablesSection(from: pairs))
        let blocksByName = parseBlocks(from: blocksSection(from: pairs))
        let entityPairs = entitiesSection(from: pairs)
        let rawRecords = parseEntityRecords(from: entityPairs)
        let records = expandInsertRecords(rawRecords, blocksByName: blocksByName)
        let diagnostics = records.flatMap(\.diagnostics)
        return ParseResult(records: records, layersByID: layersByID, diagnostics: diagnostics)
    }

    private static func parseEntityRecords(from entityPairs: [Pair]) -> [EntityRecord] {
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
            } else if type == "INSERT" {
                if var insert = makeInsert(from: recordPairs) {
                    insert.attachedAttributes = consumeInsertAttributes(from: entityPairs, index: &index)
                    record = insert
                } else {
                    record = nil
                }
            } else {
                record = makeEntity(type: type, pairs: recordPairs)
            }
            guard let record else { continue }
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

    private static func parseBlocks(from blockPairs: [Pair]) -> [String: BlockDefinition] {
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
                records: parseEntityRecords(from: bodyPairs),
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
            layers.append(
                Kernel.CADLayer(
                    id: name,
                    name: name,
                    isVisible: aci >= 0 && (flags & 1) == 0,
                    isLocked: (flags & 4) == 4,
                    colorARGB: color,
                    lineWeight: lineWeight(from: recordPairs) ?? 0.25
                )
            )
        }
        return layers
    }

    private static func makeEntity(type: String, pairs: [Pair]) -> EntityRecord? {
        switch type {
        case "LINE":
            return makeLine(from: pairs)
        case "POINT":
            return makePoint(from: pairs)
        case "XLINE", "RAY":
            return makeInfiniteLine(type: type, from: pairs)
        case "LWPOLYLINE":
            return makeLWPolyline(from: pairs)
        case "CIRCLE":
            return makeCircle(from: pairs)
        case "ARC":
            return makeArc(from: pairs)
        case "ELLIPSE":
            return makeEllipse(from: pairs)
        case "SPLINE":
            return makeSpline(from: pairs)
        case "DIMENSION":
            return makeDimension(from: pairs)
        case "TEXT", "MTEXT", "ATTRIB":
            return makeText(type: type, from: pairs)
        case "INSERT":
            return makeInsert(from: pairs)
        case "HATCH":
            return makeHatch(from: pairs)
        case "LEADER", "MLEADER":
            return makeLeader(type: type, from: pairs)
        case "MLINE":
            return makeMLine(from: pairs)
        case "SOLID", "TRACE", "3DFACE":
            return makeFilledShape(type: type, from: pairs)
        case "IMAGE", "PDFUNDERLAY", "DWFUNDERLAY", "DGNUNDERLAY", "UNDERLAY":
            return makeImagePlaceholder(type: type, from: pairs)
        case "WIPEOUT":
            return makeWipeout(from: pairs)
        default:
            return unsupportedRecord(
                type: type,
                pairs: pairs,
                code: "CAD_POC_DXF_UNSUPPORTED_ENTITY",
                reason: "\(type) is not supported by the CAD Metal PoC."
            )
        }
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

    private static func consumeInsertAttributes(from pairs: [Pair], index: inout Int) -> [EntityRecord] {
        var attributes: [EntityRecord] = []
        while index < pairs.count, pairs[index].code == 0 {
            let childType = normalized(pairs[index].value)
            if childType == "ATTRIB" {
                index += 1
                var childPairs: [Pair] = []
                while index < pairs.count, pairs[index].code != 0 {
                    childPairs.append(pairs[index])
                    index += 1
                }
                if let attribute = makeText(type: "ATTRIB", from: childPairs) {
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

    private static func makeDimension(from pairs: [Pair]) -> EntityRecord? {
        let endpoints = dimensionEndpoints(from: pairs)
        guard let endpoints else {
            return unsupportedRecord(
                type: "DIMENSION",
                pairs: pairs,
                code: "CAD_POC_DIMENSION_GEOMETRY_UNRESOLVED",
                reason: "DIMENSION geometry cannot be resolved by the CAD Metal PoC."
            )
        }

        let path = Kernel.CADPath(elements: [
            .move(to: endpoints.start),
            .line(to: endpoints.end)
        ])
        let textPoint = point(in: pairs, xCode: 11, yCode: 21)
            ?? midpoint(endpoints.start, endpoints.end)
        let height = positiveOrNil(firstDouble(code: 40, in: pairs))
            ?? positiveOrNil(firstDouble(code: 140, in: pairs))
            ?? 2.5
        let measurement = firstDouble(code: 42, in: pairs)
            ?? distance(from: endpoints.start, to: endpoints.end)
        let measurementText = formattedMeasurement(measurement)
        let rawText = dimensionDisplayText(from: pairs, measurementText: measurementText)
        let styleName = firstString(code: 7, in: pairs)
            ?? firstString(code: 3, in: pairs)
            ?? Kernel.CADTextStyle.default.id
        let style = Kernel.CADTextStyle(id: styleName, name: styleName)
        let textRotation = atan2(endpoints.end.y - endpoints.start.y, endpoints.end.x - endpoints.start.x)
        let text = Kernel.CADTextEngine().makeTextRun(
            rawText: rawText,
            insertionPoint: textPoint,
            style: style,
            height: height,
            rotationRadians: textRotation
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
                    message: "DIMENSION imported with a dimension line, arrowheads, aligned text, and simplified style for the CAD Metal PoC.",
                    detail: firstString(code: 5, in: pairs)
                ),
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_POC_DIMENSION_STYLE_SIMPLIFIED",
                    message: "DIMENSION style was simplified to text height and line color.",
                    detail: styleName
                )
            ]
        )
    }

    private static func makeText(type: String, from pairs: [Pair]) -> EntityRecord? {
        let rawText = joinedText(from: pairs, acceptedCodes: Set([1, 3]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return nil }

        let insertion = point(in: pairs, xCode: 10, yCode: 20) ?? .zero
        let styleName = firstString(code: 7, in: pairs) ?? Kernel.CADTextStyle.default.id
        let height = positiveOrNil(firstDouble(code: 40, in: pairs)) ?? 2.5
        let rotation = (firstDouble(code: 50, in: pairs) ?? 0) * .pi / 180
        let style = Kernel.CADTextStyle(id: styleName, name: styleName)
        let text = Kernel.CADTextEngine().makeTextRun(
            rawText: rawText,
            insertionPoint: insertion,
            style: style,
            height: height,
            rotationRadians: rotation
        )
        let bounds = textBounds(for: text, insertion: insertion, height: height)
        let kind: Kernel.CADEntityKind = type == "MTEXT" ? .mtext : (type == "ATTRIB" ? .attrib : .text)
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
            sourceType: type
        )
    }

    private static func makeInsert(from pairs: [Pair]) -> EntityRecord? {
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
            sourceType: "INSERT"
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
                    severity: .warning,
                    code: isComplexBoundary
                        ? "CAD_POC_HATCH_COMPLEX_BOUNDARY_DEGRADED"
                        : "CAD_POC_HATCH_DEGRADED_TO_BOUNDARY",
                    message: isComplexBoundary
                        ? "Complex HATCH imported as a filled outer boundary; inner loops and patterns are simplified."
                        : "HATCH imported as a filled boundary for the CAD Metal PoC.",
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
        let width = max(
            Double(text.displayText.count) * max(height * 0.6, 0.6),
            max(height, 0.6)
        )
        return Kernel.CADBounds(
            minX: insertion.x,
            minY: insertion.y,
            maxX: insertion.x + width,
            maxY: insertion.y + max(height, 0.6)
        )
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
        inheritedLayerID: String? = nil,
        inheritedColorARGB: UInt32? = nil,
        inheritedLineWeight: Double? = nil,
        activeBlocks: Set<String> = []
    ) -> [EntityRecord] {
        records.flatMap { record -> [EntityRecord] in
            if record.kind == .insert,
               let name = record.blockName,
               let block = blocksByName[name],
               !activeBlocks.contains(name) {
                let insertLayerID = record.layerID == Kernel.CADLayer.default.id
                    ? inheritedLayerID
                    : record.layerID
                let insertColorARGB = record.colorARGB ?? inheritedColorARGB
                let insertLineWeight = record.lineWeight ?? inheritedLineWeight
                let blockBaseTransform = Kernel.CADTransform.translation(
                    x: -block.basePoint.x,
                    y: -block.basePoint.y
                )
                let insertTransform = (record.insertTransform ?? .identity)
                    .concatenating(blockBaseTransform)
                let combinedTransform = transform.concatenating(insertTransform)
                if block.isXref {
                    return [
                        xrefRecord(
                            for: record,
                            block: block,
                            transform: combinedTransform,
                            inheritedLayerID: insertLayerID,
                            inheritedColorARGB: insertColorARGB,
                            inheritedLineWeight: insertLineWeight
                        )
                    ]
                }

                let expandedBlockRecords = expandInsertRecords(
                    block.records,
                    blocksByName: blocksByName,
                    transform: combinedTransform,
                    inheritedLayerID: insertLayerID,
                    inheritedColorARGB: insertColorARGB,
                    inheritedLineWeight: insertLineWeight,
                    activeBlocks: activeBlocks.union([name])
                )
                let expandedAttributes = record.attachedAttributes.map {
                    $0.applying(
                        combinedTransform,
                        inheritedLayerID: insertLayerID,
                        inheritedColorARGB: insertColorARGB,
                        inheritedLineWeight: insertLineWeight
                    )
                }
                return expandedBlockRecords + expandedAttributes
            }

            guard record.kind != .insert else { return [] }
            return [
                record.applying(
                    transform,
                    inheritedLayerID: inheritedLayerID,
                    inheritedColorARGB: inheritedColorARGB,
                    inheritedLineWeight: inheritedLineWeight
                )
            ]
        }
    }

    private static func xrefRecord(
        for insert: EntityRecord,
        block: BlockDefinition,
        transform: Kernel.CADTransform,
        inheritedLayerID: String?,
        inheritedColorARGB: UInt32?,
        inheritedLineWeight: Double?
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
            colorARGB: insert.colorARGB ?? inheritedColorARGB,
            lineWeight: insert.lineWeight ?? inheritedLineWeight,
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

    private static func layerID(from pairs: [Pair]) -> String {
        let layer = firstString(code: 8, in: pairs)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (layer?.isEmpty == false ? layer : nil) ?? Kernel.CADLayer.default.id
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

private extension DXFBasic2DParser.EntityRecord {
    func applying(
        _ transform: SiteKeeperCADKernel.CADTransform,
        inheritedLayerID: String?,
        inheritedColorARGB: UInt32? = nil,
        inheritedLineWeight: Double? = nil
    ) -> DXFBasic2DParser.EntityRecord {
        var copy = self
        if let inheritedLayerID, copy.layerID == SiteKeeperCADKernel.CADLayer.default.id {
            copy.layerID = inheritedLayerID
        }
        if copy.colorARGB == nil {
            copy.colorARGB = inheritedColorARGB
        }
        if copy.lineWeight == nil {
            copy.lineWeight = inheritedLineWeight
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
            copy.bounds = copy.bounds.union(bounds.applying(transform))
        }
        return copy
    }
}

private extension String {
    var containsUnicodeReplacementCharacter: Bool {
        unicodeScalars.contains { $0.value == 0xFFFD }
    }
}
