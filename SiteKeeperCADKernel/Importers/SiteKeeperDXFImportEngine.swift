import CoreFoundation
import Foundation

extension SiteKeeperCADKernel {
    struct DXFImportEngine: CADImportEngine {
        let id = "sitekeeper.dxf"
        let supportedFormats: Set<CADFileFormat> = [.dxf]

        func canImport(file: CADFile) -> Bool {
            supportedFormats.contains(file.format)
        }

        func importDrawing(file: CADFile) async throws -> CADDatabase {
            do {
                let data = try Data(contentsOf: file.url)
                let contents = decodeDXFText(data: data)
                var parser = DXFParser(file: file, contents: contents)
                return try parser.parse()
            } catch let error as CADImportError {
                throw error
            } catch {
                throw CADImportError.importerNotReady("DXF import failed: \(file.displayName)")
            }
        }

        private func decodeDXFText(data: Data) -> String {
            let gb18030 = String.Encoding(
                rawValue: CFStringConvertEncodingToNSStringEncoding(
                    CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
                )
            )
            let candidates: [String.Encoding] = [.utf8, .utf16LittleEndian, .utf16BigEndian, gb18030, .isoLatin1]
            for encoding in candidates {
                if let text = String(data: data, encoding: encoding), !text.isEmpty {
                    return text
                }
            }
            return String(decoding: data, as: UTF8.self)
        }
    }
}

private struct DXFPair {
    var code: Int
    var value: String
}

private struct DXFRecord {
    var type: String
    var pairs: [DXFPair]
}

private struct DXFParseState {
    typealias Kernel = SiteKeeperCADKernel

    var units: Kernel.CADUnits = .unitless
    var headerExtents: Kernel.CADBounds?
    var layersByID: [String: Kernel.CADLayer] = [:]
    var textStylesByID: [String: Kernel.CADTextStyle] = [:]
    var ltypeNames: Set<String> = []
    var blocks: [Kernel.CADBlock] = []
    var entities: [Kernel.CADEntity] = []
    var diagnostics = Kernel.CADDrawingDiagnostics()
}

private struct DXFParser {
    typealias Kernel = SiteKeeperCADKernel

    private enum EntityContext {
        case modelSpace
        case block(defaultLayerID: String?)
    }

    var file: Kernel.CADFile
    var contents: String
    private let textEngine = Kernel.CADTextEngine()

