import Foundation

extension DXFBasic2DParser {
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


    static func parseEntityRecords(
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

            let parsedRecords: [EntityRecord]
            if type == "POLYLINE" {
                let vertexPairs = consumePolylineVertices(from: entityPairs, index: &index)
                parsedRecords = makePolyline(from: recordPairs, vertexPairs: vertexPairs).map { [$0] } ?? []
            } else if type == "INSERT" || type == "MINSERT" {
                if var insert = makeInsert(type: type, from: recordPairs) {
                    insert.attachedAttributes = consumeInsertAttributes(
                        from: entityPairs,
                        index: &index,
                        textStylesByID: textStylesByID
                    )
                    parsedRecords = [insert]
                } else {
                    parsedRecords = []
                }
            } else {
                parsedRecords = makeEntities(type: type, pairs: recordPairs, textStylesByID: textStylesByID)
            }
            for parsedRecord in parsedRecords {
                var record = parsedRecord
                record.lineType = lineType(from: recordPairs) ?? record.lineType
                record.layoutID = layoutID(from: recordPairs) ?? record.layoutID
                records.append(record)
            }
        }
        return records
    }


    static func decodePairs(_ contents: String) -> [Pair] {
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


    static func tablesSection(from pairs: [Pair]) -> [Pair] {
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


    static func blocksSection(from pairs: [Pair]) -> [Pair] {
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


    static func entitiesSection(from pairs: [Pair]) -> [Pair] {
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


    static func parseBlocks(
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


    static func parseLayers(from tablePairs: [Pair]) -> [String: Kernel.CADLayer] {
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


    static func parseLayerRecords(from pairs: [Pair]) -> [Kernel.CADLayer] {
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


    static func parseTextStyles(from tablePairs: [Pair]) -> [String: Kernel.CADTextStyle] {
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


    static func parseTextStyleRecords(from pairs: [Pair]) -> [Kernel.CADTextStyle] {
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


    static func buildLayouts(from records: [EntityRecord]) -> [Kernel.CADLayout] {
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


    static func consumePolylineVertices(from pairs: [Pair], index: inout Int) -> [[Pair]] {
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


    static func consumeInsertAttributes(
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

}
