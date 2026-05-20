import Foundation

extension DXFBasic2DParser {
    static func makeEntities(
        type: String,
        pairs: [Pair],
        textStylesByID: [String: Kernel.CADTextStyle]
    ) -> [EntityRecord] {
        if type == "TABLE" {
            return makeTableCellTexts(from: pairs, textStylesByID: textStylesByID)
        }
        guard let record = makeEntity(type: type, pairs: pairs, textStylesByID: textStylesByID) else {
            return []
        }
        return [record]
    }


    static func makeEntity(
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
        case "LEADER", "MLEADER", "MULTILEADER":
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
                code: "CAD_NATIVE_DXF_UNSUPPORTED_ENTITY",
                reason: "\(type) is not supported by the Native CAD Renderer."
            )
        }
        guard var record else {
            return nil
        }
        record.lineType = lineType(from: pairs) ?? record.lineType
        return record
    }


    static func makeLine(from pairs: [Pair]) -> EntityRecord? {
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


    static func makePoint(from pairs: [Pair]) -> EntityRecord? {
        guard let point = point(in: pairs, xCode: 10, yCode: 20) else {
            return unsupportedRecord(
                type: "POINT",
                pairs: pairs,
                code: "CAD_NATIVE_POINT_GEOMETRY_UNRESOLVED",
                reason: "POINT geometry cannot be resolved by the Native CAD Renderer."
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


    static func makeInfiniteLine(type: String, from pairs: [Pair]) -> EntityRecord? {
        guard let base = point(in: pairs, xCode: 10, yCode: 20),
              let direction = point(in: pairs, xCode: 11, yCode: 21) else {
            return unsupportedRecord(
                type: type,
                pairs: pairs,
                code: "CAD_NATIVE_INFINITE_LINE_GEOMETRY_UNRESOLVED",
                reason: "\(type) geometry cannot be resolved by the Native CAD Renderer."
            )
        }
        let length = hypot(direction.x, direction.y)
        guard length > 0 else {
            return unsupportedRecord(
                type: type,
                pairs: pairs,
                code: "CAD_NATIVE_INFINITE_LINE_GEOMETRY_UNRESOLVED",
                reason: "\(type) direction cannot be resolved by the Native CAD Renderer."
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
                    code: "CAD_NATIVE_INFINITE_LINE_CLIPPED",
                    message: "\(type) imported as a finite preview segment.",
                    detail: firstString(code: 5, in: pairs)
                )
            ]
        )
    }


    static func makeLWPolyline(from pairs: [Pair]) -> EntityRecord? {
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
                    code: "CAD_NATIVE_LWPOLYLINE_BULGE_TESSELLATED",
                    message: "LWPOLYLINE bulge arcs were tessellated into polyline segments.",
                    detail: firstString(code: 5, in: pairs)
                )
            ] : []
        )
    }


    static func makePolyline(from pairs: [Pair], vertexPairs: [[Pair]]) -> EntityRecord? {
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
                    code: "CAD_NATIVE_POLYLINE_BULGE_TESSELLATED",
                    message: "POLYLINE vertex bulge arcs were tessellated into polyline segments.",
                    detail: firstString(code: 5, in: pairs)
                )
            ] : []
        )
    }


    static func makeCircle(from pairs: [Pair]) -> EntityRecord? {
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


    static func makeArc(from pairs: [Pair]) -> EntityRecord? {
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


    static func makeEllipse(from pairs: [Pair]) -> EntityRecord? {
        guard
            let center = point(in: pairs, xCode: 10, yCode: 20),
            let majorVector = point(in: pairs, xCode: 11, yCode: 21)
        else {
            return unsupportedRecord(
                type: "ELLIPSE",
                pairs: pairs,
                code: "CAD_NATIVE_ELLIPSE_GEOMETRY_UNRESOLVED",
                reason: "ELLIPSE geometry cannot be resolved by the Native CAD Renderer."
            )
        }

        let majorRadius = hypot(majorVector.x, majorVector.y)
        let ratio = positiveOrNil(firstDouble(code: 40, in: pairs)) ?? 1
        guard majorRadius > 0, ratio > 0 else {
            return unsupportedRecord(
                type: "ELLIPSE",
                pairs: pairs,
                code: "CAD_NATIVE_ELLIPSE_GEOMETRY_UNRESOLVED",
                reason: "ELLIPSE geometry cannot be resolved by the Native CAD Renderer."
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
                    code: "CAD_NATIVE_ELLIPSE_TESSELLATED",
                    message: "ELLIPSE imported as tessellated polyline for the Native CAD Renderer.",
                    detail: firstString(code: 5, in: pairs)
                )
            ]
        )
    }


    static func makeSpline(from pairs: [Pair]) -> EntityRecord? {
        var points = orderedPoints(in: pairs, xCode: 10, yCode: 20)
        if points.count < 2 {
            points = orderedPoints(in: pairs, xCode: 11, yCode: 21)
        }

        guard points.count >= 2 else {
            return unsupportedRecord(
                type: "SPLINE",
                pairs: pairs,
                code: "CAD_NATIVE_SPLINE_POINTS_UNRESOLVED",
                reason: "SPLINE control points cannot be resolved by the Native CAD Renderer."
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
                    code: "CAD_NATIVE_SPLINE_DEGRADED_TO_POLYLINE",
                    message: "SPLINE imported as control-point polyline for the Native CAD Renderer.",
                    detail: firstString(code: 5, in: pairs)
                )
            ]
        )
    }


    static func makeDimension(
        from pairs: [Pair],
        textStylesByID: [String: Kernel.CADTextStyle]
    ) -> EntityRecord? {
        let endpoints = dimensionEndpoints(from: pairs)
        guard let endpoints else {
            return unsupportedRecord(
                type: "DIMENSION",
                pairs: pairs,
                code: "CAD_NATIVE_DIMENSION_GEOMETRY_UNRESOLVED",
                reason: "DIMENSION geometry cannot be resolved by the Native CAD Renderer."
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
                    code: "CAD_NATIVE_DIMENSION_SIMPLIFIED",
                    message: "DIMENSION imported with extension lines, dimension line, arrowheads, positioned text, and simplified scale style for the Native CAD Renderer.",
                    detail: firstString(code: 5, in: pairs)
                ),
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_NATIVE_DIMENSION_STYLE_SIMPLIFIED",
                    message: "DIMENSION style was simplified to text height, arrow scale, and line color.",
                    detail: styleName
                )
            ]
        )
    }

    struct DimensionGeometry {
        var path: Kernel.CADPath
        var dimensionStart: Kernel.CADPoint
        var dimensionEnd: Kernel.CADPoint
        var defaultTextPoint: Kernel.CADPoint
    }


    static func makeText(
        type: String,
        from pairs: [Pair],
        textStylesByID: [String: Kernel.CADTextStyle]
    ) -> EntityRecord? {
        let rawText = joinedText(from: pairs, acceptedCodes: Set([1, 3]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return nil }

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
        let horizontalAlignmentCode: Int?
        let verticalAlignmentCode: Int?
        if type == "MTEXT" {
            // MTEXT group code 71 is the attachment point. Codes 72/73 are
            // drawing direction and line-spacing style, not text alignment.
            horizontalAlignmentCode = attachmentCode
            verticalAlignmentCode = attachmentCode
        } else {
            horizontalAlignmentCode = firstInt(code: 72, in: pairs)
            verticalAlignmentCode = firstInt(code: 73, in: pairs)
        }
        let insertion = textAnchorPoint(
            type: type,
            pairs: pairs,
            horizontalAlignmentCode: horizontalAlignmentCode,
            verticalAlignmentCode: verticalAlignmentCode
        )
        let text = Kernel.CADTextEngine().makeTextRun(
            rawText: rawText,
            insertionPoint: insertion,
            style: style,
            height: height,
            rotationRadians: rotation,
            widthFactor: widthFactor,
            boxWidth: boxWidth,
            boxHeight: boxHeight,
            horizontalAlignmentCode: horizontalAlignmentCode,
            verticalAlignmentCode: verticalAlignmentCode
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


    private static func textAnchorPoint(
        type: String,
        pairs: [Pair],
        horizontalAlignmentCode: Int?,
        verticalAlignmentCode: Int?
    ) -> Kernel.CADPoint {
        let insertion = point(in: pairs, xCode: 10, yCode: 20) ?? .zero
        guard type != "MTEXT" else { return insertion }
        guard let alignment = point(in: pairs, xCode: 11, yCode: 21) else {
            return insertion
        }

        let insertionIsMissing = abs(insertion.x) <= 0.000001 && abs(insertion.y) <= 0.000001
        let alignmentIsValid = abs(alignment.x) > 0.000001 || abs(alignment.y) > 0.000001
        let usesAlignmentAnchor = (horizontalAlignmentCode ?? 0) != 0 || (verticalAlignmentCode ?? 0) != 0
        return alignmentIsValid && (insertionIsMissing || usesAlignmentAnchor) ? alignment : insertion
    }


    static func makeInsert(type: String, from pairs: [Pair]) -> EntityRecord? {
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


    static func makeHatch(from pairs: [Pair]) -> EntityRecord? {
        let boundary = orderedPoints(in: pairs, xCode: 10, yCode: 20)
        let boundaryPathCount = firstInt(code: 91, in: pairs) ?? 1
        let hasEdgeMetadata = pairs.contains { $0.code == 72 || $0.code == 92 || $0.code == 93 }
        let isComplexBoundary = boundaryPathCount > 1 || hasEdgeMetadata
        guard boundary.count >= 3 else {
            let reason = isComplexBoundary
                ? "Complex HATCH boundary cannot be resolved by the Native CAD Renderer."
                : "HATCH boundary cannot be resolved by the Native CAD Renderer."
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
                            ? "CAD_NATIVE_HATCH_COMPLEX_BOUNDARY_UNRESOLVED"
                            : "CAD_NATIVE_HATCH_BOUNDARY_UNRESOLVED",
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
                        ? "CAD_NATIVE_HATCH_COMPLEX_BOUNDARY_DEGRADED"
                        : "CAD_NATIVE_HATCH_SIMPLE_FILL",
                    message: isComplexBoundary
                        ? "Complex HATCH imported as boundary-only geometry; inner loops and fill patterns are skipped to keep rendering responsive."
                        : "Simple closed HATCH imported as a filled polygon for the Native CAD Renderer.",
                    detail: firstString(code: 5, in: pairs)
                )
            ]
        )
    }


    static func makeLeader(type: String, from pairs: [Pair]) -> EntityRecord? {
        let vertices = orderedPoints(in: pairs, xCode: 10, yCode: 20)
        guard vertices.count >= 2 else {
            if let textRecord = makeLeaderTextOnly(type: type, from: pairs) {
                return textRecord
            }
            return unsupportedRecord(
                type: type,
                pairs: pairs,
                code: "CAD_NATIVE_LEADER_GEOMETRY_UNRESOLVED",
                reason: "\(type) vertices cannot be resolved by the Native CAD Renderer."
            )
        }
        let path = makePath(from: vertices, closed: false)
        let text = leaderTextRun(type: type, pairs: pairs, fallbackPoint: vertices.last ?? path.bounds.center)
        let bounds = text.map { path.bounds.union(textBounds(for: $0, insertion: $0.insertionPoint, height: $0.height)) }
            ?? path.bounds
        return EntityRecord(
            kind: text == nil ? .polyline : .dimension,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: path,
            text: text,
            bounds: bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: type,
            diagnostics: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: text == nil
                        ? "CAD_NATIVE_LEADER_DEGRADED_TO_POLYLINE"
                        : "CAD_NATIVE_LEADER_TEXT_SIMPLIFIED",
                    message: text == nil
                        ? "\(type) imported as a polyline."
                        : "\(type) imported as leader geometry with simplified annotation text.",
                    detail: firstString(code: 5, in: pairs)
                )
            ]
        )
    }


    static func makeLeaderTextOnly(type: String, from pairs: [Pair]) -> EntityRecord? {
        guard let text = leaderTextRun(type: type, pairs: pairs, fallbackPoint: point(in: pairs, xCode: 10, yCode: 20) ?? .zero) else {
            return nil
        }
        let bounds = textBounds(for: text, insertion: text.insertionPoint, height: text.height)
        return EntityRecord(
            kind: .mtext,
            layerID: layerID(from: pairs),
            handle: firstString(code: 5, in: pairs),
            path: nil,
            text: text,
            bounds: bounds,
            colorARGB: colorARGB(from: pairs, defaultACI: nil),
            lineWeight: lineWeight(from: pairs),
            visibility: visibility(from: pairs),
            sourceType: type,
            diagnostics: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: "CAD_NATIVE_LEADER_TEXT_WITHOUT_GEOMETRY",
                    message: "\(type) annotation text was imported, but leader geometry could not be resolved.",
                    detail: firstString(code: 5, in: pairs)
                )
            ]
        )
    }


    static func leaderTextRun(
        type: String,
        pairs: [Pair],
        fallbackPoint: Kernel.CADPoint
    ) -> Kernel.CADTextRun? {
        let rawText = joinedText(from: pairs, acceptedCodes: Set([1, 3, 302, 304]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return nil }

        let insertion = point(in: pairs, xCode: 12, yCode: 22)
            ?? point(in: pairs, xCode: 11, yCode: 21)
            ?? fallbackPoint
        let styleName = firstString(code: 7, in: pairs) ?? Kernel.CADTextStyle.default.id
        let style = Kernel.CADTextStyle(id: styleName, name: styleName)
        let height = positiveOrNil(firstDouble(code: 40, in: pairs))
            ?? positiveOrNil(firstDouble(code: 140, in: pairs))
            ?? 2.5
        let boxWidth = positiveOrNil(firstDouble(code: 41, in: pairs))
        let rotation = (firstDouble(code: 50, in: pairs) ?? 0) * .pi / 180
        return Kernel.CADTextEngine().makeTextRun(
            rawText: rawText,
            insertionPoint: insertion,
            style: style,
            height: height,
            rotationRadians: rotation,
            widthFactor: style.widthFactor,
            boxWidth: boxWidth,
            horizontalAlignmentCode: firstInt(code: 71, in: pairs),
            verticalAlignmentCode: firstInt(code: 72, in: pairs)
        )
    }


    static func makeTableCellTexts(
        from pairs: [Pair],
        textStylesByID: [String: Kernel.CADTextStyle]
    ) -> [EntityRecord] {
        let cellTexts = tableCellTextValues(from: pairs)
        guard !cellTexts.isEmpty else {
            return [
                unsupportedRecord(
                    type: "TABLE",
                    pairs: pairs,
                    code: "CAD_NATIVE_TABLE_TEXT_UNRESOLVED",
                    reason: "TABLE cell text cannot be resolved by the Native CAD Renderer."
                )
            ]
        }

        let insertion = point(in: pairs, xCode: 10, yCode: 20) ?? .zero
        let columnCount = max(firstInt(code: 90, in: pairs) ?? Int(ceil(sqrt(Double(cellTexts.count)))), 1)
        let rowCount = max(firstInt(code: 91, in: pairs) ?? Int(ceil(Double(cellTexts.count) / Double(columnCount))), 1)
        let widths = allDoubles(code: 142, in: pairs)
        let heights = allDoubles(code: 141, in: pairs)
        let defaultWidth = positiveOrNil(firstDouble(code: 41, in: pairs)) ?? 20
        let defaultHeight = positiveOrNil(firstDouble(code: 40, in: pairs)) ?? 8
        let rotation = (firstDouble(code: 50, in: pairs) ?? 0) * .pi / 180
        let styleName = firstString(code: 7, in: pairs) ?? Kernel.CADTextStyle.default.id
        let style = textStylesByID[styleName] ?? Kernel.CADTextStyle(id: styleName, name: styleName)
        let handle = firstString(code: 5, in: pairs)
        let layer = layerID(from: pairs)
        let color = colorARGB(from: pairs, defaultACI: nil)
        let lineWeight = lineWeight(from: pairs)
        let visibility = visibility(from: pairs)

        var records: [EntityRecord] = []
        records.reserveCapacity(cellTexts.count)
        for (index, rawText) in cellTexts.enumerated() {
            let row = min(index / columnCount, max(rowCount - 1, 0))
            let column = index % columnCount
            let cellWidth = widths.indices.contains(column)
                ? (positiveOrNil(widths[column]) ?? defaultWidth)
                : defaultWidth
            let cellHeight = heights.indices.contains(row)
                ? (positiveOrNil(heights[row]) ?? defaultHeight)
                : defaultHeight
            let xOffset = cumulative(widths, through: column, fallback: defaultWidth) + cellWidth * 0.08
            let yOffset = -cumulative(heights, through: row, fallback: defaultHeight) - cellHeight * 0.55
            let insertionPoint = Kernel.CADPoint(
                x: insertion.x + xOffset * cos(rotation) - yOffset * sin(rotation),
                y: insertion.y + xOffset * sin(rotation) + yOffset * cos(rotation)
            )
            let textHeight = max(cellHeight * 0.45, style.fixedHeight ?? 2.5)
            let text = Kernel.CADTextEngine().makeTextRun(
                rawText: rawText,
                insertionPoint: insertionPoint,
                style: style,
                height: textHeight,
                rotationRadians: rotation,
                widthFactor: style.widthFactor,
                boxWidth: cellWidth,
                boxHeight: cellHeight,
                horizontalAlignmentCode: firstInt(code: 170, in: pairs),
                verticalAlignmentCode: firstInt(code: 170, in: pairs)
            )
            let bounds = textBounds(for: text, insertion: insertionPoint, height: textHeight)
            records.append(
                EntityRecord(
                    kind: .mtext,
                    layerID: layer,
                    handle: handle.map { "\($0)-cell-\(index)" },
                    path: nil,
                    text: text,
                    bounds: bounds,
                    colorARGB: color,
                    lineWeight: lineWeight,
                    visibility: visibility,
                    sourceType: "TABLE",
                    diagnostics: [
                        Kernel.CADDrawingDiagnostics.Entry(
                            severity: .info,
                            code: "CAD_NATIVE_TABLE_CELL_TEXT_SIMPLIFIED",
                            message: "TABLE cell text imported as positioned MTEXT for the Native CAD Renderer.",
                            detail: handle
                        )
                    ]
                )
            )
        }
        return records
    }


    static func tableCellTextValues(from pairs: [Pair]) -> [String] {
        let acceptedCodes = Set([1, 3, 302, 304])
        return pairs
            .filter { acceptedCodes.contains($0.code) }
            .map { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }


    static func cumulative(_ values: [Double], through index: Int, fallback: Double) -> Double {
        guard index > 0 else { return 0 }
        return (0..<index).reduce(0) { partial, current in
            if values.indices.contains(current) {
                return partial + (positiveOrNil(values[current]) ?? fallback)
            }
            return partial + fallback
        }
    }


    static func makeMLine(from pairs: [Pair]) -> EntityRecord? {
        let vertices = orderedPoints(in: pairs, xCode: 11, yCode: 21)
        guard vertices.count >= 2 else {
            return unsupportedRecord(
                type: "MLINE",
                pairs: pairs,
                code: "CAD_NATIVE_MLINE_GEOMETRY_UNRESOLVED",
                reason: "MLINE vertices cannot be resolved by the Native CAD Renderer."
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
                    code: "CAD_NATIVE_MLINE_DEGRADED_TO_CENTERLINE",
                    message: "MLINE imported as its vertex centerline.",
                    detail: firstString(code: 5, in: pairs)
                )
            ]
        )
    }


    static func makeFilledShape(type: String, from pairs: [Pair]) -> EntityRecord? {
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
                code: "CAD_NATIVE_FILLED_SHAPE_GEOMETRY_UNRESOLVED",
                reason: "\(type) boundary cannot be resolved by the Native CAD Renderer."
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
                    code: "CAD_NATIVE_FILLED_SHAPE_DEGRADED_TO_BOUNDARY",
                    message: "\(type) imported as a closed boundary.",
                    detail: firstString(code: 5, in: pairs)
                )
            ]
        )
    }


    static func makeImagePlaceholder(type: String, from pairs: [Pair]) -> EntityRecord? {
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
                    code: "CAD_NATIVE_IMAGE_PLACEHOLDER",
                    message: "\(type) imported as a frame placeholder.",
                    detail: firstString(code: 5, in: pairs)
                )
            ],
            unsupportedReason: "\(type) placeholder; referenced image or underlay content is not rendered in the Native CAD Renderer."
        )
    }


    static func makeWipeout(from pairs: [Pair]) -> EntityRecord? {
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
                        code: "CAD_NATIVE_WIPEOUT_DEGRADED_TO_BOUNDARY",
                        message: "WIPEOUT imported as a boundary frame; masking is not implemented in the native CAD renderer.",
                        detail: firstString(code: 5, in: pairs)
                    )
                ]
            )
        }
        return makeImagePlaceholder(type: "WIPEOUT", from: pairs)
    }


    static func dimensionEndpoints(from pairs: [Pair]) -> (start: Kernel.CADPoint, end: Kernel.CADPoint)? {
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


    static func dimensionDisplayText(from pairs: [Pair], measurementText: String) -> String {
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


    static func expandInsertRecords(
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
                            code: "CAD_NATIVE_INSERT_BLOCK_NAME_MISSING",
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
                            code: "CAD_NATIVE_INSERT_BLOCK_CYCLE",
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
                            code: "CAD_NATIVE_INSERT_BLOCK_MISSING",
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


    static func xrefRecord(
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
        let reason = "XREF \(block.name) is referenced but not loaded by the Native CAD Renderer."
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
                    code: "CAD_NATIVE_XREF_NOT_LOADED",
                    message: reason,
                    detail: block.xrefPath ?? block.name
                )
            ],
            unsupportedReason: reason
        )
    }


    static func resolvedInheritedLineType(
        _ lineType: String?,
        inheritedLineType: String?
    ) -> String? {
        let trimmed = lineType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.caseInsensitiveCompare("ByBlock") == .orderedSame || trimmed.isEmpty {
            return inheritedLineType
        }
        return trimmed
    }


    static func blockDefinition(
        named name: String,
        in blocksByName: [String: BlockDefinition]
    ) -> BlockDefinition? {
        if let block = blocksByName[name] {
            return block
        }
        let normalizedName = normalized(name)
        return blocksByName.first { normalized($0.key) == normalizedName }?.value
    }


    static func insertArrayTransforms(for record: EntityRecord) -> [Kernel.CADTransform] {
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


    static func unresolvedInsertRecord(
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


    static func attributeTag(type: String, pairs: [Pair]) -> String? {
        guard type == "ATTRIB" || type == "ATTDEF" else { return nil }
        let value = firstString(code: 2, in: pairs)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }


    static func layerID(from pairs: [Pair]) -> String {
        let layer = firstString(code: 8, in: pairs)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (layer?.isEmpty == false ? layer : nil) ?? Kernel.CADLayer.default.id
    }


    static func layoutID(from pairs: [Pair]) -> String? {
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


    static func blockName(from pairs: [Pair]) -> String? {
        let name = (firstString(code: 2, in: pairs) ?? firstString(code: 3, in: pairs))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }

}
