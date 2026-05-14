import Foundation
import SwiftUI

private enum LibreDWGLoadingMessages {
    static let initial = LibreDWGPreviewLoadStage.readingGeometry.detail
    static let progressSeconds: [UInt64] = [8, 20, 45, 90]
}

public struct LibreDWGBridgePreview: View {
    public let fileURL: URL
    public let preferredCodePage: Int32?
    public let preferredBigFont: Int32?
    public let fontMappings: [LibreDWGFontMapping]
    public let initialViewState: LibreDWGCanvasViewStateSnapshot?
    public let onCanvasTransformChange: (LibreDWGCanvasTransformSnapshot) -> Void
    public let onViewStateChange: (LibreDWGCanvasViewStateSnapshot) -> Void
    public let onTextRepairPresetRequest: (Int32?, Int32?) -> Void
    public let onSnapPointsChange: ([LibreDWGSnapPointPayload]) -> Void
    public let onTextAutoDetectionChange: (LibreDWGTextAutoDetectionSnapshot) -> Void

    @State private var state: PreviewState = .loading
    @State private var loadTask: Task<Void, Never>?
    @State private var loadProgressTask: Task<Void, Never>?
    @State private var loadToken = UUID()
    @State private var textLoadTask: Task<Void, Never>?
    @State private var textLoadProgressTask: Task<Void, Never>?
    @State private var textLoadToken = UUID()
    @State private var wasCancelled = false
    @State private var loadingStage: LibreDWGPreviewLoadStage = .readingGeometry
    @State private var loadingStages: [LibreDWGPreviewLoadStage] = [.readingGeometry, .buildingIndex]
    @State private var fullTextLoadingStage: LibreDWGPreviewLoadStage = .readingText
    @State private var fullTextLoadMessage = LibreDWGPreviewLoadStage.readingText.detail
    @State private var isLoadingFullText = false
    @State private var fullTextLoadError: String?
    @State private var loadingMessage = LibreDWGLoadingMessages.initial

    public init(
        fileURL: URL,
        preferredCodePage: Int32? = nil,
        preferredBigFont: Int32? = nil,
        fontMappings: [LibreDWGFontMapping] = [],
        initialViewState: LibreDWGCanvasViewStateSnapshot? = nil,
        onCanvasTransformChange: @escaping (LibreDWGCanvasTransformSnapshot) -> Void = { _ in },
        onViewStateChange: @escaping (LibreDWGCanvasViewStateSnapshot) -> Void = { _ in },
        onTextRepairPresetRequest: @escaping (Int32?, Int32?) -> Void = { _, _ in },
        onSnapPointsChange: @escaping ([LibreDWGSnapPointPayload]) -> Void = { _ in },
        onTextAutoDetectionChange: @escaping (LibreDWGTextAutoDetectionSnapshot) -> Void = { _ in }
    ) {
        self.fileURL = fileURL
        self.preferredCodePage = preferredCodePage
        self.preferredBigFont = preferredBigFont
        self.fontMappings = fontMappings
        self.initialViewState = initialViewState
        self.onCanvasTransformChange = onCanvasTransformChange
        self.onViewStateChange = onViewStateChange
        self.onTextRepairPresetRequest = onTextRepairPresetRequest
        self.onSnapPointsChange = onSnapPointsChange
        self.onTextAutoDetectionChange = onTextAutoDetectionChange
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .task(id: taskIdentity) {
                startLoadingPreview()
            }
            .onDisappear {
                cancelActivePreviewLoading()
            }
    }

    private var taskIdentity: String {
        "\(fileURL.path)#\(preferredCodePage.map(String.init) ?? "auto")#\(preferredBigFont.map(String.init) ?? "auto")#\(fontMappingsIdentity)"
    }

