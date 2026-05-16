import Foundation

extension CADPoC {
    struct CADImportResult {
        var database: SiteKeeperCADKernel.CADDatabase
        var trace: CADOpenTrace
    }

    struct LibreDWGNativeImportEngine: SiteKeeperCADKernel.CADImportEngine {
        typealias Kernel = SiteKeeperCADKernel

        let id = "sitekeeper.poc.dwg-native.line"
        private var convertedDWGImportID: String {
            "\(id).converted-dxf-artifact"
        }

        func canImport(file: Kernel.CADFile) -> Bool {
            switch file.format {
            case .dxf:
                return true
            case .dwg:
                return convertedDXFURL(for: file) != nil
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
                return try importDXFLines(
                    dxfFile: file,
                    sourceFile: file,
                    importSource: id,
                    convertedFromDWG: nil
                )
            case .dwg:
                guard let dxfURL = convertedDXFURL(for: file) else {
                    throw Kernel.CADImportError.unsupportedFormat(file.format)
                }
                let convertedFile = Kernel.CADFile(
                    url: dxfURL,
                    displayName: dxfURL.lastPathComponent,
                    format: .dxf
                )
                return try importDXFLines(
                    dxfFile: convertedFile,
                    sourceFile: file,
                    importSource: convertedDWGImportID,
                    convertedFromDWG: dxfURL
                )
            case .intermediateJSON, .unknown:
                throw Kernel.CADImportError.unsupportedFormat(file.format)
            }
        }

        private func importDXFLines(
            dxfFile: Kernel.CADFile,
            sourceFile: Kernel.CADFile,
            importSource: String,
            convertedFromDWG dxfURL: URL?
        ) throws -> CADImportResult {
            let data = try Data(contentsOf: dxfFile.url)
            let contents = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? String(decoding: data, as: UTF8.self)
            let records = DXFLineOnlyParser.parse(contents)
            let layerIDs = Set(records.map(\.layerID))
            let layers = layerIDs.isEmpty
                ? [Kernel.CADLayer.default]
                : layerIDs.sorted().map { Kernel.CADLayer(id: $0, name: $0) }
            let entities = records.map(makeLineEntity(record:))
            let bounds = entities.reduce(Kernel.CADBounds.empty) { $0.union($1.bounds) }
            var diagnostics = records.isEmpty
                ? noLineDiagnostics(file: sourceFile)
                : Kernel.CADDrawingDiagnostics()
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
            database.setImportMetadata(
                geometryParsed: !entities.isEmpty,
                isMetadataOnly: entities.isEmpty,
                importSource: importSource
            )

            let trace = CADOpenTrace(
                fileName: sourceFile.displayName,
                importSource: importSource,
                rawLineCount: records.count,
                entityCount: database.entityCount,
                drawableEntityCount: database.drawableEntityCount,
                bounds: database.extents,
                openedForRender: database.drawableEntityCount > 0
            )
            return CADImportResult(database: database, trace: trace)
        }

        private func makeLineEntity(record: DXFLineOnlyParser.LineRecord) -> Kernel.CADEntity {
            let path = Kernel.CADPath(elements: [
                .move(to: record.start),
                .line(to: record.end)
            ])
            return Kernel.CADEntity(
                id: UUID(),
                kind: .line,
                layerID: record.layerID,
                layoutID: Kernel.CADLayout.modelSpace.id,
                color: 0xFF0A84FF,
                lineType: "Continuous",
                lineWeight: 2,
                path: path,
                bounds: path.bounds,
                visibility: .visible,
                sourceHandle: record.handle
            )
        }

        private func noLineDiagnostics(file: Kernel.CADFile) -> Kernel.CADDrawingDiagnostics {
            Kernel.CADDrawingDiagnostics(entries: [
                Kernel.CADDrawingDiagnostics.Entry(
                    severity: .warning,
                    code: "CAD_POC_NO_LINE_ENTITIES",
                    message: "The CAD Metal PoC imported no LINE entities.",
                    detail: file.displayName
                )
            ])
        }

        private func convertedDXFURL(for file: Kernel.CADFile) -> URL? {
            let candidates = [
                file.url.deletingPathExtension().appendingPathExtension("dxf"),
                file.url.appendingPathExtension("dxf")
            ]
            return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
        }
    }
}

private enum DXFLineOnlyParser {
    typealias Kernel = SiteKeeperCADKernel

    struct Pair {
        var code: Int
        var value: String
    }

    struct LineRecord {
        var layerID: String
        var handle: String?
        var start: Kernel.CADPoint
        var end: Kernel.CADPoint
    }

    static func parse(_ contents: String) -> [LineRecord] {
        let pairs = decodePairs(contents)
        let entityPairs = entitiesSection(from: pairs)
        var records: [LineRecord] = []
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

            guard type == "LINE", let line = makeLine(from: recordPairs) else { continue }
            records.append(line)
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

    private static func entitiesSection(from pairs: [Pair]) -> [Pair] {
        var index = 0
        while index < pairs.count {
            if pairs[index].code == 0,
               pairs[index].value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "SECTION",
               index + 1 < pairs.count,
               pairs[index + 1].code == 2,
               pairs[index + 1].value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "ENTITIES" {
                index += 2
                var section: [Pair] = []
                while index < pairs.count {
                    if pairs[index].code == 0,
                       pairs[index].value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "ENDSEC" {
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

    private static func makeLine(from pairs: [Pair]) -> LineRecord? {
        guard
            let startX = firstDouble(code: 10, in: pairs),
            let startY = firstDouble(code: 20, in: pairs),
            let endX = firstDouble(code: 11, in: pairs),
            let endY = firstDouble(code: 21, in: pairs)
        else {
            return nil
        }
        let layer = firstString(code: 8, in: pairs)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LineRecord(
            layerID: (layer?.isEmpty == false ? layer : nil) ?? Kernel.CADLayer.default.id,
            handle: firstString(code: 5, in: pairs),
            start: Kernel.CADPoint(x: startX, y: startY),
            end: Kernel.CADPoint(x: endX, y: endY)
        )
    }

    private static func firstDouble(code: Int, in pairs: [Pair]) -> Double? {
        guard let value = pairs.first(where: { $0.code == code })?.value else { return nil }
        return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func firstString(code: Int, in pairs: [Pair]) -> String? {
        pairs.first(where: { $0.code == code })?.value
    }
}
