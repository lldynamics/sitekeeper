import Foundation

extension NativeCAD {
    struct CADDiagnosticLogEntry: Equatable, Codable {
        let timestamp: String
        let category: String
        let message: String
        let payloadJSON: String?
        let coalescingKey: String?
    }

    enum CADDiagnosticLog {
        private static let maximumEntryCount = 200
        private static let lock = NSLock()
        private static var entries: [CADDiagnosticLogEntry] = []

        static func record(
            category: String,
            message: String,
            payloadJSON: String? = nil,
            coalescingKey: String? = nil
        ) {
            let entry = CADDiagnosticLogEntry(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                category: category,
                message: message,
                payloadJSON: payloadJSON,
                coalescingKey: coalescingKey
            )
            lock.lock()
            defer { lock.unlock() }
            if let coalescingKey,
               let index = entries.lastIndex(where: { $0.coalescingKey == coalescingKey }) {
                entries[index] = entry
            } else {
                entries.append(entry)
            }
            if entries.count > maximumEntryCount {
                entries.removeFirst(entries.count - maximumEntryCount)
            }
        }

        static func recordEncoded<T: Encodable>(
            category: String,
            message: String,
            payload: T,
            coalescingKey: String? = nil
        ) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let payloadJSON = (try? encoder.encode(payload))
                .flatMap { String(data: $0, encoding: .utf8) }
            record(
                category: category,
                message: message,
                payloadJSON: payloadJSON,
                coalescingKey: coalescingKey
            )
        }

        static func recentEntries(limit: Int = maximumEntryCount) -> [CADDiagnosticLogEntry] {
            lock.lock()
            defer { lock.unlock() }
            return Array(entries.suffix(max(0, limit)))
        }

