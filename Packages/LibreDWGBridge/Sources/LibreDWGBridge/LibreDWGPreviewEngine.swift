import Foundation
import CoreGraphics

enum LibreDWGPreviewLoadMode {
    case full
    case geometryOnly

    var nativeParseMode: LibreDWGNativeParseMode {
        switch self {
        case .full:
            return .full
        case .geometryOnly:
            return .geometryOnly
        }
    }
}

enum LibreDWGPreviewLoadStage: Int, CaseIterable, Sendable {
    case readingGeometry
    case readingText
    case buildingIndex

    var title: String {
        switch self {
        case .readingGeometry:
            return "正在读取几何"
        case .readingText:
            return "正在读取文字"
        case .buildingIndex:
            return "正在建立索引"
        }
    }

    var detail: String {
        switch self {
        case .readingGeometry:
            return "正在读取线、圆、块参照、标注等基础图元。"
        case .readingText:
            return "正在读取文字、样式、编码和 SHX / 大字体信息。"
        case .buildingIndex:
            return "正在建立图层、视口和吸附索引，便于大图纸缩放和平移。"
        }
    }

    var systemImage: String {
        switch self {
        case .readingGeometry:
            return "line.diagonal"
        case .readingText:
            return "textformat"
        case .buildingIndex:
            return "square.grid.3x3"
        }
    }

    func longRunningMessage(elapsedSeconds: UInt64) -> String {
        switch self {
        case .readingGeometry:
            if elapsedSeconds >= 90 {
                return "仍在读取几何，图纸可能包含大量代理、AEC、天正对象或超大图元。"
            }
            if elapsedSeconds >= 45 {
                return "复杂图纸读取几何可能需要更久，仍在本机解析。"
            }
            if elapsedSeconds >= 20 {
                return "图纸较大，仍在读取几何实体。"
            }
            return detail
        case .readingText:
            if elapsedSeconds >= 90 {
                return "仍在读取文字和字体，图纸可能包含大量文字、标注或缺失 SHX 映射。"
            }
            if elapsedSeconds >= 45 {
                return "复杂图纸读取文字可能需要更久，仍在本机解析。"
            }
            if elapsedSeconds >= 20 {
                return "图纸文字较多，仍在读取文字和字体。"
            }
            return detail
        case .buildingIndex:
            if elapsedSeconds >= 45 {
                return "图元较多，正在建立空间索引以减少后续缩放卡顿。"
            }
            if elapsedSeconds >= 20 {
                return "正在整理图层、视口和吸附索引。"
            }
            return detail
        }
    }
}

enum LibreDWGPreviewCacheStatus: Equatable, Sendable {
    case checking
    case memoryHit
    case miss
    case fileChanged
    case waitingForActiveParse
    case stored
    case cancelled

    var title: String {
        switch self {
        case .checking:
            return "检查缓存"
        case .memoryHit:
            return "缓存命中"
        case .miss:
            return "建立缓存"
        case .fileChanged:
            return "文件已修改"
        case .waitingForActiveParse:
            return "等待已有解析"
        case .stored:
            return "已缓存"
        case .cancelled:
            return "已取消"
        }
    }

    var detail: String {
        switch self {
        case .checking:
            return "按文件路径和修改时间查找已解析结果。"
        case .memoryHit:
            return "文件未改变，直接复用本次会话内的解析结果。"
        case .miss:
            return "当前文件状态没有可用缓存，正在解析并建立缓存。"
        case .fileChanged:
            return "检测到同一路径图纸已变化，旧缓存已失效并重新解析。"
        case .waitingForActiveParse:
            return "同一图纸正在解析，完成后直接复用该结果。"
        case .stored:
            return "解析结果已按当前文件状态保存，未修改时再次打开会更快。"
        case .cancelled:
            return "已停止等待本次解析缓存。"
        }
    }

    var systemImage: String {
        switch self {
        case .checking:
            return "externaldrive.badge.magnifyingglass"
        case .memoryHit:
            return "bolt.fill"
        case .miss:
            return "externaldrive.badge.plus"
        case .fileChanged:
            return "arrow.triangle.2.circlepath"
        case .waitingForActiveParse:
            return "clock.arrow.circlepath"
        case .stored:
            return "checkmark.seal.fill"
        case .cancelled:
            return "xmark.circle"
        }
    }
}

