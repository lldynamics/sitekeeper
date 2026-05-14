import Foundation

enum LibreDWGPreviewEngine {
    static func load(
        fileURL: URL,
        preferredCodePage: Int32?,
        preferredBigFont: Int32?
    ) async -> PreviewState {
        let ext = fileURL.pathExtension.lowercased()
        do {
            switch ext {
            case "dxf":
                let model = try await Task.detached(priority: .userInitiated) {
                    try DXFPreviewParser.parse(
                        fileURL: fileURL,
                        preferredCodePage: preferredCodePage,
                        preferredBigFont: preferredBigFont
                    )
                }.value
                return .dxf(model, nil)
            case "dwg":
                return await loadDWG(
                    fileURL: fileURL,
                    preferredCodePage: preferredCodePage,
                    preferredBigFont: preferredBigFont
                )
            default:
                return .failed("不支持的图纸格式：\(ext.uppercased())")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func loadDWG(
        fileURL: URL,
        preferredCodePage: Int32?,
        preferredBigFont: Int32?
    ) async -> PreviewState {
        if let preflightState = unsupportedDWGVersionState(fileURL: fileURL) {
            return preflightState
        }

        do {
            let resolved = try await LibreDWGPreviewParseCoordinator.shared.parse(
                fileURL: fileURL,
                preferredCodePage: preferredCodePage,
                preferredBigFont: preferredBigFont
            )
            let hint = [resolved.hint, "LibreDWG 已解析 DWG：\(fileURL.lastPathComponent)"]
                .compactMap { $0 }
                .joined(separator: "，")
            return .dxf(resolved.model, hint)
        } catch {
            return .failed(dwgFailureMessage(
                fileURL: fileURL,
                preferredCodePage: preferredCodePage,
                preferredBigFont: preferredBigFont,
                nativeError: error
            ))
        }
    }

    private static func dwgFailureMessage(
        fileURL: URL,
        preferredCodePage: Int32?,
        preferredBigFont: Int32?,
        nativeError: Error
    ) -> String {
        let codePageHint = preferredCodePage.map { "，编码 \(Int($0))" } ?? ""
        let bigFontHint = preferredBigFont.map { "，大字体 \(Int($0))" } ?? ""
        return "LibreDWG 原生解析失败：\(fileURL.lastPathComponent)\(codePageHint)\(bigFontHint)。\(nativeError.localizedDescription)"
    }

    private static let bundledLibreDWGSupportedHeaders: Set<String> = [
        "AC1009",
        "AC1012",
        "AC1014",
        "AC1015",
        "AC1018",
        "AC1021",
        "AC1024",
        "AC1027",
        "AC1032",
        "AC1036",
    ]

    private static func unsupportedDWGVersionState(fileURL: URL) -> PreviewState? {
        guard let header = readDWGHeaderMagic(fileURL: fileURL),
              header.hasPrefix("AC"),
              !bundledLibreDWGSupportedHeaders.contains(header) else {
            return nil
        }
        let hint = "当前内置 LibreDWG 暂不支持 \(header) DWG，已跳过原生解析以避免长时间停在加载中。"
        if let info = try? DWGMetadata.from(fileURL: fileURL, hints: [hint]) {
            return .dwgMetadata(info)
        }
        return .failed(hint)
    }

    private static func readDWGHeaderMagic(fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 6),
              data.count == 6 else { return nil }
        return String(data: data, encoding: .ascii)
    }
}

private struct DWGTextRenderOptions {
    let codePage: Int32?
    let bigFont: Int32?
    let hint: String?
}

private func resolvedDWGTextOptions(
    fileURL: URL,
    preferredCodePage: Int32?,
    preferredBigFont: Int32?
) -> DWGTextRenderOptions {
    DWGTextRenderOptions(
        codePage: preferredCodePage,
        bigFont: preferredBigFont,
        hint: nil
    )
}

private struct LibreDWGPreviewParseOutput {
    let model: DXFPreviewModel
    let hint: String?
}

private struct LibreDWGPreviewParseKey: Hashable {
    let path: String
    let modifiedAt: TimeInterval
    let fileSize: UInt64
    let codePage: Int32
    let bigFont: Int32
}

private struct LibreDWGPreviewParseEntry {
    let id: UUID
    let task: Task<LibreDWGPreviewParseOutput, Error>
}

private actor LibreDWGPreviewParseCoordinator {
    static let shared = LibreDWGPreviewParseCoordinator()

    private var inFlight: [LibreDWGPreviewParseKey: LibreDWGPreviewParseEntry] = [:]

    func parse(
        fileURL: URL,
        preferredCodePage: Int32?,
        preferredBigFont: Int32?
    ) async throws -> LibreDWGPreviewParseOutput {
        let key = Self.makeKey(
            fileURL: fileURL,
            preferredCodePage: preferredCodePage,
            preferredBigFont: preferredBigFont
        )
        cancelStaleTasks(forPath: key.path, keeping: key)
        let task: Task<LibreDWGPreviewParseOutput, Error>
        if let existing = inFlight[key] {
            task = existing.task
        } else {
            let id = UUID()
            task = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                let options = resolvedDWGTextOptions(
                    fileURL: fileURL,
                    preferredCodePage: preferredCodePage,
                    preferredBigFont: preferredBigFont
                )
                let model = try LibreDWGNativeParser.parse(
                    fileURL: fileURL,
                    preferredCodePage: options.codePage,
                    preferredBigFont: options.bigFont
                )
                try Task.checkCancellation()
                return LibreDWGPreviewParseOutput(model: model, hint: options.hint)
            }
            inFlight[key] = LibreDWGPreviewParseEntry(id: id, task: task)
            Task(priority: .utility) {
                _ = try? await task.value
                self.clear(key: key, id: id)
            }
        }

        return try await withTaskCancellationHandler(operation: {
            try await task.value
        }, onCancel: {
            task.cancel()
        })
    }

    private func clear(key: LibreDWGPreviewParseKey, id: UUID) {
        guard inFlight[key]?.id == id else { return }
        inFlight[key] = nil
    }

    private func cancelStaleTasks(forPath path: String, keeping keepKey: LibreDWGPreviewParseKey) {
        let staleKeys = inFlight.keys.filter { $0.path == path && $0 != keepKey }
        guard !staleKeys.isEmpty else { return }
        for staleKey in staleKeys {
            inFlight[staleKey]?.task.cancel()
            inFlight[staleKey] = nil
        }
    }

    nonisolated private static func makeKey(
        fileURL: URL,
        preferredCodePage: Int32?,
        preferredBigFont: Int32?
    ) -> LibreDWGPreviewParseKey {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)) ?? [:]
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        return LibreDWGPreviewParseKey(
            path: fileURL.path,
            modifiedAt: modifiedAt,
            fileSize: fileSize,
            codePage: preferredCodePage ?? 0,
            bigFont: preferredBigFont ?? 0
        )
    }

}