    private var fontMappingsIdentity: String {
        fontMappings
            .map { "\($0.sourceKind):\($0.pattern):\($0.bigFont)" }
            .sorted()
            .joined(separator: "|")
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            if wasCancelled {
                cancelledLoadingView
            } else {
                loadingProgressView
            }
        case .dxf(let preview):
            ZStack(alignment: .bottomTrailing) {
                DXFCanvasPreview(
                    model: preview.model,
                    sourceHint: preview.sourceHint,
                    geometryIndex: preview.geometryIndex,
                    fileURL: fileURL,
                    initialViewState: initialViewState,
                    onCanvasTransformChange: onCanvasTransformChange,
                    onViewStateChange: onViewStateChange,
                    onTextRepairPresetRequest: onTextRepairPresetRequest,
                    onSnapPointsChange: onSnapPointsChange
                )
                if preview.isGeometryOnly && fileURL.pathExtension.lowercased() == "dwg" {
                    fullTextLoadControl
                }
            }
        case .dwgMetadata(let info):
            DWGMetadataPreview(fileURL: fileURL, info: info)
        case .failed(let reason):
            ContentUnavailableView(
                "图纸预览失败",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(reason)
            )
        }
    }

    private var loadingProgressView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 6) {
                Text(loadingStage.title)
                    .font(.headline)
                Text(loadingMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            loadingStageRows(stages: loadingStages, currentStage: loadingStage)

            Button(role: .cancel) {
                cancelActivePreviewLoading(markCancelled: true)
            } label: {
                Label("取消解析", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text("取消会停止当前等待和后续索引/文字流程；底层 DWG 读取已进入原生库时，可能需要返回后才完全释放。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(24)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cancelledLoadingView: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("已取消解析")
                    .font(.headline)
                Text("当前图纸没有写入任何 CAD 原文件；需要时可以重新打开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                startLoadingPreview()
            } label: {
                Label("重新打开", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(24)
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadingStageRows(
        stages: [LibreDWGPreviewLoadStage],
        currentStage: LibreDWGPreviewLoadStage
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(stages, id: \.self) { stage in
                let state = loadingStageState(stage, currentStage: currentStage, stages: stages)
                HStack(spacing: 8) {
                    Image(systemName: state.iconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(state.tint)
                        .frame(width: 18)
                    Text(stage.title.replacingOccurrences(of: "正在", with: ""))
                        .font(.caption.weight(stage == currentStage ? .semibold : .regular))
                        .foregroundStyle(stage == currentStage ? .primary : .secondary)
                    Spacer(minLength: 8)
                    Text(state.title)
                        .font(.caption2)
                        .foregroundStyle(state.tint)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 360)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func loadingStageState(
        _ stage: LibreDWGPreviewLoadStage,
        currentStage: LibreDWGPreviewLoadStage,
        stages: [LibreDWGPreviewLoadStage]
    ) -> (title: String, iconName: String, tint: Color) {
        guard let stageIndex = stages.firstIndex(of: stage),
              let currentIndex = stages.firstIndex(of: currentStage) else {
            return ("等待", "circle", .secondary)
        }
        if stageIndex < currentIndex {
            return ("完成", "checkmark.circle.fill", .green)
        }
        if stageIndex == currentIndex {
            return ("进行中", stage.systemImage, .accentColor)
        }
        return ("等待", "circle", .secondary)
    }

    @MainActor
    private func startLoadingPreview() {
        cancelLoadingPreview()
        state = .loading
        wasCancelled = false
        fullTextLoadError = nil
        let token = UUID()
        loadToken = token
        let identity = taskIdentity
        let currentFileURL = fileURL
        let currentPreferredCodePage = preferredCodePage
        let currentPreferredBigFont = preferredBigFont
        let currentFontMappings = fontMappings
        let shouldStageDWG = currentFileURL.pathExtension.lowercased() == "dwg"
        loadingStages = shouldStageDWG ? [.readingGeometry, .buildingIndex] : [.readingGeometry, .buildingIndex]
        loadingStage = .readingGeometry
        loadingMessage = loadingStage.detail

        let task = Task.detached(priority: .userInitiated) {
            let progress: LibreDWGPreviewProgressHandler = { stage in
                await MainActor.run {
                    guard identity == taskIdentity, loadToken == token else { return }
                    loadingStage = stage
                    loadingMessage = stage.detail
                }
            }
            if shouldStageDWG {
                let loadedState = await LibreDWGPreviewEngine.load(
                    fileURL: currentFileURL,
                    preferredCodePage: currentPreferredCodePage,
                    preferredBigFont: currentPreferredBigFont,
                    fontMappings: currentFontMappings,
                    progress: progress,
                    mode: .geometryOnly
                )
                await MainActor.run {
                    guard identity == taskIdentity, loadToken == token else { return }
                    loadProgressTask?.cancel()
                    loadProgressTask = nil
                    loadTask = nil
                    state = loadedState
                }
            } else {
                let loadedState = await LibreDWGPreviewEngine.load(
                    fileURL: currentFileURL,
                    preferredCodePage: currentPreferredCodePage,
                    preferredBigFont: currentPreferredBigFont,
                    fontMappings: currentFontMappings,
                    progress: progress
                )
                await MainActor.run {
                    guard identity == taskIdentity, loadToken == token else { return }
                    loadProgressTask?.cancel()
                    loadProgressTask = nil
                    loadTask = nil
                    state = loadedState
                    postTextAutoDetectionIfAvailable(for: loadedState, fileURL: currentFileURL, fontMappings: currentFontMappings)
                }
            }
        }

        loadTask = task
        loadProgressTask = Task.detached(priority: .utility) {
            var elapsed: UInt64 = 0
            for seconds in LibreDWGLoadingMessages.progressSeconds {
                let delay = seconds > elapsed ? seconds - elapsed : 0
                elapsed = seconds
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard identity == taskIdentity, loadToken == token else { return }
                    loadingMessage = loadingStage.longRunningMessage(elapsedSeconds: seconds)
                }
            }
        }
    }

    @MainActor
    private func cancelLoadingPreview() {
        loadTask?.cancel()
        loadTask = nil
        loadToken = UUID()
        loadProgressTask?.cancel()
        loadProgressTask = nil
        textLoadTask?.cancel()
        textLoadTask = nil
        textLoadProgressTask?.cancel()
        textLoadProgressTask = nil
        textLoadToken = UUID()
        isLoadingFullText = false
        fullTextLoadError = nil
    }

    @MainActor
    private func cancelActivePreviewLoading(markCancelled: Bool = false) {
        let currentFileURL = fileURL
        cancelLoadingPreview()
        Task.detached(priority: .utility) {
            await LibreDWGPreviewEngine.cancelLoads(for: currentFileURL)
        }
        if markCancelled {
            wasCancelled = true
            state = .loading
            loadingMessage = "已取消解析。"
        }
    }

    @ViewBuilder
    private var fullTextLoadControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoadingFullText {
                HStack(alignment: .top, spacing: 8) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fullTextLoadingStage.title)
                            .font(.caption.weight(.semibold))
                        Text(fullTextLoadMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                loadingStageRows(stages: [.readingText, .buildingIndex], currentStage: fullTextLoadingStage)
                Button(role: .cancel) {
                    cancelFullTextLoading(markCancelled: true)
                } label: {
                    Label("取消文字解析", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    loadFullTextPreview()
                } label: {
                    Label("加载文字", systemImage: "text.viewfinder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Text("已先显示基础几何，文字按需解析。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let fullTextLoadError {
                Text(fullTextLoadError)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(12)
    }

    @MainActor
    private func loadFullTextPreview() {
        guard fileURL.pathExtension.lowercased() == "dwg", !isLoadingFullText else { return }
        isLoadingFullText = true
        fullTextLoadError = nil
        textLoadTask?.cancel()
        textLoadProgressTask?.cancel()

        let token = UUID()
        textLoadToken = token
        let identity = taskIdentity
        let currentFileURL = fileURL
        let currentPreferredCodePage = preferredCodePage
        let currentPreferredBigFont = preferredBigFont
        let currentFontMappings = fontMappings
        fullTextLoadingStage = .readingText
        fullTextLoadMessage = LibreDWGPreviewLoadStage.readingText.detail

        textLoadTask = Task.detached(priority: .userInitiated) {
            let progress: LibreDWGPreviewProgressHandler = { stage in
                await MainActor.run {
                    guard identity == taskIdentity, textLoadToken == token else { return }
                    fullTextLoadingStage = stage
                    fullTextLoadMessage = stage.detail
                }
            }
            let fullState = await LibreDWGPreviewEngine.load(
                fileURL: currentFileURL,
                preferredCodePage: currentPreferredCodePage,
                preferredBigFont: currentPreferredBigFont,
                fontMappings: currentFontMappings,
                progress: progress,
                mode: .full
            )
            await MainActor.run {
                guard identity == taskIdentity, textLoadToken == token else { return }
                isLoadingFullText = false
                textLoadTask = nil
                textLoadProgressTask?.cancel()
                textLoadProgressTask = nil
                switch fullState {
                case .failed(let reason):
                    fullTextLoadError = reason
                default:
                    fullTextLoadError = nil
                    state = fullState
                    postTextAutoDetectionIfAvailable(for: fullState, fileURL: currentFileURL, fontMappings: currentFontMappings)
                }
            }
        }

        textLoadProgressTask = Task.detached(priority: .utility) {
            var elapsed: UInt64 = 0
            for seconds in LibreDWGLoadingMessages.progressSeconds {
                let delay = seconds > elapsed ? seconds - elapsed : 0
                elapsed = seconds
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard identity == taskIdentity, textLoadToken == token else { return }
                    fullTextLoadMessage = fullTextLoadingStage.longRunningMessage(elapsedSeconds: seconds)
                }
            }
        }
    }

    @MainActor
    private func cancelFullTextLoading(markCancelled: Bool = false) {
        let currentFileURL = fileURL
        textLoadTask?.cancel()
        textLoadTask = nil
        textLoadProgressTask?.cancel()
        textLoadProgressTask = nil
        textLoadToken = UUID()
        isLoadingFullText = false
        Task.detached(priority: .utility) {
            await LibreDWGPreviewEngine.cancelLoads(for: currentFileURL)
        }
        if markCancelled {
            fullTextLoadError = "已取消文字解析。"
        }
    }

    @MainActor
    private func postTextAutoDetectionIfAvailable(
        for loadedState: PreviewState,
        fileURL: URL,
        fontMappings: [LibreDWGFontMapping]
    ) {
        guard case .dxf(let preview) = loadedState,
              fileURL.pathExtension.lowercased() == "dwg",
              !preview.model.texts.isEmpty else { return }
        let model = preview.model
        Task.detached(priority: .utility) {
            let result = LibreDWGTextAutoDetector.detect(model: model, fontMappings: fontMappings)
            await MainActor.run {
                onTextAutoDetectionChange(
                    LibreDWGTextAutoDetectionSnapshot(
                        codePage: result.codePage,
                        bigFont: result.bigFont,
                        styleName: result.styleName,
                        fontFile: result.fontFile,
                        bigFontFile: result.bigFontFile,
                        autoDetectScore: result.score,
                        styleSummary: result.styleSummary,
                        matchedFontSummary: result.matchedFontSummary,
                        unresolvedFontSummary: result.unresolvedFontSummary,
                        fontResolutionSummary: result.fontResolutionSummary,
                        rawTextBytesHexSample: result.rawTextBytesHexSample,
                        detectionSummary: result.detectionSummary,
                        summary: result.summary
                    )
                )
            }
        }
    }
}

enum DXFPreviewParser {
    private struct DecodedTextPayload {
        let text: String
        let resolvedCodePage: Int32?
        let usedPreferredCodePage: Bool
    }

    static func parse(
        fileURL: URL,
        preferredCodePage: Int32? = nil,
        preferredBigFont: Int32? = nil,
        fontMappings _: [LibreDWGFontMapping] = []
    ) throws -> DXFPreviewModel {
        let raw = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let decodedPayload = decodeText(raw, preferredCodePage: preferredCodePage)
        let text = decodedPayload.text
        let bigFontProfile = preferredBigFont
            .flatMap(CADTextBigFontProfile.init(rawValue:)) ?? .auto
        let pairs = dxfPairs(from: text)

        var segments: [DXFPreviewModel.Segment] = []
        var polylines: [DXFPreviewModel.Polyline] = []
        var circles: [DXFPreviewModel.Circle] = []
        var texts: [DXFPreviewModel.TextEntity] = []
        var arcCount = 0
        var polylineEntityCount = 0

        var type: String?
        var fields: [Int: [String]] = [:]
        var isCollectingPolyline = false
        var polylineClosed = false
        var polylineVertices: [CGPoint] = []
        var activePolylineLayer = "0"

        func flushEntity() {
            guard let type else { return }
            let layer = fields.firstString(8).flatMap { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            } ?? "0"
            switch type {
            case "LINE":
                if let x1 = fields.firstDouble(10),
                   let y1 = fields.firstDouble(20),
                   let x2 = fields.firstDouble(11),
                   let y2 = fields.firstDouble(21) {
                    segments.append(.init(
                        from: CGPoint(x: x1, y: y1),
                        to: CGPoint(x: x2, y: y2),
                        style: .default,
                        layer: layer
                    ))
                }
            case "LWPOLYLINE":
                let xs = fields.allDoubles(10)
                let ys = fields.allDoubles(20)
                let count = min(xs.count, ys.count)
                if count > 1 {
                    var points: [CGPoint] = (0..<count).map { CGPoint(x: xs[$0], y: ys[$0]) }
                    let flag = fields.firstInt(70) ?? 0
                    if (flag & 0x01) == 0x01, let first = points.first {
                        points.append(first)
                    }
                    polylines.append(.init(points: points, style: .default, layer: layer))
                    polylineEntityCount += 1
                }
            case "POLYLINE":
                isCollectingPolyline = true
                polylineClosed = ((fields.firstInt(70) ?? 0) & 0x01) == 0x01
                polylineVertices = []
                activePolylineLayer = layer
            case "VERTEX":
                guard isCollectingPolyline,
                      let x = fields.firstDouble(10),
                      let y = fields.firstDouble(20) else { break }
                polylineVertices.append(CGPoint(x: x, y: y))
            case "SEQEND":
                guard isCollectingPolyline else { break }
                var points = polylineVertices
                if polylineClosed, let first = points.first, points.count > 1 {
                    points.append(first)
                }
                if points.count > 1 {
                    polylines.append(.init(points: points, style: .default, layer: activePolylineLayer))
                    polylineEntityCount += 1
                }
                isCollectingPolyline = false
                polylineVertices = []
                activePolylineLayer = "0"
            case "CIRCLE":
                if let x = fields.firstDouble(10),
                   let y = fields.firstDouble(20),
                   let radius = fields.firstDouble(40),
                   radius > 0 {
                    circles.append(.init(
                        center: CGPoint(x: x, y: y),
                        radius: radius,
                        style: .default,
                        layer: layer
                    ))
                }
            case "ARC":
                if let centerX = fields.firstDouble(10),
                   let centerY = fields.firstDouble(20),
                   let radius = fields.firstDouble(40),
                   let start = fields.firstDouble(50),
                   let end = fields.firstDouble(51),
                   radius > 0 {
                    let arcPoints = sampleArcPoints(
                        center: CGPoint(x: centerX, y: centerY),
                        radius: radius,
                        startDegrees: start,
                        endDegrees: end
                    )
                    if arcPoints.count > 1 {
                        polylines.append(.init(points: arcPoints, style: .default, layer: layer))
                        arcCount += 1
                    }
                }
            case "SOLID", "TRACE":
                if let x1 = fields.firstDouble(10),
                   let y1 = fields.firstDouble(20),
                   let x2 = fields.firstDouble(11),
                   let y2 = fields.firstDouble(21),
                   let x3 = fields.firstDouble(12),
                   let y3 = fields.firstDouble(22) {
                    var points = [
                        CGPoint(x: x1, y: y1),
                        CGPoint(x: x2, y: y2),
                        CGPoint(x: x3, y: y3),
                    ]
                    if let x4 = fields.firstDouble(13),
                       let y4 = fields.firstDouble(23) {
                        points.append(CGPoint(x: x4, y: y4))
                    }
                    if let first = points.first {
                        points.append(first)
                    }
                    if points.count > 2 {
                        polylines.append(.init(points: points, style: .default, layer: layer))
                    }
                }
            case "DIMENSION":
                if let x1 = fields.firstDouble(13),
                   let y1 = fields.firstDouble(23),
                   let x2 = fields.firstDouble(14),
                   let y2 = fields.firstDouble(24) {
                    polylines.append(.init(
                        points: [CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2)],
                        style: DXFPreviewModel.StrokeStyle(rgb: 0x008EA8, width: 0.9),
                        layer: layer,
                        renderKind: .dimension
                    ))
                }
                if let x = fields.firstDouble(11),
                   let y = fields.firstDouble(21),
                   let rawValue = fields.firstString(1) {
                    let normalized = normalizeDXFText(rawValue, bigFontProfile: bigFontProfile)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            rawValue: rawValue,
                            rawTextBytesHex: nil,
                            chosenCodepage: decodedPayload.resolvedCodePage.map(Int.init),
                            height: fields.firstDouble(40) ?? 2,
                            rotation: ((fields.firstDouble(53) ?? 0) * .pi / 180),
                            style: DXFPreviewModel.StrokeStyle(rgb: 0x008EA8, width: 0.9),
                            layer: layer,
                            renderKind: .dimension
                        ))
                    }
                }
            case "LEADER", "MULTILEADER":
                let xs = fields.allDoubles(10)
                let ys = fields.allDoubles(20)
                let count = min(xs.count, ys.count)
                if count > 1 {
                    let points = (0..<count).map { CGPoint(x: xs[$0], y: ys[$0]) }
                    polylines.append(.init(points: points, style: .default, layer: layer))
                }
                if let x = fields.firstDouble(11),
                   let y = fields.firstDouble(21),
                   let rawValue = fields.firstString(304) ?? fields.firstString(1) {
                    let normalized = normalizeDXFText(rawValue, bigFontProfile: bigFontProfile)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            rawValue: rawValue,
                            rawTextBytesHex: nil,
                            chosenCodepage: decodedPayload.resolvedCodePage.map(Int.init),
                            height: fields.firstDouble(40) ?? 2,
                            rotation: ((fields.firstDouble(50) ?? 0) * .pi / 180),
                            style: DXFPreviewModel.StrokeStyle(rgb: 0x7A3DB8, width: 0.8),
                            layer: layer,
                            renderKind: .leader
                        ))
                    }
                }
            case "HATCH":
                let xs = fields.allDoubles(10)
                let ys = fields.allDoubles(20)
                let count = min(xs.count, ys.count)
                if count > 1 {
                    var points = (0..<count).map { CGPoint(x: xs[$0], y: ys[$0]) }
                    if let first = points.first, let last = points.last,
                       (abs(first.x - last.x) > 0.0001 || abs(first.y - last.y) > 0.0001) {
                        points.append(first)
                    }
                    polylines.append(.init(
                        points: points,
                        style: DXFPreviewModel.StrokeStyle(rgb: 0xCC7A00, width: 0.7),
                        layer: layer,
                        renderKind: .hatch
                    ))
                    if let labelPoint = centroid(of: points),
                       let rawPattern = fields.firstString(2) {
                        let pattern = normalizeDXFText(rawPattern, bigFontProfile: bigFontProfile)
                        let label = hatchLabel(for: pattern, solidFlag: fields.firstInt(70))
                        if !label.isEmpty {
                            texts.append(.init(
                                point: labelPoint,
                                value: label,
                                rawValue: rawPattern,
                                rawTextBytesHex: nil,
                                chosenCodepage: decodedPayload.resolvedCodePage.map(Int.init),
                                height: max(fields.firstDouble(41) ?? 2, 1.4),
                                rotation: 0,
                                style: DXFPreviewModel.StrokeStyle(rgb: 0xCC7A00, width: 0.7),
                                layer: layer,
                                renderKind: .hatch
                            ))
                        }
                    }
                }
            case "IMAGE", "WIPEOUT":
                if let x = fields.firstDouble(10),
                   let y = fields.firstDouble(20),
                   let ux = fields.firstDouble(11),
                   let uy = fields.firstDouble(21),
                   let vx = fields.firstDouble(12),
                   let vy = fields.firstDouble(22),
                   let width = fields.firstDouble(13),
                   let height = fields.firstDouble(23) {
                    let a = CGPoint(x: x, y: y)
                    let b = CGPoint(x: x + ux * width, y: y + uy * width)
                    let d = CGPoint(x: x + vx * height, y: y + vy * height)
                    let c = CGPoint(x: b.x + (d.x - a.x), y: b.y + (d.y - a.y))
                    let points = [a, b, c, d, a]
                    polylines.append(.init(points: points, style: .default, layer: layer))
                }
            case "TEXT", "ATTRIB":
                if let x = fields.firstDouble(10),
                   let y = fields.firstDouble(20),
                   let rawValue = fields.firstString(1) {
                    let styleName = fields.firstString(7)
                    let normalized = normalizeDXFText(rawValue, bigFontProfile: bigFontProfile)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            rawValue: rawValue,
                            rawTextBytesHex: nil,
                            chosenCodepage: decodedPayload.resolvedCodePage.map(Int.init),
                            height: fields.firstDouble(40) ?? 2,
                            rotation: ((fields.firstDouble(50) ?? 0) * .pi / 180),
                            style: .default,
                            layer: layer,
                            styleName: styleName,
                            renderKind: type == "ATTRIB" ? .attribute : .regular,
                            kind: type == "ATTRIB" ? .text : .text
                        ))
                    }
                }
            case "MTEXT":
                if let x = fields.firstDouble(10),
                   let y = fields.firstDouble(20) {
                    let styleName = fields.firstString(7)
                    let chunks = fields.allStrings(3)
                    let tail = fields.firstString(1).map { [$0] } ?? []
                    let merged = (chunks + tail).joined()
                    let normalized = normalizeDXFText(merged, bigFontProfile: bigFontProfile)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            rawValue: merged,
                            rawTextBytesHex: nil,
                            chosenCodepage: decodedPayload.resolvedCodePage.map(Int.init),
                            height: fields.firstDouble(40) ?? 2,
                            rotation: ((fields.firstDouble(50) ?? 0) * .pi / 180),
                            style: .default,
                            layer: layer,
                            styleName: styleName,
                            kind: .mtext
                        ))
                    }
                }
            default:
                break
            }
        }

        for pair in pairs {
            if pair.code == 0 {
                flushEntity()
                type = pair.value.uppercased()
                fields = [:]
            } else if type != nil {
                fields[pair.code, default: []].append(pair.value)
            }
        }
        flushEntity()

        let bounds = computeBounds(
            segments: segments,
            polylines: polylines,
            circles: circles,
            texts: texts
        )
        guard let bounds else {
            throw NSError(domain: "LibreDWGBridge", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: "未识别到可绘制的 DXF 几何元素（当前支持二维 LINE / ARC / LWPOLYLINE / POLYLINE / CIRCLE / SOLID / DIMENSION / TEXT / MTEXT / ATTRIB）。",
            ])
        }

        return DXFPreviewModel(
            segments: segments,
            polylines: polylines,
            circles: circles,
            texts: texts,
            arcCount: arcCount,
            polylineEntityCount: polylineEntityCount,
            textDecodingHint: decodingHint(
                preferredCodePage: preferredCodePage,
                resolvedCodePage: decodedPayload.resolvedCodePage,
                preferredBigFont: preferredBigFont,
                usedPreferredCodePage: decodedPayload.usedPreferredCodePage
            ),
            textIssueHint: textIssueHint(from: texts),
            bounds: bounds
        )
    }

    private static func decodeText(_ data: Data, preferredCodePage: Int32?) -> DecodedTextPayload {
        let candidates: [(Int32?, String.Encoding)] = {
            var values: [(Int32?, String.Encoding)] = []
            if let preferredCodePage, let encoding = stringEncoding(for: preferredCodePage) {
                values.append((preferredCodePage, encoding))
            }
            values.append(contentsOf: [
                (65001, .utf8),
                (936, stringEncoding(for: 936)),
                (54936, stringEncoding(for: 54936)),
                (950, stringEncoding(for: 950)),
                (932, .shiftJIS),
                (949, stringEncoding(for: 949)),
                (20127, .ascii),
            ].compactMap { codePage, encoding in
                encoding.map { (codePage, $0) }
            })
            return values
        }()

        var seen: Set<UInt> = []
        var best: (text: String, score: Int, codePage: Int32?)?
        for (codePage, encoding) in candidates where seen.insert(encoding.rawValue).inserted {
            guard let decoded = String(data: data, encoding: encoding) else { continue }
            let score = decodedQualityScore(decoded)
            if let preferredCodePage, codePage == preferredCodePage {
                return DecodedTextPayload(
                    text: decoded,
                    resolvedCodePage: preferredCodePage,
                    usedPreferredCodePage: true
                )
            }
            if best == nil || score > best!.score {
                best = (decoded, score, codePage)
            }
        }
        if let best {
            return DecodedTextPayload(
                text: best.text,
                resolvedCodePage: best.codePage,
                usedPreferredCodePage: false
            )
        }
        return DecodedTextPayload(
            text: String(decoding: data, as: UTF8.self),
            resolvedCodePage: 65001,
            usedPreferredCodePage: false
        )
    }

    private static func stringEncoding(for codePage: Int32) -> String.Encoding? {
        let cfEncoding = CFStringConvertWindowsCodepageToEncoding(UInt32(codePage))
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        guard nsEncoding != UInt(kCFStringEncodingInvalidId) else { return nil }
        return String.Encoding(rawValue: nsEncoding)
    }

    private static func decodedQualityScore(_ text: String) -> Int {
        var score = 0
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x3400...0x4DBF).contains(value) ||
                (0x4E00...0x9FFF).contains(value) ||
                (0xF900...0xFAFF).contains(value) ||
                (0x3000...0x303F).contains(value) ||
                (0xFF00...0xFFEF).contains(value) {
                score += 12
            } else if value == 0xFFFD {
                score -= 40
            } else if (0x00A0...0x00FF).contains(value) {
                score -= 6
            } else if value == 0x3F {
                score -= 4
            } else if value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t" {
                score -= 12
            } else if value < 0x7F {
                score += 1
            }
        }
        score += cadVocabularyScore(text)
        return score
    }

    private static func textIssueHint(from texts: [DXFPreviewModel.TextEntity]) -> DXFTextIssueHint? {
        guard !texts.isEmpty else { return nil }
        var suspiciousCount = 0
        var mojibakeCount = 0
        var styleDiagnostics: Set<String> = []

        for text in texts {
            if CADTextNormalizer.looksSuspicious(text.value) {
                suspiciousCount += 1
            }
            if CADTextNormalizer.looksLikeMojibake(text.value) {
                mojibakeCount += 1
            }
            if let styleName = text.styleName, !styleName.isEmpty {
                styleDiagnostics.insert("样式 \(styleName)")
            }
            if let fontFile = text.fontFile, !fontFile.isEmpty {
                styleDiagnostics.insert("字体 \(fontFile)")
            }
            if let bigFontFile = text.bigFontFile, !bigFontFile.isEmpty {
                styleDiagnostics.insert("大字体 \(bigFontFile)")
            }
        }

        guard suspiciousCount > 0 else { return nil }
        return DXFTextIssueHint(
            textCount: texts.count,
            suspiciousTextCount: suspiciousCount,
            mojibakeTextCount: mojibakeCount,
            styleDiagnostics: Array(styleDiagnostics).sorted()
        )
    }

    private static func cadVocabularyScore(_ text: String) -> Int {
        let commonTerms = [
            "平面", "立面", "剖面", "详图", "节点", "标高", "轴线", "尺寸",
            "配电", "回路", "照明", "插座", "桥架", "线管", "接地", "负荷", "施工",
            "建筑", "结构", "电气", "给排水", "消防", "弱电", "系统图", "配线",
            "平面圖", "立面圖", "剖面圖", "詳圖", "節點", "標高", "軸線", "尺寸",
            "配電", "迴路", "照明", "插座", "橋架", "線管", "接地", "負荷", "施工",
            "建築", "結構", "電氣", "給排水", "消防", "弱電", "系統圖", "配線",
        ]
        let suspiciousGlyphs = ["Ê", "Ð", "Ä", "Ã", "Â", "Ó", "Æ", "Ë", "·", "µ", "Ç"]
        var score = 0
        for term in commonTerms where text.contains(term) {
            score += 18
        }
        for glyph in suspiciousGlyphs where text.contains(glyph) {
            score -= 18
        }
        return score
    }

    private static func decodingHint(
        preferredCodePage: Int32?,
        resolvedCodePage: Int32?,
        preferredBigFont: Int32?,
        usedPreferredCodePage: Bool
    ) -> String? {
        let bodyText: String
        if usedPreferredCodePage, let preferredCodePage {
            bodyText = "正文 \(codePageName(for: preferredCodePage))"
        } else if let resolvedCodePage {
            bodyText = "正文自动命中 \(codePageName(for: resolvedCodePage))"
        } else {
            bodyText = "正文自动编码"
        }
        let shxText = preferredBigFont
            .flatMap(CADTextBigFontProfile.init(rawValue:))
            .map(bigFontName(for:)) ?? "自动 SHX"
        return "\(bodyText) / \(shxText)"
    }

    private static func codePageName(for codePage: Int32) -> String {
        switch codePage {
        case 936:
            return "GBK 936"
        case 950:
            return "Big5 950"
        case 54936:
            return "GB18030 54936"
        case 932:
            return "Shift-JIS 932"
        case 949:
            return "Korean 949"
        case 65001:
            return "UTF-8"
        case 20127:
            return "ASCII"
        default:
            return "代码页 \(Int(codePage))"
        }
    }

    private static func bigFontName(for profile: CADTextBigFontProfile) -> String {
        switch profile {
        case .auto:
            return "自动 SHX"
        case .gbcbig:
            return "GBCBIG"
        case .hztxt:
            return "HZTXT"
        case .hzfs:
            return "HZFS"
        case .big5:
            return "Big5 字体"
        case .disabled:
            return "关闭 SHX 映射"
        }
    }

    private static func dxfPairs(from text: String) -> [(code: Int, value: String)] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [(code: Int, value: String)] = []
        var index = 0
        while index + 1 < lines.count {
            let codeText = lines[index].trimmingCharacters(in: .whitespaces)
            let valueText = lines[index + 1].trimmingCharacters(in: .whitespaces)
            if let code = Int(codeText) {
                result.append((code: code, value: valueText))
            }
            index += 2
        }
        return result
    }

    private static func computeBounds(
        segments: [DXFPreviewModel.Segment],
        polylines: [DXFPreviewModel.Polyline],
        circles: [DXFPreviewModel.Circle],
        texts: [DXFPreviewModel.TextEntity]
    ) -> CGRect? {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        func include(_ point: CGPoint) {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        for segment in segments {
            include(segment.from)
            include(segment.to)
        }
        for polyline in polylines {
            for point in polyline.points {
                include(point)
            }
        }
        for circle in circles {
            include(CGPoint(x: circle.center.x - circle.radius, y: circle.center.y - circle.radius))
            include(CGPoint(x: circle.center.x + circle.radius, y: circle.center.y + circle.radius))
        }
        for text in texts {
            include(text.point)
        }

        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else {
            return nil
        }
        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private static func sampleArcPoints(
        center: CGPoint,
        radius: CGFloat,
        startDegrees: CGFloat,
        endDegrees: CGFloat
    ) -> [CGPoint] {
        let twoPi = CGFloat.pi * 2
        let start = startDegrees * .pi / 180
        var end = endDegrees * .pi / 180
        while end < start {
            end += twoPi
        }
        let span = max(end - start, 0)
        let segments = max(Int(ceil(span / (.pi / 18))), 8)
        guard segments > 0 else { return [] }

        return (0...segments).map { index in
            let t = CGFloat(index) / CGFloat(segments)
            let angle = start + span * t
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private static func centroid(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let uniquePoints: [CGPoint]
        if points.count > 1, points.first == points.last {
            uniquePoints = Array(points.dropLast())
        } else {
            uniquePoints = points
        }
        guard !uniquePoints.isEmpty else { return nil }

        let sum = uniquePoints.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPoint(
            x: sum.x / CGFloat(uniquePoints.count),
            y: sum.y / CGFloat(uniquePoints.count)
        )
    }

    private static func hatchLabel(for pattern: String, solidFlag: Int?) -> String {
        let normalized = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return ""
        }
        if normalized.caseInsensitiveCompare("SOLID") == .orderedSame || solidFlag == 1 {
            return "实填充"
        }
        return normalized
    }

    private static func normalizeDXFText(_ raw: String, bigFontProfile: CADTextBigFontProfile) -> String {
        CADTextNormalizer.normalize(raw, bigFontProfile: bigFontProfile)
    }
}

private extension Dictionary where Key == Int, Value == [String] {
    func firstDouble(_ code: Int) -> CGFloat? {
        self[code]?.first.flatMap { Double($0) }.map { CGFloat($0) }
    }

    func allDoubles(_ code: Int) -> [CGFloat] {
        (self[code] ?? []).compactMap { Double($0) }.map { CGFloat($0) }
    }

    func firstInt(_ code: Int) -> Int? {
        self[code]?.first.flatMap(Int.init)
    }

    func firstString(_ code: Int) -> String? {
        self[code]?.first
    }

    func allStrings(_ code: Int) -> [String] {
        self[code] ?? []
    }
}