typealias LibreDWGPreviewProgressHandler = @Sendable (LibreDWGPreviewLoadStage) async -> Void
typealias LibreDWGPreviewCacheHandler = @Sendable (LibreDWGPreviewCacheStatus) async -> Void

enum LibreDWGPreviewEngine {
    static func load(
        fileURL: URL,
        preferredCodePage: Int32?,
        preferredBigFont: Int32?,
        fontMappings: [LibreDWGFontMapping] = [],
        progress: LibreDWGPreviewProgressHandler? = nil,
        cacheStatus: LibreDWGPreviewCacheHandler? = nil,
        mode: LibreDWGPreviewLoadMode = .full
    ) async -> PreviewState {
        let ext = fileURL.pathExtension.lowercased()
        do {
            switch ext {
            case "dxf":
                await progress?(.readingGeometry)
                let model = try await Task.detached(priority: .userInitiated) {
                    try DXFPreviewParser.parse(
                        fileURL: fileURL,
                        preferredCodePage: preferredCodePage,
                        preferredBigFont: preferredBigFont,
                        fontMappings: fontMappings
                    )
                }.value
                await progress?(.buildingIndex)
                return .dxf(DXFPreparedPreview(model: model, sourceHint: nil))
            case "dwg":
                return await loadDWG(
                    fileURL: fileURL,
                    preferredCodePage: preferredCodePage,
                    preferredBigFont: preferredBigFont,
                    fontMappings: fontMappings,
                    progress: progress,
                    cacheStatus: cacheStatus,
                    mode: mode
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
        preferredBigFont: Int32?,
        fontMappings: [LibreDWGFontMapping],
        progress: LibreDWGPreviewProgressHandler?,
        cacheStatus: LibreDWGPreviewCacheHandler?,
        mode: LibreDWGPreviewLoadMode
    ) async -> PreviewState {
        if let preflightState = unsupportedDWGVersionState(fileURL: fileURL) {
            return preflightState
        }

        do {
            await progress?(mode == .full ? .readingText : .readingGeometry)
            let resolved = try await LibreDWGPreviewParseCoordinator.shared.parse(
                fileURL: fileURL,
                preferredCodePage: preferredCodePage,
                preferredBigFont: preferredBigFont,
                fontMappings: fontMappings,
                cacheStatus: cacheStatus,
                mode: mode
            )
            await progress?(.buildingIndex)
            let hint = [resolved.hint, DWGLiteSupportPolicy.parsedHint(fileName: fileURL.lastPathComponent, mode: mode)]
                .compactMap { $0 }
                .joined(separator: "，")
            return .dxf(DXFPreparedPreview(
                model: resolved.model,
                sourceHint: hint,
                isGeometryOnly: mode == .geometryOnly
            ))
        } catch {
            return .failed(dwgFailureMessage(
                fileURL: fileURL,
                preferredCodePage: preferredCodePage,
                preferredBigFont: preferredBigFont,
                nativeError: error
            ))
        }
    }

    static func cancelLoads(for fileURL: URL) async {
        await LibreDWGPreviewParseCoordinator.shared.cancel(fileURL: fileURL)
    }

    private static func dwgFailureMessage(
        fileURL: URL,
        preferredCodePage: Int32?,
        preferredBigFont: Int32?,
        nativeError: Error
    ) -> String {
        let codePageHint = preferredCodePage.map { "，编码 \(Int($0))" } ?? ""
        let bigFontHint = preferredBigFont.map { "，大字体 \(Int($0))" } ?? ""
        return "DWG Lite 本地解析失败：\(fileURL.lastPathComponent)\(codePageHint)\(bigFontHint)。\(nativeError.localizedDescription)"
    }

    private static func unsupportedDWGVersionState(fileURL: URL) -> PreviewState? {
        guard let header = readDWGHeaderMagic(fileURL: fileURL),
              header.hasPrefix("AC"),
              !DWGLiteSupportPolicy.supportedHeaders.contains(header) else {
            return nil
        }
        let hint = DWGLiteSupportPolicy.unsupportedVersionHint(header)
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

    var cacheCostMB: Double {
        model.dwgDiagnostic?.estimatedMemoryMB ?? Self.estimatedModelMemoryMB(model)
    }

    private static func estimatedModelMemoryMB(_ model: DXFPreviewModel) -> Double {
        var estimatedBytes = 0
        estimatedBytes += model.segments.count * MemoryLayout<DXFPreviewModel.Segment>.stride
        estimatedBytes += model.polylines.count * MemoryLayout<DXFPreviewModel.Polyline>.stride
        estimatedBytes += model.circles.count * MemoryLayout<DXFPreviewModel.Circle>.stride
        estimatedBytes += model.texts.count * MemoryLayout<DXFPreviewModel.TextEntity>.stride
        for polyline in model.polylines {
            estimatedBytes += polyline.points.count * MemoryLayout<CGPoint>.stride
        }
        for text in model.texts {
            estimatedBytes += text.value.utf8.count
            estimatedBytes += text.rawValue?.utf8.count ?? 0
            estimatedBytes += text.rawTextBytesHex?.utf8.count ?? 0
            estimatedBytes += text.styleName?.utf8.count ?? 0
            estimatedBytes += text.fontFile?.utf8.count ?? 0
            estimatedBytes += text.bigFontFile?.utf8.count ?? 0
        }
        return Double(max(estimatedBytes, 0)) / 1_048_576.0
    }
}

private struct LibreDWGPreviewParseKey: Hashable {
    let path: String
    let modifiedAt: TimeInterval
    let fileSize: UInt64
    let codePage: Int32
    let bigFont: Int32
    let fontMappingsSignature: String
    let mode: Int
}

private struct LibreDWGPreviewParseEntry {
    let id: UUID
    let task: Task<LibreDWGPreviewParseOutput, Error>
}

private actor LibreDWGPreviewParseCoordinator {
    static let shared = LibreDWGPreviewParseCoordinator()

    private var inFlight: [LibreDWGPreviewParseKey: LibreDWGPreviewParseEntry] = [:]
    private var completed: [LibreDWGPreviewParseKey: LibreDWGPreviewParseOutput] = [:]
    private var completedOrder: [LibreDWGPreviewParseKey] = []
    private var completedCostMB: [LibreDWGPreviewParseKey: Double] = [:]
    private let completedMemoryBudgetMB: Double = 96

    func parse(
        fileURL: URL,
        preferredCodePage: Int32?,
        preferredBigFont: Int32?,
        fontMappings: [LibreDWGFontMapping],
        cacheStatus: LibreDWGPreviewCacheHandler?,
        mode: LibreDWGPreviewLoadMode
    ) async throws -> LibreDWGPreviewParseOutput {
        let key = Self.makeKey(
            fileURL: fileURL,
            preferredCodePage: preferredCodePage,
            preferredBigFont: preferredBigFont,
            fontMappings: fontMappings,
            mode: mode
        )
        await cacheStatus?(.checking)
        if let cached = completed[key] {
            touchCompletedKey(key)
            await cacheStatus?(.memoryHit)
            return cached
        }

        let fileChanged = hasCompletedCacheForChangedFile(matching: key)
        if fileChanged {
            removeCompletedCacheEntriesForChangedFile(matching: key)
            await cacheStatus?(.fileChanged)
        }

        cancelStaleTasks(forPath: key.path, keeping: key)
        let task: Task<LibreDWGPreviewParseOutput, Error>
        if let existing = inFlight[key] {
            await cacheStatus?(.waitingForActiveParse)
            task = existing.task
        } else {
            if !fileChanged {
                await cacheStatus?(.miss)
            }
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
                    preferredBigFont: options.bigFont,
                    fontMappings: fontMappings,
                    mode: mode.nativeParseMode
                )
                try Task.checkCancellation()
                return LibreDWGPreviewParseOutput(model: model, hint: options.hint)
            }
            inFlight[key] = LibreDWGPreviewParseEntry(id: id, task: task)
            Task(priority: .utility) {
                do {
                    let output = try await task.value
                    self.finish(key: key, id: id, output: output)
                } catch {
                    self.clear(key: key, id: id)
                }
            }
        }

        // Native DWG parsing cannot be interrupted once inside LibreDWG; keep the
        // shared task alive so reopening the same drawing can reuse the result.
        let output = try await task.value
        await cacheStatus?(.stored)
        return output
    }

    private func clear(key: LibreDWGPreviewParseKey, id: UUID) {
        guard inFlight[key]?.id == id else { return }
        inFlight[key] = nil
    }

    private func finish(key: LibreDWGPreviewParseKey, id: UUID, output: LibreDWGPreviewParseOutput) {
        guard inFlight[key]?.id == id else { return }
        inFlight[key] = nil
        completed[key] = output
        completedCostMB[key] = max(output.cacheCostMB, 0.1)
        touchCompletedKey(key)
        trimCompletedCache(preserving: key)
    }

    private func trimCompletedCache(preserving preservedKey: LibreDWGPreviewParseKey) {
        while completedMemoryUsageMB > completedMemoryBudgetMB, completedOrder.count > 1 {
            guard let removedKey = completedOrder.first(where: { $0 != preservedKey }) else {
                break
            }
            removeCompletedCacheEntry(removedKey)
        }
    }

    private var completedMemoryUsageMB: Double {
        completedCostMB.values.reduce(0, +)
    }

    private func removeCompletedCacheEntry(_ key: LibreDWGPreviewParseKey) {
        completed[key] = nil
        completedCostMB[key] = nil
        completedOrder.removeAll { $0 == key }
    }

    private func touchCompletedKey(_ key: LibreDWGPreviewParseKey) {
        completedOrder.removeAll { $0 == key }
        completedOrder.append(key)
    }

    private func hasCompletedCacheForChangedFile(matching key: LibreDWGPreviewParseKey) -> Bool {
        completed.keys.contains { cachedKey in
            cachedKey.path == key.path &&
                (cachedKey.modifiedAt != key.modifiedAt || cachedKey.fileSize != key.fileSize)
        }
    }

    private func removeCompletedCacheEntriesForChangedFile(matching key: LibreDWGPreviewParseKey) {
        let staleKeys = completed.keys.filter { cachedKey in
            cachedKey.path == key.path &&
                (cachedKey.modifiedAt != key.modifiedAt || cachedKey.fileSize != key.fileSize)
        }
        for staleKey in staleKeys {
            removeCompletedCacheEntry(staleKey)
        }
    }

    private func cancelStaleTasks(forPath path: String, keeping keepKey: LibreDWGPreviewParseKey) {
        let staleKeys = inFlight.keys.filter { $0.path == path && $0 != keepKey }
        guard !staleKeys.isEmpty else { return }
        for staleKey in staleKeys {
            inFlight[staleKey]?.task.cancel()
            inFlight[staleKey] = nil
        }
    }

    func cancel(fileURL: URL) {
        let path = fileURL.path
        let keys = inFlight.keys.filter { $0.path == path }
        guard !keys.isEmpty else { return }
        for key in keys {
            inFlight[key]?.task.cancel()
            inFlight[key] = nil
        }
    }

    nonisolated private static func makeKey(
        fileURL: URL,
        preferredCodePage: Int32?,
        preferredBigFont: Int32?,
        fontMappings: [LibreDWGFontMapping],
        mode: LibreDWGPreviewLoadMode
    ) -> LibreDWGPreviewParseKey {
        let attributes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)) ?? [:]
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        return LibreDWGPreviewParseKey(
            path: fileURL.path,
            modifiedAt: modifiedAt,
            fileSize: fileSize,
            codePage: preferredCodePage ?? 0,
            bigFont: preferredBigFont ?? 0,
            fontMappingsSignature: fontMappingsSignature(fontMappings),
            mode: mode == .full ? 0 : 1
        )
    }

    nonisolated private static func fontMappingsSignature(_ fontMappings: [LibreDWGFontMapping]) -> String {
        fontMappings
            .filter { !$0.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "\($0.sourceKind):\($0.pattern):\($0.bigFont)" }
            .sorted()
            .joined(separator: "|")
    }

}