        #if DEBUG
        static func removeAllForTesting() {
            lock.lock()
            defer { lock.unlock() }
            entries.removeAll()
        }
        #endif
    }

    struct CADTextImportSample: Equatable, Codable {
        var entityId: String
        var entityType: String
        var layerID: String
        var layoutID: String
        var sourceHandle: String?
        var rawText: String
        var decodedText: String
        var normalizedText: String
        var displayText: String
        var attributeTag: String?
        var rawTextBytesHex: String?
        var textStyleName: String
        var fontFile: String?
        var bigFontFile: String?
        var selectedFontName: String
        var fallbackReason: String?
        var warnings: [String]
        var bounds: SiteKeeperCADKernel.CADBounds
    }

    struct CADOpenTrace: Equatable, Codable {
        var fileName: String
        var importSource: String
        var rawLineCount: Int
        var rawPolylineCount: Int
        var rawCircleCount: Int
        var rawArcCount: Int
        var rawInsertCount: Int
        var rawEllipseCount: Int
        var rawSplineCount: Int
        var rawFilledShapeCount: Int
        var rawDimensionCount: Int
        var rawHatchCount: Int
        var rawTextCount: Int
        var rawTextEntityCount: Int
        var rawMTextEntityCount: Int
        var rawAttribEntityCount: Int
        var rawAttdefEntityCount: Int
        var rawProxyEntityCount: Int
        var rawTianzhengProxyCount: Int
        var rawMLeaderCount: Int
        var rawViewportCount: Int
        var mleaderTextCandidateCount: Int
        var proxyTextCandidateCount: Int
        var tianzhengTextCandidateCount: Int
        var expandedInsertEntityCount: Int
        var exportedTextEntityCount: Int
        var exportedMTextEntityCount: Int
        var exportedAttribEntityCount: Int
        var exportedProxyEntityCount: Int
        var exportedTianzhengProxyCount: Int
        var exportedMLeaderTextCount: Int
        var exportedViewportCount: Int
        var skippedViewportCount: Int
        var entityCount: Int
        var drawableEntityCount: Int
        var renderCommandCount: Int
        var bounds: SiteKeeperCADKernel.CADBounds
        var openedForRender: Bool
        var importCacheHit: Bool
        var importMilliseconds: Double
        var failureMessage: String?
        var textSamples: [CADTextImportSample]

        init(
            fileName: String,
            importSource: String,
            rawLineCount: Int = 0,
            rawPolylineCount: Int = 0,
            rawCircleCount: Int = 0,
            rawArcCount: Int = 0,
            rawInsertCount: Int = 0,
            rawEllipseCount: Int = 0,
            rawSplineCount: Int = 0,
            rawFilledShapeCount: Int = 0,
            rawDimensionCount: Int = 0,
            rawHatchCount: Int = 0,
            rawTextCount: Int = 0,
            rawTextEntityCount: Int = 0,
            rawMTextEntityCount: Int = 0,
            rawAttribEntityCount: Int = 0,
            rawAttdefEntityCount: Int = 0,
            rawProxyEntityCount: Int = 0,
            rawTianzhengProxyCount: Int = 0,
            rawMLeaderCount: Int = 0,
            rawViewportCount: Int = 0,
            mleaderTextCandidateCount: Int = 0,
            proxyTextCandidateCount: Int = 0,
            tianzhengTextCandidateCount: Int = 0,
            expandedInsertEntityCount: Int = 0,
            exportedTextEntityCount: Int = 0,
            exportedMTextEntityCount: Int = 0,
            exportedAttribEntityCount: Int = 0,
            exportedProxyEntityCount: Int = 0,
            exportedTianzhengProxyCount: Int = 0,
            exportedMLeaderTextCount: Int = 0,
            exportedViewportCount: Int = 0,
            skippedViewportCount: Int = 0,
            entityCount: Int = 0,
            drawableEntityCount: Int = 0,
            renderCommandCount: Int = 0,
            bounds: SiteKeeperCADKernel.CADBounds = .empty,
            openedForRender: Bool? = nil,
            importCacheHit: Bool = false,
            importMilliseconds: Double = 0,
            failureMessage: String? = nil,
            textSamples: [CADTextImportSample] = []
        ) {
            self.fileName = fileName
            self.importSource = importSource
            self.rawLineCount = rawLineCount
            self.rawPolylineCount = rawPolylineCount
            self.rawCircleCount = rawCircleCount
            self.rawArcCount = rawArcCount
            self.rawInsertCount = rawInsertCount
            self.rawEllipseCount = rawEllipseCount
            self.rawSplineCount = rawSplineCount
            self.rawFilledShapeCount = rawFilledShapeCount
            self.rawDimensionCount = rawDimensionCount
            self.rawHatchCount = rawHatchCount
            self.rawTextCount = rawTextCount
            self.rawTextEntityCount = rawTextEntityCount
            self.rawMTextEntityCount = rawMTextEntityCount
            self.rawAttribEntityCount = rawAttribEntityCount
            self.rawAttdefEntityCount = rawAttdefEntityCount
            self.rawProxyEntityCount = rawProxyEntityCount
            self.rawTianzhengProxyCount = rawTianzhengProxyCount
            self.rawMLeaderCount = rawMLeaderCount
            self.rawViewportCount = rawViewportCount
            self.mleaderTextCandidateCount = mleaderTextCandidateCount
            self.proxyTextCandidateCount = proxyTextCandidateCount
            self.tianzhengTextCandidateCount = tianzhengTextCandidateCount
            self.expandedInsertEntityCount = expandedInsertEntityCount
            self.exportedTextEntityCount = exportedTextEntityCount
            self.exportedMTextEntityCount = exportedMTextEntityCount
            self.exportedAttribEntityCount = exportedAttribEntityCount
            self.exportedProxyEntityCount = exportedProxyEntityCount
            self.exportedTianzhengProxyCount = exportedTianzhengProxyCount
            self.exportedMLeaderTextCount = exportedMLeaderTextCount
            self.exportedViewportCount = exportedViewportCount
            self.skippedViewportCount = skippedViewportCount
            self.entityCount = entityCount
            self.drawableEntityCount = drawableEntityCount
            self.renderCommandCount = renderCommandCount
            self.bounds = bounds
            self.openedForRender = openedForRender ?? (drawableEntityCount > 0 && renderCommandCount > 0)
            self.importCacheHit = importCacheHit
            self.importMilliseconds = importMilliseconds
            self.failureMessage = failureMessage
            self.textSamples = textSamples
        }

        static func unsupported(
            fileName: String,
            importSource: String,
            failureMessage: String? = nil
        ) -> CADOpenTrace {
            CADOpenTrace(
                fileName: fileName,
                importSource: importSource,
                rawLineCount: 0,
                rawPolylineCount: 0,
                rawCircleCount: 0,
                rawArcCount: 0,
                rawEllipseCount: 0,
                rawSplineCount: 0,
                rawFilledShapeCount: 0,
                rawDimensionCount: 0,
                rawHatchCount: 0,
                rawTextCount: 0,
                entityCount: 0,
                drawableEntityCount: 0,
                renderCommandCount: 0,
                bounds: .empty,
                openedForRender: false,
                failureMessage: failureMessage
            )
        }
    }
}