    mutating func parse() throws -> Kernel.CADDatabase {
        let allPairs = decodePairs(contents)
        let sections = splitSections(from: allPairs)
        var state = DXFParseState()

        if let header = sections["HEADER"] {
            parseHeaderSection(header, state: &state)
        }
        if let tables = sections["TABLES"] {
            parseTablesSection(tables, state: &state)
        }
        if let blocks = sections["BLOCKS"] {
            parseBlocksSection(blocks, state: &state)
        }
        if let entities = sections["ENTITIES"] {
            parseEntitiesSection(
                entities,
                context: .modelSpace,
                state: &state
            )
        }

        if state.entities.isEmpty {
            state.diagnostics.append(
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: "CAD_DXF_NO_DRAWABLE_ENTITIES",
                    message: "DXF file does not contain drawable 2D entities.",
                    detail: file.displayName
                )
            )
        }
        if !state.ltypeNames.isEmpty {
            state.diagnostics.append(
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .info,
                    code: "CAD_DXF_LTYPE_SIMPLIFIED",
                    message: "LTYPE table parsed with simplified handling.",
                    detail: state.ltypeNames.sorted().joined(separator: ", ")
                )
            )
        }

        let mergedLayers = buildLayers(state: state)
        let textStyles = buildTextStyles(state: state)
        let allBounds = state.entities.reduce(Kernel.CADBounds.empty) { $0.union($1.bounds) }
        let extents = state.headerExtents ?? allBounds

        var database = Kernel.CADDatabase(
            file: file,
            units: state.units,
            extents: extents,
            layers: mergedLayers,
            layouts: buildLayouts(from: state.entities),
            blocks: state.blocks,
            entities: state.entities,
            textStyles: textStyles,
            diagnostics: state.diagnostics
        )
        database.setImportMetadata(
            geometryParsed: true,
            importSource: Kernel.DXFImportEngine().id
        )
        return database
    }

    private func decodePairs(_ contents: String) -> [DXFPair] {
        let lines = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var pairs: [DXFPair] = []
        var index = 0
        while index + 1 < lines.count {
            let codeText = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = lines[index + 1].trimmingCharacters(in: .newlines)
            if let code = Int(codeText) {
                pairs.append(DXFPair(code: code, value: value))
            }
            index += 2
        }
        return pairs
    }

    private func splitSections(from pairs: [DXFPair]) -> [String: [DXFPair]] {
        var sections: [String: [DXFPair]] = [:]
        var index = 0
        while index < pairs.count {
            let pair = pairs[index]
            if pair.code == 0, normalizedType(pair.value) == "SECTION" {
                let sectionName = (index + 1 < pairs.count && pairs[index + 1].code == 2)
                    ? normalizedType(pairs[index + 1].value)
                    : "UNKNOWN"
                index += 2
                var body: [DXFPair] = []
                while index < pairs.count {
                    let current = pairs[index]
                    if current.code == 0, normalizedType(current.value) == "ENDSEC" {
                        break
                    }
                    body.append(current)
                    index += 1
                }
                sections[sectionName, default: []].append(contentsOf: body)
            }
            index += 1
        }
        return sections
    }

    private func parseHeaderSection(_ pairs: [DXFPair], state: inout DXFParseState) {
        var index = 0
        var extMin: Kernel.CADPoint?
        var extMax: Kernel.CADPoint?
        while index < pairs.count {
            let pair = pairs[index]
            guard pair.code == 9 else {
                index += 1
                continue
            }
            let variableName = normalizedType(pair.value)
            index += 1
            var variablePairs: [DXFPair] = []
            while index < pairs.count, pairs[index].code != 9 {
                variablePairs.append(pairs[index])
                index += 1
            }
            switch variableName {
            case "$INSUNITS":
                if let insUnits = firstInt(code: 70, in: variablePairs) {
                    state.units = units(for: insUnits)
                }
            case "$EXTMIN":
                extMin = point(in: variablePairs, xCode: 10, yCode: 20)
            case "$EXTMAX":
                extMax = point(in: variablePairs, xCode: 10, yCode: 20)
            default:
                break
            }
        }

        if let extMin, let extMax {
            state.headerExtents = Kernel.CADBounds(
                minX: min(extMin.x, extMax.x),
                minY: min(extMin.y, extMax.y),
                maxX: max(extMin.x, extMax.x),
                maxY: max(extMin.y, extMax.y)
            )
        }
    }

    private func parseTablesSection(_ pairs: [DXFPair], state: inout DXFParseState) {
        var index = 0
        while index < pairs.count {
            guard pairs[index].code == 0, normalizedType(pairs[index].value) == "TABLE" else {
                index += 1
                continue
            }
            index += 1
            let tableName = (index < pairs.count && pairs[index].code == 2)
                ? normalizedType(pairs[index].value)
                : "UNKNOWN"
            if index < pairs.count, pairs[index].code == 2 {
                index += 1
            }

            var tableBody: [DXFPair] = []
            while index < pairs.count {
                if pairs[index].code == 0, normalizedType(pairs[index].value) == "ENDTAB" {
                    break
                }
                tableBody.append(pairs[index])
                index += 1
            }
            parseTable(named: tableName, pairs: tableBody, state: &state)
            index += 1
        }
    }

    private func parseTable(named tableName: String, pairs: [DXFPair], state: inout DXFParseState) {
        let records = parseRecords(pairs: pairs)
        switch tableName {
        case "LAYER":
            for record in records where normalizedType(record.type) == "LAYER" {
                let layerName = firstString(code: 2, in: record.pairs) ?? Kernel.CADLayer.default.id
                let flags = firstInt(code: 70, in: record.pairs) ?? 0
                let colorCode = firstInt(code: 62, in: record.pairs) ?? 7
                let layerColor = colorARGB(fromEntityPairs: record.pairs, defaultACI: abs(colorCode))
                let isVisible = colorCode >= 0 && (flags & 1) == 0
                let isLocked = (flags & 4) == 4
                let lineWeight = lineWeight(from: record.pairs) ?? 0.25
                state.layersByID[layerName] = Kernel.CADLayer(
                    id: layerName,
                    name: layerName,
                    isVisible: isVisible,
                    isLocked: isLocked,
                    colorARGB: layerColor,
                    lineWeight: lineWeight,
                    lineType: firstString(code: 6, in: record.pairs) ?? "Continuous"
                )
            }
        case "STYLE":
            for record in records where normalizedType(record.type) == "STYLE" {
                let styleName = firstString(code: 2, in: record.pairs) ?? Kernel.CADTextStyle.default.id
                let obliqueDegrees = firstDouble(code: 50, in: record.pairs) ?? 0
                let style = Kernel.CADTextStyle(
                    id: styleName,
                    name: styleName,
                    fontName: firstString(code: 3, in: record.pairs),
                    bigFontName: firstString(code: 4, in: record.pairs),
                    fixedHeight: positiveOrNil(firstDouble(code: 40, in: record.pairs)),
                    widthFactor: positiveOr(firstDouble(code: 41, in: record.pairs), fallback: 1),
                    obliqueAngleRadians: obliqueDegrees * .pi / 180
                )
                state.textStylesByID[styleName] = style
            }
        case "LTYPE":
            for record in records where normalizedType(record.type) == "LTYPE" {
                if let ltype = firstString(code: 2, in: record.pairs), !ltype.isEmpty {
                    state.ltypeNames.insert(ltype)
                }
            }
        default:
            break
        }
    }

    private mutating func parseBlocksSection(_ pairs: [DXFPair], state: inout DXFParseState) {
        var index = 0
        while index < pairs.count {
            guard pairs[index].code == 0, normalizedType(pairs[index].value) == "BLOCK" else {
                index += 1
                continue
            }
            index += 1
            let headerPairs = consumeRecordPairs(pairs: pairs, index: &index)
            let blockName = firstString(code: 2, in: headerPairs)
                ?? firstString(code: 3, in: headerPairs)
                ?? "BLOCK_\(state.blocks.count + 1)"
            let normalizedName = normalizedType(blockName)
            let blockLayer = firstString(code: 8, in: headerPairs)

            var blockEntities: [Kernel.CADEntity] = []
            while index < pairs.count {
                guard pairs[index].code == 0 else {
                    index += 1
                    continue
                }
                let kind = normalizedType(pairs[index].value)
                if kind == "ENDBLK" {
                    index += 1
                    _ = consumeRecordPairs(pairs: pairs, index: &index)
                    break
                }
                if kind == "BLOCK" {
                    break
                }
                let parsed = parseEntity(
                    from: pairs,
                    index: &index,
                    context: .block(defaultLayerID: blockLayer),
                    state: &state
                )
                blockEntities.append(contentsOf: parsed)
            }

            if normalizedName == "*MODEL_SPACE" || normalizedName == "*PAPER_SPACE" {
                continue
            }
            let basePoint = point(in: headerPairs, xCode: 10, yCode: 20) ?? .zero
            let blockBounds = blockEntities.reduce(Kernel.CADBounds.empty) { $0.union($1.bounds) }
            let resolvedBounds = blockBounds.isEmpty
                ? Kernel.CADBounds(
                    minX: basePoint.x,
                    minY: basePoint.y,
                    maxX: basePoint.x,
                    maxY: basePoint.y
                )
                : blockBounds
            state.blocks.append(
                Kernel.CADBlock(
                    id: blockName,
                    name: blockName,
                    basePoint: basePoint,
                    entities: blockEntities,
                    bounds: resolvedBounds,
                    sourceHandle: firstString(code: 5, in: headerPairs)
                )
            )
        }
    }

    private mutating func parseEntitiesSection(
        _ pairs: [DXFPair],
        context: EntityContext,
        state: inout DXFParseState
    ) {
        var index = 0
        while index < pairs.count {
            guard pairs[index].code == 0 else {
                index += 1
                continue
            }
            let parsed = parseEntity(from: pairs, index: &index, context: context, state: &state)
            state.entities.append(contentsOf: parsed)
        }
    }

    private mutating func parseEntity(
        from pairs: [DXFPair],
        index: inout Int,
        context: EntityContext,
        state: inout DXFParseState
    ) -> [Kernel.CADEntity] {
        guard index < pairs.count else { return [] }
        guard pairs[index].code == 0 else {
            index += 1
            return []
        }
        let type = normalizedType(pairs[index].value)
        index += 1
        let recordPairs = consumeRecordPairs(pairs: pairs, index: &index)

        switch type {
        case "POLYLINE":
            var vertexRecords: [[DXFPair]] = []
            while index < pairs.count, pairs[index].code == 0 {
                let childType = normalizedType(pairs[index].value)
                if childType == "VERTEX" {
                    index += 1
                    vertexRecords.append(consumeRecordPairs(pairs: pairs, index: &index))
                    continue
                }
                if childType == "SEQEND" {
                    index += 1
                    _ = consumeRecordPairs(pairs: pairs, index: &index)
                    break
                }
                break
            }
            let entity = makePolylineEntity(
                type: type,
                recordPairs: recordPairs,
                polylineVertices: vertexRecords,
                context: context,
                state: &state
            )
            return [entity]

        case "INSERT":
            var results = [makeInsertEntity(recordPairs: recordPairs, context: context, state: &state)]
            if (firstInt(code: 66, in: recordPairs) ?? 0) == 1 {
                while index < pairs.count, pairs[index].code == 0 {
                    let childType = normalizedType(pairs[index].value)
                    if childType == "ATTRIB" || childType == "ATTDEF" {
                        index += 1
                        let attribPairs = consumeRecordPairs(pairs: pairs, index: &index)
                        results.append(
                            makeTextEntity(
                                type: childType,
                                recordPairs: attribPairs,
                                context: context,
                                state: &state
                            )
                        )
                        continue
                    }
                    if childType == "SEQEND" {
                        index += 1
                        _ = consumeRecordPairs(pairs: pairs, index: &index)
                        break
                    }
                    break
                }
            }
            return results

        default:
            return [makeEntity(type: type, recordPairs: recordPairs, context: context, state: &state)]
        }
    }

    private mutating func makeEntity(
        type: String,
        recordPairs: [DXFPair],
        context: EntityContext,
        state: inout DXFParseState
    ) -> Kernel.CADEntity {
        switch type {
        case "LINE":
            return makeLineEntity(recordPairs: recordPairs, context: context, state: &state)
        case "LWPOLYLINE":
            return makePolylineEntity(
                type: type,
                recordPairs: recordPairs,
                polylineVertices: [],
                context: context,
                state: &state
            )
        case "CIRCLE":
            return makeCircleLikeEntity(kind: .circle, recordPairs: recordPairs, context: context, state: &state)
        case "ARC":
            return makeCircleLikeEntity(kind: .arc, recordPairs: recordPairs, context: context, state: &state)
        case "ELLIPSE":
            return makeEllipseEntity(recordPairs: recordPairs, context: context, state: &state)
        case "SPLINE":
            return makeSplineEntity(recordPairs: recordPairs, context: context, state: &state)
        case "TEXT", "MTEXT", "ATTRIB", "ATTDEF":
            return makeTextEntity(type: type, recordPairs: recordPairs, context: context, state: &state)
        case "DIMENSION":
            return makeDimensionEntity(recordPairs: recordPairs, context: context, state: &state)
        case "HATCH":
            return makeHatchEntity(recordPairs: recordPairs, context: context, state: &state)
        case "IMAGE", "UNDERLAY", "PDFUNDERLAY", "DWFUNDERLAY", "DGNUNDERLAY":
            return makeImagePlaceholderEntity(type: type, recordPairs: recordPairs, context: context, state: &state)
        case "VERTEX", "SEQEND":
            return makeUnsupportedEntity(
                type: type,
                recordPairs: recordPairs,
                context: context,
                reason: "\(type) is only valid inside POLYLINE and was preserved as unsupported.",
                state: &state
            )
        default:
            return makeUnsupportedEntity(
                type: type,
                recordPairs: recordPairs,
                context: context,
                reason: "Unsupported DXF entity: \(type)",
                state: &state
            )
        }
    }

    private mutating func makeLineEntity(
        recordPairs: [DXFPair],
        context: EntityContext,
        state: inout DXFParseState
    ) -> Kernel.CADEntity {
        guard let start = point(in: recordPairs, xCode: 10, yCode: 20),
              let end = point(in: recordPairs, xCode: 11, yCode: 21)
        else {
            return makeUnsupportedEntity(
                type: "LINE",
                recordPairs: recordPairs,
                context: context,
                reason: "LINE missing start/end coordinates.",
                state: &state
            )
        }
        let path = Kernel.CADPath(elements: [.move(to: start), .line(to: end)])
        return makeCommonEntity(
            kind: .line,
            recordPairs: recordPairs,
            context: context,
            state: &state,
            path: path,
            text: nil,
            blockName: nil,
            transform: .identity,
            bounds: path.bounds
        )
    }

    private mutating func makePolylineEntity(
        type: String,
        recordPairs: [DXFPair],
        polylineVertices: [[DXFPair]],
        context: EntityContext,
        state: inout DXFParseState
    ) -> Kernel.CADEntity {
        let polylinePoints: [Kernel.CADPoint]
        if type == "POLYLINE" {
            polylinePoints = polylineVertices.compactMap { point(in: $0, xCode: 10, yCode: 20) }
        } else {
            polylinePoints = points(in: recordPairs, xCode: 10, yCode: 20)
        }
        guard let first = polylinePoints.first else {
            return makeUnsupportedEntity(
                type: type,
                recordPairs: recordPairs,
                context: context,
                reason: "\(type) has no points.",
                state: &state
            )
        }
        var pathElements: [Kernel.CADPath.Element] = [.move(to: first)]
        pathElements.append(contentsOf: polylinePoints.dropFirst().map { .line(to: $0) })
        let isClosed = (firstInt(code: 70, in: recordPairs) ?? 0) & 1 == 1
        if isClosed, polylinePoints.count >= 2 {
            pathElements.append(.close)
        }
        let path = Kernel.CADPath(elements: pathElements)
        let kind: Kernel.CADEntityKind = type == "LWPOLYLINE" ? .lwPolyline : .polyline
        return makeCommonEntity(
            kind: kind,
            recordPairs: recordPairs,
            context: context,
            state: &state,
            path: path,
            text: nil,
            blockName: nil,
            transform: .identity,
            bounds: path.bounds
        )
    }

    private mutating func makeCircleLikeEntity(
        kind: Kernel.CADEntityKind,
        recordPairs: [DXFPair],
        context: EntityContext,
        state: inout DXFParseState
    ) -> Kernel.CADEntity {
        guard let center = point(in: recordPairs, xCode: 10, yCode: 20),
              let radius = positiveOrNil(firstDouble(code: 40, in: recordPairs))
        else {
            return makeUnsupportedEntity(
                type: kind.rawValue.uppercased(),
                recordPairs: recordPairs,
                context: context,
                reason: "\(kind.rawValue.uppercased()) missing center/radius.",
                state: &state
            )
        }
        let bounds = Kernel.CADBounds(
            minX: center.x - radius,
            minY: center.y - radius,
            maxX: center.x + radius,
            maxY: center.y + radius
        )
        return makeCommonEntity(
            kind: kind,
            recordPairs: recordPairs,
            context: context,
            state: &state,
            path: nil,
            text: nil,
            blockName: nil,
            transform: .identity,
            bounds: bounds
        )
    }

    private mutating func makeEllipseEntity(
        recordPairs: [DXFPair],
        context: EntityContext,
        state: inout DXFParseState
    ) -> Kernel.CADEntity {
        guard let center = point(in: recordPairs, xCode: 10, yCode: 20),
              let majorVector = point(in: recordPairs, xCode: 11, yCode: 21)
        else {
            return makeUnsupportedEntity(
                type: "ELLIPSE",
                recordPairs: recordPairs,
                context: context,
                reason: "ELLIPSE missing center/major-axis data.",
                state: &state
            )
        }
        let majorRadius = hypot(majorVector.x, majorVector.y)
        let ratio = positiveOr(firstDouble(code: 40, in: recordPairs), fallback: 0.5)
        let minorRadius = majorRadius * ratio
        guard majorRadius > 0, minorRadius > 0 else {
            return makeUnsupportedEntity(
                type: "ELLIPSE",
                recordPairs: recordPairs,
                context: context,
                reason: "ELLIPSE has invalid axis radii.",
                state: &state
            )
        }
        let theta = atan2(majorVector.y, majorVector.x)
        let dx = sqrt(pow(majorRadius * cos(theta), 2) + pow(minorRadius * sin(theta), 2))
        let dy = sqrt(pow(majorRadius * sin(theta), 2) + pow(minorRadius * cos(theta), 2))
        let bounds = Kernel.CADBounds(
            minX: center.x - dx,
            minY: center.y - dy,
            maxX: center.x + dx,
            maxY: center.y + dy
        )
        return makeCommonEntity(
            kind: .ellipse,
            recordPairs: recordPairs,
            context: context,
            state: &state,
            path: nil,
            text: nil,
            blockName: nil,
            transform: .identity,
            bounds: bounds
        )
    }

    private mutating func makeSplineEntity(
        recordPairs: [DXFPair],
        context: EntityContext,
        state: inout DXFParseState
    ) -> Kernel.CADEntity {
        let splinePoints = points(in: recordPairs, xCode: 10, yCode: 20)
        guard let first = splinePoints.first else {
            return makeUnsupportedEntity(
                type: "SPLINE",
                recordPairs: recordPairs,
                context: context,
                reason: "SPLINE has no control points.",
                state: &state
            )
        }
        var elements: [Kernel.CADPath.Element] = [.move(to: first)]
        elements.append(contentsOf: splinePoints.dropFirst().map { .line(to: $0) })
        let path = Kernel.CADPath(elements: elements)
        let entry = Kernel.CADDrawingDiagnostics.Entry(
            severity: .warning,
            code: "CAD_DXF_SPLINE_SIMPLIFIED",
            message: "SPLINE simplified to polyline for first-stage rendering.",
            detail: firstString(code: 5, in: recordPairs)
        )
        return makeCommonEntity(
            kind: .polyline,
            recordPairs: recordPairs,
            context: context,
            state: &state,
            path: path,
            text: nil,
            blockName: nil,
            transform: .identity,
            bounds: path.bounds,
            diagnostics: Kernel.CADDrawingDiagnostics(entries: [entry])
        )
    }

    private mutating func makeTextEntity(
        type: String,
        recordPairs: [DXFPair],
        context: EntityContext,
        state: inout DXFParseState
    ) -> Kernel.CADEntity {
        let rawText = joinedText(from: recordPairs, acceptedCodes: Set([1, 3])).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            return makeUnsupportedEntity(
                type: type,
                recordPairs: recordPairs,
                context: context,
                reason: "\(type) has empty text payload.",
                state: &state
            )
        }
        let insertion = point(in: recordPairs, xCode: 10, yCode: 20) ?? fallbackPoint(in: recordPairs)
        let styleName = firstString(code: 7, in: recordPairs) ?? Kernel.CADTextStyle.default.id
        let style = resolveTextStyle(named: styleName, state: &state)
        let height = positiveOrNil(firstDouble(code: 40, in: recordPairs)) ?? style.fixedHeight ?? 2.5
        let rotation = (firstDouble(code: 50, in: recordPairs) ?? 0) * .pi / 180

        let textRun = textEngine.makeTextRun(
            rawText: rawText,
            insertionPoint: insertion,
            style: style,
            height: height,
            rotationRadians: rotation
        )
        let bounds = Kernel.CADBounds(
            minX: insertion.x,
            minY: insertion.y,
            maxX: insertion.x + max(Double(textRun.displayText.count) * max(height * 0.6, 0.6), max(height, 0.6)),
            maxY: insertion.y + max(height, 0.6)
        )
        let kind: Kernel.CADEntityKind
        switch type {
        case "MTEXT":
            kind = .mtext
        case "ATTRIB", "ATTDEF":
            kind = .attrib
        default:
            kind = .text
        }
        return makeCommonEntity(
            kind: kind,
            recordPairs: recordPairs,
            context: context,
            state: &state,
            path: nil,
            text: textRun,
            blockName: nil,
            transform: .identity,
            bounds: bounds
        )
    }

    private mutating func makeDimensionEntity(
        recordPairs: [DXFPair],
        context: EntityContext,
        state: inout DXFParseState
    ) -> Kernel.CADEntity {
        let start = point(in: recordPairs, xCode: 13, yCode: 23)
            ?? point(in: recordPairs, xCode: 10, yCode: 20)
        let end = point(in: recordPairs, xCode: 14, yCode: 24)
            ?? point(in: recordPairs, xCode: 11, yCode: 21)
        guard let start, let end else {
            return makeUnsupportedEntity(
                type: "DIMENSION",
                recordPairs: recordPairs,
                context: context,
                reason: "DIMENSION missing definition points.",
                state: &state
            )
        }
        let path = Kernel.CADPath(elements: [.move(to: start), .line(to: end)])
        let rawText = firstString(code: 1, in: recordPairs)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let textRun: Kernel.CADTextRun?
        if rawText.isEmpty {
            textRun = nil
        } else {
            let styleName = firstString(code: 7, in: recordPairs) ?? Kernel.CADTextStyle.default.id
            let style = resolveTextStyle(named: styleName, state: &state)
            let insertion = point(in: recordPairs, xCode: 11, yCode: 21) ?? path.bounds.center
            textRun = textEngine.makeTextRun(
                rawText: rawText,
                insertionPoint: insertion,
                style: style,
                height: style.fixedHeight ?? 2.5
            )
        }
        let entry = Kernel.CADDrawingDiagnostics.Entry(
            severity: .warning,
            code: "CAD_DXF_DIMENSION_SIMPLIFIED",
            message: "DIMENSION imported as simplified dimension line.",
            detail: firstString(code: 5, in: recordPairs)
        )
        return makeCommonEntity(
            kind: .dimension,
            recordPairs: recordPairs,
            context: context,
            state: &state,
            path: path,
            text: textRun,
            blockName: nil,
            transform: .identity,
            bounds: textRun == nil ? path.bounds : path.bounds.union(
                Kernel.CADBounds(
                    minX: textRun!.insertionPoint.x,
                    minY: textRun!.insertionPoint.y,
                    maxX: textRun!.insertionPoint.x,
                    maxY: textRun!.insertionPoint.y
                )
            ),
            diagnostics: Kernel.CADDrawingDiagnostics(entries: [entry])
        )
    }

    private mutating func makeHatchEntity(
        recordPairs: [DXFPair],
        context: EntityContext,
        state: inout DXFParseState
    ) -> Kernel.CADEntity {
        let boundary = points(in: recordPairs, xCode: 10, yCode: 20)
        guard boundary.count >= 3 else {
            return makeUnsupportedEntity(
                type: "HATCH",
                recordPairs: recordPairs,
                context: context,
                reason: "HATCH boundary cannot be resolved and is kept as unsupported.",
                state: &state
            )
        }
        var elements: [Kernel.CADPath.Element] = [.move(to: boundary[0])]
        elements.append(contentsOf: boundary.dropFirst().map { .line(to: $0) })
        elements.append(.close)
        let path = Kernel.CADPath(elements: elements)
        let entry = Kernel.CADDrawingDiagnostics.Entry(
            severity: .warning,
            code: "CAD_DXF_HATCH_SIMPLIFIED",
            message: "HATCH imported as boundary path.",
            detail: firstString(code: 5, in: recordPairs)
        )
        return makeCommonEntity(
            kind: .hatch,
            recordPairs: recordPairs,
            context: context,
            state: &state,
            path: path,
            text: nil,
            blockName: nil,
            transform: .identity,
            bounds: path.bounds,
            diagnostics: Kernel.CADDrawingDiagnostics(entries: [entry])
        )
    }

    private mutating func makeInsertEntity(
        recordPairs: [DXFPair],
        context: EntityContext,
        state: inout DXFParseState
    ) -> Kernel.CADEntity {
        guard let blockName = firstString(code: 2, in: recordPairs), !blockName.isEmpty else {
            return makeUnsupportedEntity(
                type: "INSERT",
                recordPairs: recordPairs,
                context: context,
                reason: "INSERT has no block name.",
                state: &state
            )
        }
        let insertion = point(in: recordPairs, xCode: 10, yCode: 20) ?? fallbackPoint(in: recordPairs)
        let sx = firstDouble(code: 41, in: recordPairs) ?? 1
        let sy = firstDouble(code: 42, in: recordPairs) ?? 1
        let rotationRadians = (firstDouble(code: 50, in: recordPairs) ?? 0) * .pi / 180
        let transform = Kernel.CADTransform
            .translation(x: insertion.x, y: insertion.y)
            .concatenating(.rotation(rotationRadians))
            .concatenating(.scale(x: sx, y: sy))
        let bounds = Kernel.CADBounds(minX: insertion.x, minY: insertion.y, maxX: insertion.x, maxY: insertion.y)
        return makeCommonEntity(
            kind: .insert,
            recordPairs: recordPairs,
            context: context,
            state: &state,
            path: nil,
            text: nil,
            blockName: blockName,
            transform: transform,
            bounds: bounds
        )
    }

    private mutating func makeImagePlaceholderEntity(
        type: String,
        recordPairs: [DXFPair],
        context: EntityContext,
        state: inout DXFParseState
    ) -> Kernel.CADEntity {
        let insertion = point(in: recordPairs, xCode: 10, yCode: 20) ?? fallbackPoint(in: recordPairs)
        let width = max(firstDouble(code: 13, in: recordPairs) ?? 1, 1)
        let height = max(firstDouble(code: 23, in: recordPairs) ?? 1, 1)
        let bounds = Kernel.CADBounds(
            minX: insertion.x,
            minY: insertion.y,
            maxX: insertion.x + width,
            maxY: insertion.y + height
        )
        let entry = Kernel.CADDrawingDiagnostics.Entry(
            severity: .warning,
            code: "CAD_DXF_IMAGE_PLACEHOLDER",
            message: "\(type) imported as placeholder.",
            detail: firstString(code: 5, in: recordPairs)
        )
        return makeCommonEntity(
            kind: .image,
            recordPairs: recordPairs,
            context: context,
            state: &state,
            path: nil,
            text: nil,
            blockName: nil,
            transform: .identity,
            bounds: bounds,
            diagnostics: Kernel.CADDrawingDiagnostics(entries: [entry]),
            unsupportedReason: "\(type) placeholder"
        )
    }

    private mutating func makeUnsupportedEntity(
        type: String,
        recordPairs: [DXFPair],
        context: EntityContext,
        reason: String,
        state: inout DXFParseState
    ) -> Kernel.CADEntity {
        let anchor = fallbackPoint(in: recordPairs)
        let bounds = Kernel.CADBounds(minX: anchor.x, minY: anchor.y, maxX: anchor.x, maxY: anchor.y)
        let entry = Kernel.CADDrawingDiagnostics.Entry(
            severity: .warning,
            code: "CAD_DXF_ENTITY_UNSUPPORTED",
            message: reason,
            detail: type
        )
        return makeCommonEntity(
            kind: .unsupported,
            recordPairs: recordPairs,
            context: context,
            state: &state,
            path: nil,
            text: nil,
            blockName: nil,
            transform: .identity,
            bounds: bounds,
            diagnostics: Kernel.CADDrawingDiagnostics(entries: [entry]),
            unsupportedReason: reason
        )
    }

    private mutating func makeCommonEntity(
        kind: Kernel.CADEntityKind,
        recordPairs: [DXFPair],
        context: EntityContext,
        state: inout DXFParseState,
        path: Kernel.CADPath?,
        text: Kernel.CADTextRun?,
        blockName: String?,
        transform: Kernel.CADTransform,
        bounds: Kernel.CADBounds,
        diagnostics: Kernel.CADDrawingDiagnostics = Kernel.CADDrawingDiagnostics(),
        unsupportedReason: String? = nil
    ) -> Kernel.CADEntity {
        let layerID = resolvedLayerID(from: recordPairs, context: context)
        ensureLayerExists(layerID: layerID, state: &state)
        let layoutID = resolvedLayoutID(from: recordPairs)
        let visibility = (firstInt(code: 60, in: recordPairs) ?? 0) == 1 ? Kernel.CADVisibility.hidden : .visible
        let entityColor = colorARGB(fromEntityPairs: recordPairs, defaultACI: nil)
        let lineType = firstString(code: 6, in: recordPairs) ?? "ByLayer"
        if lineType.caseInsensitiveCompare("ByLayer") != .orderedSame {
            state.ltypeNames.insert(lineType)
        }
        let entity = Kernel.CADEntity(
            kind: kind,
            layerID: layerID,
            layoutID: layoutID,
            color: entityColor,
            lineType: lineType,
            lineWeight: lineWeight(from: recordPairs) ?? -1,
            path: text == nil ? path : nil,
            text: text,
            blockName: blockName,
            transform: transform,
            bounds: bounds.isEmpty ? fallbackBounds(from: recordPairs) : bounds,
            visibility: visibility,
            sourceHandle: firstString(code: 5, in: recordPairs),
            diagnostics: diagnostics,
            unsupportedReason: unsupportedReason
        )
        state.diagnostics = state.diagnostics.merging(entity.diagnostics)
        return entity
    }

    private func consumeRecordPairs(pairs: [DXFPair], index: inout Int) -> [DXFPair] {
        var recordPairs: [DXFPair] = []
        while index < pairs.count, pairs[index].code != 0 {
            recordPairs.append(pairs[index])
            index += 1
        }
        return recordPairs
    }

    private func parseRecords(pairs: [DXFPair]) -> [DXFRecord] {
        var index = 0
        var records: [DXFRecord] = []
        while index < pairs.count {
            guard pairs[index].code == 0 else {
                index += 1
                continue
            }
            let type = normalizedType(pairs[index].value)
            index += 1
            let recordPairs = consumeRecordPairs(pairs: pairs, index: &index)
            records.append(DXFRecord(type: type, pairs: recordPairs))
        }
        return records
    }

    private func buildLayers(state: DXFParseState) -> [Kernel.CADLayer] {
        var layers = state.layersByID
        for entity in state.entities where layers[entity.layerID] == nil {
            layers[entity.layerID] = Kernel.CADLayer(id: entity.layerID, name: entity.layerID)
        }
        if layers.isEmpty {
            return [.default]
        }
        return layers.values.sorted { lhs, rhs in
            lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
    }

    private func buildTextStyles(state: DXFParseState) -> [Kernel.CADTextStyle] {
        if state.textStylesByID.isEmpty {
            return [.default]
        }
        return state.textStylesByID.values.sorted {
            $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
        }
    }

    private func buildLayouts(from entities: [Kernel.CADEntity]) -> [Kernel.CADLayout] {
        let hasPaper = entities.contains { $0.layoutID.caseInsensitiveCompare("paper") == .orderedSame }
        if hasPaper {
            return [.modelSpace, Kernel.CADLayout(id: "paper", name: "Paper", isModelSpace: false)]
        }
        return [.modelSpace]
    }

    private func units(for insUnits: Int) -> Kernel.CADUnits {
        switch insUnits {
        case 1:
            return Kernel.CADUnits(name: "inch", metersPerDrawingUnit: 0.0254)
        case 2:
            return Kernel.CADUnits(name: "foot", metersPerDrawingUnit: 0.3048)
        case 3:
            return Kernel.CADUnits(name: "mile", metersPerDrawingUnit: 1609.344)
        case 4:
            return Kernel.CADUnits(name: "millimeter", metersPerDrawingUnit: 0.001)
        case 5:
            return Kernel.CADUnits(name: "centimeter", metersPerDrawingUnit: 0.01)
        case 6:
            return Kernel.CADUnits(name: "meter", metersPerDrawingUnit: 1)
        case 7:
            return Kernel.CADUnits(name: "kilometer", metersPerDrawingUnit: 1000)
        case 20:
            return Kernel.CADUnits(name: "parsec", metersPerDrawingUnit: 3.085_677_581e16)
        default:
            return .unitless
        }
    }

    private func resolveTextStyle(named styleName: String, state: inout DXFParseState) -> Kernel.CADTextStyle {
        if let exact = state.textStylesByID[styleName] {
            return exact
        }
        if let matched = state.textStylesByID.values.first(where: {
            $0.id.caseInsensitiveCompare(styleName) == .orderedSame || $0.name.caseInsensitiveCompare(styleName) == .orderedSame
        }) {
            return matched
        }
        let style = Kernel.CADTextStyle(id: styleName, name: styleName)
        state.textStylesByID[styleName] = style
        return style
    }

    private func ensureLayerExists(layerID: String, state: inout DXFParseState) {
        if state.layersByID[layerID] == nil {
            state.layersByID[layerID] = Kernel.CADLayer(id: layerID, name: layerID)
        }
    }

    private func resolvedLayerID(from recordPairs: [DXFPair], context: EntityContext) -> String {
        if let layer = firstString(code: 8, in: recordPairs), !layer.isEmpty {
            return layer
        }
        switch context {
        case .modelSpace:
            return Kernel.CADLayer.default.id
        case let .block(defaultLayerID):
            return defaultLayerID ?? Kernel.CADLayer.default.id
        }
    }

    private func resolvedLayoutID(from recordPairs: [DXFPair]) -> String {
        if (firstInt(code: 67, in: recordPairs) ?? 0) == 1 {
            return "paper"
        }
        return Kernel.CADLayout.modelSpace.id
    }

    private func fallbackPoint(in pairs: [DXFPair]) -> Kernel.CADPoint {
        point(in: pairs, xCode: 10, yCode: 20)
            ?? point(in: pairs, xCode: 11, yCode: 21)
            ?? point(in: pairs, xCode: 13, yCode: 23)
            ?? point(in: pairs, xCode: 14, yCode: 24)
            ?? .zero
    }

    private func fallbackBounds(from pairs: [DXFPair]) -> Kernel.CADBounds {
        let anchor = fallbackPoint(in: pairs)
        return Kernel.CADBounds(minX: anchor.x, minY: anchor.y, maxX: anchor.x, maxY: anchor.y)
    }

    private func point(in pairs: [DXFPair], xCode: Int, yCode: Int) -> Kernel.CADPoint? {
        guard let x = firstDouble(code: xCode, in: pairs),
              let y = firstDouble(code: yCode, in: pairs)
        else {
            return nil
        }
        return Kernel.CADPoint(x: x, y: y)
    }

    private func points(in pairs: [DXFPair], xCode: Int, yCode: Int) -> [Kernel.CADPoint] {
        var result: [Kernel.CADPoint] = []
        var pendingX: Double?
        for pair in pairs {
            if pair.code == xCode {
                pendingX = parseDouble(pair.value)
                continue
            }
            if pair.code == yCode, let x = pendingX, let y = parseDouble(pair.value) {
                result.append(Kernel.CADPoint(x: x, y: y))
                pendingX = nil
            }
        }
        return result
    }

    private func joinedText(from pairs: [DXFPair], acceptedCodes: Set<Int>) -> String {
        pairs
            .filter { acceptedCodes.contains($0.code) }
            .map(\.value)
            .joined()
    }

    private func firstString(code: Int, in pairs: [DXFPair]) -> String? {
        pairs.first { $0.code == code }?.value
    }

    private func firstInt(code: Int, in pairs: [DXFPair]) -> Int? {
        firstString(code: code, in: pairs).flatMap(Int.init)
    }

    private func firstDouble(code: Int, in pairs: [DXFPair]) -> Double? {
        firstString(code: code, in: pairs).flatMap(parseDouble)
    }

    private func parseDouble(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed) {
            return value
        }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private func positiveOrNil(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func positiveOr(_ value: Double?, fallback: Double) -> Double {
        guard let value, value > 0 else { return fallback }
        return value
    }

    private func lineWeight(from pairs: [DXFPair]) -> Double? {
        guard let raw = firstInt(code: 370, in: pairs), raw >= 0 else { return nil }
        return Double(raw) / 100
    }

    private func colorARGB(fromEntityPairs pairs: [DXFPair], defaultACI: Int?) -> UInt32 {
        if let trueColor = firstInt(code: 420, in: pairs), trueColor > 0 {
            return 0xFF000000 | UInt32(trueColor & 0x00FF_FFFF)
        }
        if let aci = firstInt(code: 62, in: pairs) {
            if aci == 0 || abs(aci) == 256 {
                return 0x00000000
            }
            return aciToARGB(abs(aci))
        }
        if let defaultACI {
            return aciToARGB(abs(defaultACI))
        }
        return 0x00000000
    }

    private func aciToARGB(_ index: Int) -> UInt32 {
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
            return 0xFFFFFFFF
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

    private func normalizedType(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}
