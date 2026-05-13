import SwiftUI

struct ProjectCADPreviewRequest: Identifiable {
    let id = UUID()
    let projectId: UUID
    let drawingID: UUID
    let fileURL: URL
    let displayName: String
    let fileType: String
    let textEncoding: CADDrawingTextEncoding
    let textBigFont: CADDrawingTextBigFont
    let overlaySnapshotData: String
    let onOverlaySnapshotChange: (UUID, String) -> Void
    let onTextEncodingChange: (UUID, CADDrawingTextEncoding) -> Void
    let onTextBigFontChange: (UUID, CADDrawingTextBigFont) -> Void

    var preferredTextCodePage: Int32? {
        textEncoding.codePageOverride
    }

    var preferredTextBigFontCode: Int32? {
        textBigFont.bridgeCode
    }
}

private struct CADExternalPreviewFallbackView: View {
    let fileURL: URL
    let displayName: String
    let fileType: String

    private var fileSizeText: String {
        do {
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            let bytes = values.fileSize ?? values.totalFileAllocatedSize ?? 0
            return QuickNoteAttachmentStorage.formattedFileSize(bytes)
        } catch {
            return String(localized: "未知大小")
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "compass.drawing")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(Color.appDoc)

            VStack(spacing: 6) {
                Text("需要外部 CAD 查看器")
                    .font(.title3.weight(.semibold))
                Text("iOS 系统预览无法可靠渲染 \(fileType.uppercased()) 原始图纸，直接打开会显示为数据。请用已安装的 CAD 应用打开，或导出为 PDF 后在本页预览和批注。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 6) {
                Text(displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text("\(fileType.uppercased()) · \(fileSizeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ShareLink(item: fileURL) {
                Label("用其他 CAD App 打开", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appDoc)
            .controlSize(.large)

            Text("建议在电脑或 CAD App 中转成 PDF，再导入项目图纸；PDF 可在应用内直接查看、批注、测量和导出交付包。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct CADLibreDWGUnavailableView: View {
    let fileURL: URL
    let displayName: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Color.appWarning)

            VStack(spacing: 6) {
                Text("LibreDWG 引擎未集成")
                    .font(.title3.weight(.semibold))
                Text("已选择 LibreDWG 预览，但当前构建未包含 LibreDWGBridge。请先把桥接库接入工程，再重编译。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(displayName)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            ShareLink(item: fileURL) {
                Label("先用其他 CAD App 打开", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appDoc)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct CADLibreDWGUnboundView: View {
    let fileURL: URL
    let displayName: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Color.appWarning)

            VStack(spacing: 6) {
                Text("LibreDWG 渲染器未注册")
                    .font(.title3.weight(.semibold))
                Text("检测到 LibreDWG 环境，但应用内还没有绑定渲染入口。请在启动时调用 CADRendererProvider.registerLibreDWGRenderer。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(displayName)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            ShareLink(item: fileURL) {
                Label("先用其他 CAD App 打开", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appDoc)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct CADPoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

private enum CADOverlayCoordinateSpace: String, Codable, Equatable {
    case canvas
    case drawing
}

private struct CADNativeCanvasTransform: Equatable {
    var bounds: CGRect
    var size: CGSize
    var zoomScale: CGFloat
    var panOffset: CGSize

    private var contentInset: CGFloat {
        min(max(min(size.width, size.height) * 0.018, 6), 14)
    }

    private var baseScale: CGFloat {
        let availableWidth = max(size.width - contentInset * 2, 1)
        let availableHeight = max(size.height - contentInset * 2, 1)
        let sx = availableWidth / max(bounds.width, 1)
        let sy = availableHeight / max(bounds.height, 1)
        return min(sx, sy)
    }

    private var horizontalPad: CGFloat {
        (size.width - bounds.width * baseScale) / 2
    }

    private var verticalPad: CGFloat {
        (size.height - bounds.height * baseScale) / 2
    }

    func canvasPoint(fromDrawing source: CGPoint) -> CGPoint {
        let x = (source.x - bounds.minX) * baseScale
        let y = (source.y - bounds.minY) * baseScale
        let base = CGPoint(
            x: horizontalPad + x,
            y: size.height - (verticalPad + y)
        )
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(
            x: center.x + (base.x - center.x) * zoomScale + panOffset.width,
            y: center.y + (base.y - center.y) * zoomScale + panOffset.height
        )
    }

    func drawingPoint(fromCanvas rendered: CGPoint) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let unscaledX = ((rendered.x - panOffset.width) - center.x) / max(zoomScale, 0.0001) + center.x
        let unscaledY = ((rendered.y - panOffset.height) - center.y) / max(zoomScale, 0.0001) + center.y
        let sourceX = bounds.minX + (unscaledX - horizontalPad) / max(baseScale, 0.0001)
        let sourceY = bounds.minY + ((size.height - unscaledY) - verticalPad) / max(baseScale, 0.0001)
        return CGPoint(x: sourceX, y: sourceY)
    }
}

private extension Notification.Name {
    static let libreDWGCanvasTransformDidChange = Notification.Name("LibreDWGBridgeCanvasTransformDidChange")
}

private struct CADStroke: Identifiable, Codable, Equatable {
    enum StrokeKind: String, Codable {
        case annotation
        case redline
    }

    var id = UUID()
    var kind: StrokeKind
    var points: [CADPoint]
    var lineWidth: Double
}

private struct CADLengthMeasurement: Identifiable, Codable, Equatable {
    var id = UUID()
    var points: [CADPoint]
    var name: String
}

private struct CADAreaMeasurement: Identifiable, Codable, Equatable {
    var id = UUID()
    var points: [CADPoint]
    var name: String
}

private struct CADTextNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var point: CADPoint
    var createdAt: String
}

private struct CADCountMarker: Identifiable, Codable, Equatable {
    var id = UUID()
    var point: CADPoint
    var category: String
    var createdAt: String
}

private struct CADQuantityItem: Identifiable, Codable, Equatable {
    enum SourceLinkKind: String, Codable, Equatable {
        case manual
        case lengthMeasurement
        case areaMeasurement
        case countCategory
    }

    var id = UUID()
    var name: String
    var unit: String
    var quantity: String
    var unitPrice: String
    var wasteRate: String
    var source: String
    var sourceLinkKind: SourceLinkKind = .manual
    var sourceLinkID: UUID?
    var sourceLinkCategory: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case unit
        case quantity
        case unitPrice
        case wasteRate
        case source
        case sourceLinkKind
        case sourceLinkID
        case sourceLinkCategory
    }

    init(
        id: UUID = UUID(),
        name: String,
        unit: String,
        quantity: String,
        unitPrice: String,
        wasteRate: String,
        source: String,
        sourceLinkKind: SourceLinkKind = .manual,
        sourceLinkID: UUID? = nil,
        sourceLinkCategory: String? = nil
    ) {
        self.id = id
        self.name = name
        self.unit = unit
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.wasteRate = wasteRate
        self.source = source
        self.sourceLinkKind = sourceLinkKind
        self.sourceLinkID = sourceLinkID
        self.sourceLinkCategory = sourceLinkCategory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        quantity = try container.decodeIfPresent(String.self, forKey: .quantity) ?? ""
        unitPrice = try container.decodeIfPresent(String.self, forKey: .unitPrice) ?? "0"
        wasteRate = try container.decodeIfPresent(String.self, forKey: .wasteRate) ?? "0"
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? String(localized: "手动")
        sourceLinkKind = try container.decodeIfPresent(SourceLinkKind.self, forKey: .sourceLinkKind) ?? .manual
        sourceLinkID = try container.decodeIfPresent(UUID.self, forKey: .sourceLinkID)
        sourceLinkCategory = try container.decodeIfPresent(String.self, forKey: .sourceLinkCategory)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(unit, forKey: .unit)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(unitPrice, forKey: .unitPrice)
        try container.encode(wasteRate, forKey: .wasteRate)
        try container.encode(source, forKey: .source)
        try container.encode(sourceLinkKind, forKey: .sourceLinkKind)
        try container.encodeIfPresent(sourceLinkID, forKey: .sourceLinkID)
        try container.encodeIfPresent(sourceLinkCategory, forKey: .sourceLinkCategory)
    }
}

private struct CADOverlaySnapshot: Codable, Equatable {
    var metersPerPoint: Double = 0.02
    var coordinateSpace: CADOverlayCoordinateSpace = .drawing
    var strokes: [CADStroke] = []
    var lengthMeasurements: [CADLengthMeasurement] = []
    var areaMeasurements: [CADAreaMeasurement] = []
    var notes: [CADTextNote] = []
    var countMarkers: [CADCountMarker] = []
    var quantityItems: [CADQuantityItem] = []

    enum CodingKeys: String, CodingKey {
        case metersPerPoint
        case coordinateSpace
        case strokes
        case lengthMeasurements
        case areaMeasurements
        case notes
        case countMarkers
        case quantityItems
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metersPerPoint = try container.decodeIfPresent(Double.self, forKey: .metersPerPoint) ?? 0.02
        coordinateSpace = try container.decodeIfPresent(CADOverlayCoordinateSpace.self, forKey: .coordinateSpace) ?? .canvas
        strokes = try container.decodeIfPresent([CADStroke].self, forKey: .strokes) ?? []
        lengthMeasurements = try container.decodeIfPresent([CADLengthMeasurement].self, forKey: .lengthMeasurements) ?? []
        areaMeasurements = try container.decodeIfPresent([CADAreaMeasurement].self, forKey: .areaMeasurements) ?? []
        notes = try container.decodeIfPresent([CADTextNote].self, forKey: .notes) ?? []
        countMarkers = try container.decodeIfPresent([CADCountMarker].self, forKey: .countMarkers) ?? []
        quantityItems = try container.decodeIfPresent([CADQuantityItem].self, forKey: .quantityItems) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metersPerPoint, forKey: .metersPerPoint)
        try container.encode(coordinateSpace, forKey: .coordinateSpace)
        try container.encode(strokes, forKey: .strokes)
        try container.encode(lengthMeasurements, forKey: .lengthMeasurements)
        try container.encode(areaMeasurements, forKey: .areaMeasurements)
        try container.encode(notes, forKey: .notes)
        try container.encode(countMarkers, forKey: .countMarkers)
        try container.encode(quantityItems, forKey: .quantityItems)
    }

    var hasOverlayContent: Bool {
        !strokes.isEmpty ||
        !lengthMeasurements.isEmpty ||
        !areaMeasurements.isEmpty ||
        !notes.isEmpty ||
        !countMarkers.isEmpty ||
        !quantityItems.isEmpty
    }
}

private enum CADOverlayTool: String, CaseIterable {
    case browse
    case annotation
    case redline
    case length
    case continuousLength
    case area
    case note
    case count

    var title: String {
        switch self {
        case .browse: return String(localized: "浏览")
        case .annotation: return String(localized: "批注")
        case .redline: return String(localized: "红线")
        case .length: return String(localized: "线长")
        case .continuousLength: return String(localized: "连续长度")
        case .area: return String(localized: "面积")
        case .note: return String(localized: "文字批注")
        case .count: return String(localized: "数数")
        }
    }

    var icon: String {
        switch self {
        case .browse: return "hand.tap"
        case .annotation: return "highlighter"
        case .redline: return "scribble"
        case .length: return "ruler"
        case .continuousLength: return "point.topleft.down.curvedto.point.bottomright.up"
        case .area: return "square.dashed"
        case .note: return "text.bubble"
        case .count: return "number.circle"
        }
    }
}

private enum CADQuantityHighlightTarget: Equatable {
    case length(UUID)
    case area(UUID)
    case countCategory(String)
}

private enum LegacyCADOverlayStorage {
    static func key(for fileURL: URL) -> String {
        let encoded = Data(fileURL.path.utf8).base64EncodedString()
        return "cad.overlay.snapshot.\(encoded)"
    }

    static func load(for fileURL: URL) -> CADOverlaySnapshot? {
        let key = key(for: fileURL)
        guard let raw = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(CADOverlaySnapshot.self, from: raw)
        } catch {
            StorageIssueLog.record("CAD 旧快照解析失败：\(fileURL.lastPathComponent)，\(error.localizedDescription)")
            return nil
        }
    }
}

struct ProjectCADPreviewView: View {
    let request: ProjectCADPreviewRequest
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var activeRequest: ProjectCADPreviewRequest
    @State private var tool: CADOverlayTool = .browse
    @State private var snapshot = CADOverlaySnapshot()
    @State private var activeStrokePoints: [CGPoint] = []
    @State private var pendingLengthPoints: [CGPoint] = []
    @State private var pendingAreaPoints: [CGPoint] = []
    @State private var activeDragLengthPoints: [CGPoint] = []
    @State private var showQuantitySheet = false
    @State private var showResetConfirm = false
    @State private var showScaleSheet = false
    @State private var showTextEncodingDialog = false
    @State private var scaleDraft = ""
    @State private var pendingNotePoint: CGPoint?
    @State private var noteDraft = ""
    @State private var showNoteSheet = false
    @State private var selectedCountCategory = String(localized: "点位")
    @State private var lastPersistedSnapshotData = ""
    @State private var isImmersivePreview = false
    @State private var selectedTextEncoding: CADDrawingTextEncoding
    @State private var selectedTextBigFont: CADDrawingTextBigFont
    @State private var isAutoDetectingText = false
    @State private var quantityHighlightTarget: CADQuantityHighlightTarget?
    @State private var nativeCanvasTransform: CADNativeCanvasTransform?
    @State private var alertMessage = ""
    @State private var showAlert = false
    private let overlaySnapTolerance: CGFloat = 14

    init(request: ProjectCADPreviewRequest) {
        self.request = request
        _activeRequest = State(initialValue: request)
        _selectedTextEncoding = State(initialValue: request.textEncoding)
        _selectedTextBigFont = State(initialValue: request.textBigFont)
    }

    private var preferredEngine: CADPreviewEngine {
        CADPreviewEngineStore.selected
    }

    private var resolvedEngine: CADPreviewEngine {
        CADPreviewCapability.resolvedEngine(preferredEngine)
    }

    private var isCADFile: Bool {
        CADPreviewCapability.isCADFile(extension: activeRequest.fileType)
    }

    private var shouldUseExternalCADPreviewFallback: Bool {
        isCADFile && (resolvedEngine == .systemQuickLook || shouldShowLibreDWGUnbound)
    }

    private var shouldShowLibreDWGUnavailable: Bool {
        isCADFile && preferredEngine == .libreDWG && !CADPreviewCapability.isLibreDWGRendererAvailable()
    }

    private var shouldShowLibreDWGUnbound: Bool {
        isCADFile &&
        resolvedEngine == .libreDWG &&
        !shouldShowLibreDWGUnavailable &&
        !CADRendererProvider.isLibreDWGRendererBound
    }

    private var shouldUseLibreDWGRenderer: Bool {
        isCADFile &&
        resolvedEngine == .libreDWG &&
        CADRendererProvider.isLibreDWGRendererBound
    }

    private var allowsOverlayEditing: Bool {
        !shouldUseExternalCADPreviewFallback &&
        !shouldShowLibreDWGUnavailable &&
        !shouldShowLibreDWGUnbound
    }

    private var engineStatusText: String {
        if !isCADFile {
            return String(localized: "文档预览")
        }
        if preferredEngine == .libreDWG && !CADPreviewCapability.isLibreDWGRendererAvailable() {
            return String(localized: "LibreDWG 未接入")
        }
        if shouldShowLibreDWGUnbound {
            return String(localized: "LibreDWG 未绑定（已回退）")
        }
        switch resolvedEngine {
        case .libreDWG:
            return isCADFile ? String(localized: "CAD 代理预览") : String(localized: "文档预览")
        case .systemQuickLook:
            return String(localized: "系统预览")
        }
    }

    private var engineStatusIcon: String {
        if shouldShowLibreDWGUnavailable || shouldShowLibreDWGUnbound {
            return "exclamationmark.triangle.fill"
        }
        return resolvedEngine == .libreDWG ? "checkmark.seal.fill" : "viewfinder"
    }

    private var engineStatusTint: Color {
        if shouldShowLibreDWGUnavailable || shouldShowLibreDWGUnbound {
            return Color.appWarning
        }
        return resolvedEngine == .libreDWG ? Color.appSuccess : Color.appDoc
    }

    private var engineStatusHint: String? {
        if shouldShowLibreDWGUnavailable {
            return String(localized: "当前构建未包含 LibreDWGBridge，已显示接入提示。")
        }
        if shouldShowLibreDWGUnbound {
            return String(localized: "LibreDWG 已可用，但渲染入口未注册，已自动回退到系统预览。")
        }
        if shouldUseExternalCADPreviewFallback {
            return String(localized: "系统预览无法可靠渲染 DWG/DXF，建议使用同名 PDF。")
        }
        return nil
    }

    private var unitHint: String {
        "1pt = \(Formatters.number(snapshot.metersPerPoint, minFraction: 0, maxFraction: 4))m"
    }

    private var quantityTotal: Double {
        snapshot.quantityItems.reduce(0) { result, item in
            let quantity = ReportBuilder.number(item.quantity)
            let unitPrice = ReportBuilder.number(item.unitPrice)
            let waste = ReportBuilder.number(item.wasteRate) / 100
            return result + quantity * max(0, 1 + waste) * unitPrice
        }
    }

    private var countCategoryOptions: [String] {
        [
            String(localized: "点位"),
            String(localized: "灯位"),
            String(localized: "插座"),
            String(localized: "开关"),
            String(localized: "桥架点"),
            String(localized: "管卡")
        ]
    }

    private var countCategoryStats: [(category: String, count: Int)] {
        var grouped: [String: Int] = [:]
        for marker in snapshot.countMarkers {
            grouped[marker.category, default: 0] += 1
        }
        return grouped
            .map { ($0.key, $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.category.localizedStandardCompare($1.category) == .orderedAscending
                }
                return $0.count > $1.count
            }
    }

    private var selectedCategoryCount: Int {
        snapshot.countMarkers.reduce(0) { result, marker in
            result + (marker.category == selectedCountCategory ? 1 : 0)
        }
    }

    private var highlightedLengthMeasurementID: UUID? {
        guard case let .length(id)? = quantityHighlightTarget else { return nil }
        return id
    }

    private var highlightedAreaMeasurementID: UUID? {
        guard case let .area(id)? = quantityHighlightTarget else { return nil }
        return id
    }

    private var highlightedCountCategory: String? {
        guard case let .countCategory(category)? = quantityHighlightTarget else { return nil }
        return category
    }

    private var projectDrawingTabs: [ProjectDrawing] {
        store.projectDrawings
            .filter { drawing in
                drawing.projectId == activeRequest.projectId &&
                ProjectDrawing.allowedFileExtensions.contains(drawing.fileType.lowercased())
            }
            .sorted { lhs, rhs in
                if lhs.isCurrentVersion != rhs.isCurrentVersion {
                    return lhs.isCurrentVersion && !rhs.isCurrentVersion
                }
                let leftDate = Formatters.parseDateOrDateTime(lhs.importedAt) ?? .distantPast
                let rightDate = Formatters.parseDateOrDateTime(rhs.importedAt) ?? .distantPast
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    if shouldShowLibreDWGUnavailable {
                        CADLibreDWGUnavailableView(
                            fileURL: activeRequest.fileURL,
                            displayName: activeRequest.displayName
                        )
                    } else if shouldUseLibreDWGRenderer,
                              let renderer = CADRendererProvider.libreDWGRenderer(
                                for: activeRequest.fileURL,
                                preferredTextCodePage: selectedTextEncoding.codePageOverride,
                                preferredTextBigFont: selectedTextBigFont.bridgeCode
                              ) {
                        renderer
                    } else if shouldUseExternalCADPreviewFallback {
                        CADExternalPreviewFallbackView(
                            fileURL: activeRequest.fileURL,
                            displayName: activeRequest.displayName,
                            fileType: activeRequest.fileType
                        )
                    } else {
                        AppQuickLookPreviewController(url: activeRequest.fileURL)
                    }

                    if allowsOverlayEditing {
                        overlayLayer(size: geo.size)
                            .allowsHitTesting(tool != .browse)
                            .zIndex(1)
                    }

                    if allowsOverlayEditing && isImmersivePreview {
                        immersiveOverlayControls
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .zIndex(2)
                    }
                }
                .background(Color.black.opacity(0.02))
            }
            .navigationTitle(activeRequest.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) {
                if !isImmersivePreview {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: engineStatusIcon)
                                .foregroundStyle(engineStatusTint)
                            Text("\(String(localized: "预览模式"))：\(engineStatusText)")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if allowsOverlayEditing {
                                Text(unitHint)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let engineStatusHint {
                            Text(engineStatusHint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if shouldUseLibreDWGRenderer {
                            HStack(spacing: 6) {
                                Image(systemName: "character.textbox")
                                    .foregroundStyle(.secondary)
                                Text("\(String(localized: "文字"))：\(selectedTextEncoding.displayName) / \(selectedTextBigFont.displayName)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                            }
                        }
                        if projectDrawingTabs.count > 1 {
                            drawingTabStrip
                        }
                        if allowsOverlayEditing {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(CADOverlayTool.allCases, id: \.self) { candidate in
                                        Button {
                                            selectOverlayTool(candidate)
                                        } label: {
                                            Label(candidate.title, systemImage: candidate.icon)
                                                .font(.caption.weight(.semibold))
                                        }
                                        .buttonStyle(.bordered)
                                        .tint(tool == candidate ? .appPrimaryAction : .secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.thinMaterial)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if allowsOverlayEditing && !isImmersivePreview {
                    bottomControlBar
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "完成")) {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if allowsOverlayEditing {
                        Button {
                            showScaleSheet = true
                            scaleDraft = Formatters.number(snapshot.metersPerPoint, minFraction: 0, maxFraction: 6)
                        } label: {
                            Image(systemName: "slider.horizontal.3").visibleIconStyle()
                        }
                        .accessibilityLabel(String(localized: "比例设置"))
                        if shouldUseLibreDWGRenderer {
                            Button {
                                showTextEncodingDialog = true
                            } label: {
                                Image(systemName: "character.textbox").visibleIconStyle()
                            }
                            .accessibilityLabel(String(localized: "文字编码与字体"))
                        }
                        Button {
                            showQuantitySheet = true
                        } label: {
                            Image(systemName: "sum").visibleIconStyle()
                        }
                        .accessibilityLabel(String(localized: "半自动算量"))
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isImmersivePreview.toggle()
                        }
                    } label: {
                        Image(systemName: isImmersivePreview ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").visibleIconStyle()
                    }
                    .accessibilityLabel(isImmersivePreview ? String(localized: "退出全屏") : String(localized: "全屏图纸"))
                    ShareLink(item: activeRequest.fileURL) {
                        Image(systemName: "square.and.arrow.up").visibleIconStyle()
                    }
                    .accessibilityLabel(String(localized: "分享图纸"))
                    if allowsOverlayEditing {
                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            Image(systemName: "trash").visibleIconStyle().foregroundStyle(.appRisk)
                        }
                        .accessibilityLabel(String(localized: "清空覆盖层"))
                    }
                }
            }
            .onAppear {
                snapshot = restoredSnapshot(for: activeRequest)
                if snapshot.metersPerPoint <= 0 {
                    snapshot.metersPerPoint = 0.02
                }
                if !countCategoryOptions.contains(selectedCountCategory) {
                    selectedCountCategory = countCategoryOptions.first ?? String(localized: "点位")
                }
                lastPersistedSnapshotData = encodedSnapshotData(snapshot)
                selectedTextEncoding = activeRequest.textEncoding
                selectedTextBigFont = activeRequest.textBigFont
                if shouldUseLibreDWGRenderer {
                    isImmersivePreview = true
                }
            }
            .task(id: snapshot) {
                await debouncePersistSnapshot(snapshot)
            }
            .task(id: activeRequest.drawingID) {
                await observeNativeCanvasTransform()
            }
            .onDisappear {
                persistSnapshotIfNeeded(snapshot)
            }
            .confirmationDialog(String(localized: "清空批注和测量？"), isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button(String(localized: "清空全部"), role: .destructive) {
                    var cleared = CADOverlaySnapshot()
                    cleared.metersPerPoint = snapshot.metersPerPoint
                    snapshot = cleared
                    quantityHighlightTarget = nil
                    clearInProgress()
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "将删除本图纸的批注、红线、测量和算量数据。"))
            }
            .alert(String(localized: "图纸定位"), isPresented: $showAlert) {
                Button(String(localized: "知道了"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showTextEncodingDialog) {
                textOptionsSheet
            }
            .sheet(isPresented: $showScaleSheet) {
                scaleEditor
            }
            .sheet(isPresented: $showQuantitySheet) {
                quantitySheet
            }
            .sheet(isPresented: $showNoteSheet) {
                noteEditorSheet
            }
        }
    }

    private var immersiveOverlayControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CADOverlayTool.allCases, id: \.self) { candidate in
                        Button {
                            selectOverlayTool(candidate)
                        } label: {
                            Label(candidate.title, systemImage: candidate.icon)
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(tool == candidate ? .appPrimaryAction : .secondary)
                    }
                }
                .padding(.horizontal, 2)
            }

            if tool != .browse {
                ScrollView(.horizontal, showsIndicators: false) {
                    bottomControlBar
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 0.8)
        )
    }

    private var drawingTabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(projectDrawingTabs) { drawing in
                    let isActive = drawing.id == activeRequest.drawingID
                    Button {
                        switchToDrawing(drawing)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: ProjectDetailDrawingHelper.drawingIcon(drawing.fileType))
                            Text(drawing.name.isEmpty ? drawing.fileName : drawing.name)
                                .lineLimit(1)
                            Text(drawing.version)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(isActive ? .white.opacity(0.8) : .secondary)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(isActive ? .white : .primary)
                        .background(
                            Capsule()
                                .fill(isActive ? Color.appPrimaryAction : Color(uiColor: .tertiarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("切换图纸 \(drawing.name.isEmpty ? drawing.fileName : drawing.name)")
                }
            }
        }
    }

    private var hasNativeDrawingCoordinateSpace: Bool {
        snapshot.coordinateSpace == .drawing && nativeCanvasTransform != nil
    }

    private func canvasPoint(fromStored point: CGPoint) -> CGPoint {
        guard snapshot.coordinateSpace == .drawing,
              let nativeCanvasTransform else { return point }
        return nativeCanvasTransform.canvasPoint(fromDrawing: point)
    }

    private func storedPoint(fromCanvas point: CGPoint) -> CGPoint {
        guard snapshot.coordinateSpace == .drawing,
              let nativeCanvasTransform else { return point }
        return nativeCanvasTransform.drawingPoint(fromCanvas: point)
    }

    private func canvasPoints(fromStored points: [CGPoint]) -> [CGPoint] {
        points.map(canvasPoint(fromStored:))
    }

    @ViewBuilder
    private func overlayLayer(size: CGSize) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.001))

            ForEach(snapshot.strokes) { stroke in
                pathView(points: canvasPoints(fromStored: stroke.points.map(\.cgPoint)))
                    .stroke(strokeColor(stroke.kind), style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round))
            }

            ForEach(snapshot.lengthMeasurements) { measurement in
                let isHighlighted = highlightedLengthMeasurementID == measurement.id
                let storedPoints = measurement.points.map(\.cgPoint)
                let renderedPoints = canvasPoints(fromStored: storedPoints)
                measurementPolyline(renderedPoints)
                    .stroke(
                        isHighlighted ? Color.appWarning : Color.appStrokeInfo,
                        style: StrokeStyle(
                            lineWidth: isHighlighted ? 3.6 : 2,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: measurement.points.count > 2 ? [4, 2] : []
                        )
                    )
                if let center = centerPoint(of: renderedPoints) {
                    measurementBadge(
                        text: lengthLabel(for: storedPoints),
                        isHighlighted: isHighlighted
                    )
                        .position(center)
                }
            }

            ForEach(snapshot.areaMeasurements) { area in
                let isHighlighted = highlightedAreaMeasurementID == area.id
                let storedPoints = area.points.map(\.cgPoint)
                let renderedPoints = canvasPoints(fromStored: storedPoints)
                if renderedPoints.count >= 3 {
                    Path { path in
                        path.move(to: renderedPoints[0])
                        for point in renderedPoints.dropFirst() {
                            path.addLine(to: point)
                        }
                        path.closeSubpath()
                    }
                    .fill(isHighlighted ? Color.appWarning.opacity(0.22) : Color.appSuccessSurfaceSubtle)

                    Path { path in
                        path.move(to: renderedPoints[0])
                        for point in renderedPoints.dropFirst() {
                            path.addLine(to: point)
                        }
                        path.closeSubpath()
                    }
                    .stroke(
                        isHighlighted ? Color.appWarning : Color.appStrokeSuccess,
                        style: StrokeStyle(lineWidth: isHighlighted ? 3 : 2, lineJoin: .round, dash: [5, 3])
                    )

                    if let center = centerPoint(of: renderedPoints) {
                        measurementBadge(text: areaLabel(for: storedPoints), isHighlighted: isHighlighted)
                            .position(center)
                    }
                }
            }

            ForEach(snapshot.notes) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "批注"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(note.text)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.appStrokeWarning, lineWidth: 1)
                )
                .position(canvasPoint(fromStored: note.point.cgPoint))
            }

            ForEach(Array(snapshot.countMarkers.enumerated()), id: \.element.id) { index, marker in
                countMarkerBadge(
                    number: index + 1,
                    category: marker.category,
                    isHighlighted: highlightedCountCategory == marker.category
                )
                    .position(canvasPoint(fromStored: marker.point.cgPoint))
            }

            if !activeStrokePoints.isEmpty {
                pathView(points: canvasPoints(fromStored: activeStrokePoints))
                    .stroke(
                        strokeColor(tool == .redline ? .redline : .annotation),
                        style: StrokeStyle(lineWidth: tool == .redline ? 3 : 2, lineCap: .round, lineJoin: .round)
                    )
            }

            if !activeDragLengthPoints.isEmpty {
                let renderedPoints = canvasPoints(fromStored: activeDragLengthPoints)
                measurementPolyline(renderedPoints)
                    .stroke(Color.appStrokeInfo, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                if let center = centerPoint(of: renderedPoints) {
                    measurementBadge(text: lengthLabel(for: activeDragLengthPoints))
                        .position(center)
                }
            }

            if !pendingLengthPoints.isEmpty {
                measurementPolyline(canvasPoints(fromStored: pendingLengthPoints))
                    .stroke(Color.appStrokeInfo, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 2]))
            }

            if !pendingAreaPoints.isEmpty {
                measurementPolyline(canvasPoints(fromStored: pendingAreaPoints))
                    .stroke(Color.appStrokeSuccess, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [3, 3]))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color.clear)
        .contentShape(Rectangle())
        .highPriorityGesture(overlayDragGesture)
        .simultaneousGesture(overlayTapGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(overlayAccessibilityLabel)
        .accessibilityValue(overlayAccessibilityValue)
        .accessibilityHint(String(localized: "拖动绘制，点按可测量/数数，自动吸附附近关键点并自动保存。"))
    }

    private var overlayDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                switch tool {
                case .annotation, .redline:
                    if activeStrokePoints.isEmpty {
                        activeStrokePoints.append(storedPoint(fromCanvas: value.startLocation))
                    }
                    activeStrokePoints.append(storedPoint(fromCanvas: value.location))
                case .length:
                    if activeDragLengthPoints.isEmpty {
                        activeDragLengthPoints = [snappedOverlayPoint(value.startLocation), snappedOverlayPoint(value.location)]
                    } else {
                        activeDragLengthPoints[1] = snappedOverlayPoint(value.location)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                switch tool {
                case .annotation, .redline:
                    guard activeStrokePoints.count > 1 else {
                        activeStrokePoints.removeAll()
                        return
                    }
                    let stroke = CADStroke(
                        kind: tool == .redline ? .redline : .annotation,
                        points: activeStrokePoints.map(CADPoint.init),
                        lineWidth: tool == .redline ? 3 : 2
                    )
                    snapshot.strokes.append(stroke)
                    activeStrokePoints.removeAll()
                case .length:
                    guard activeDragLengthPoints.count == 2 else { return }
                    snapshot.lengthMeasurements.append(
                        CADLengthMeasurement(points: activeDragLengthPoints.map(CADPoint.init), name: "\(String(localized: "线长")) \(snapshot.lengthMeasurements.count + 1)")
                    )
                    activeDragLengthPoints.removeAll()
                default:
                    break
                }
            }
    }

    private var overlayTapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                switch tool {
                case .continuousLength:
                    pendingLengthPoints.append(snappedOverlayPoint(value.location))
                case .area:
                    pendingAreaPoints.append(snappedOverlayPoint(value.location))
                case .note:
                    let snapped = snappedOverlayPoint(value.location)
                    if let removeIndex = nearestNoteIndex(toCanvasPoint: value.location) {
                        snapshot.notes.remove(at: removeIndex)
                    } else {
                        pendingNotePoint = snapped
                        noteDraft = ""
                        showNoteSheet = true
                    }
                case .count:
                    let snapped = snappedOverlayPoint(value.location)
                    if let removeIndex = nearestCountMarkerIndex(toCanvasPoint: value.location) {
                        snapshot.countMarkers.remove(at: removeIndex)
                    } else {
                        snapshot.countMarkers.append(
                            CADCountMarker(
                                point: CADPoint(snapped),
                                category: selectedCountCategory,
                                createdAt: Formatters.now()
                            )
                        )
                    }
                default:
                    break
                }
            }
    }

    private var bottomControlBar: some View {
        HStack(spacing: 10) {
            switch tool {
            case .continuousLength:
                Button(String(localized: "完成连续测量")) {
                    finalizeContinuousLength()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pendingLengthPoints.count < 2)
                Button(String(localized: "撤销一点")) {
                    if !pendingLengthPoints.isEmpty { _ = pendingLengthPoints.removeLast() }
                }
                .buttonStyle(.bordered)
                .disabled(pendingLengthPoints.isEmpty)
            case .area:
                Button(String(localized: "闭合并计算面积")) {
                    finalizeAreaMeasurement()
                }
                .buttonStyle(.borderedProminent)
                .disabled(pendingAreaPoints.count < 3)
                Button(String(localized: "撤销一点")) {
                    if !pendingAreaPoints.isEmpty { _ = pendingAreaPoints.removeLast() }
                }
                .buttonStyle(.bordered)
                .disabled(pendingAreaPoints.isEmpty)
            case .count:
                Menu {
                    ForEach(countCategoryOptions, id: \.self) { category in
                        Button(category) {
                            selectedCountCategory = category
                        }
                    }
                } label: {
                    Label(selectedCountCategory, systemImage: "number.circle")
                }
                .buttonStyle(.borderedProminent)

                Text("\(String(localized: "当前类别")) \(selectedCategoryCount)\(String(localized: "个"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(String(localized: "点空白新增，点编号删除"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button(String(localized: "撤销一个")) {
                    if !snapshot.countMarkers.isEmpty {
                        _ = snapshot.countMarkers.removeLast()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(snapshot.countMarkers.isEmpty)

                Button(String(localized: "加入算量")) {
                    appendQuantityFromCountCategory(selectedCountCategory)
                }
                .buttonStyle(.bordered)
                .disabled(selectedCategoryCount == 0)
            case .annotation:
                Text(String(localized: "拖动绘制普通批注线"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(String(localized: "撤销一笔")) {
                    removeLastStroke(kind: .annotation)
                }
                .buttonStyle(.bordered)
                .disabled(annotationStrokeCount == 0)
            case .redline:
                Text(String(localized: "拖动绘制红线标记"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(String(localized: "撤销一笔")) {
                    removeLastStroke(kind: .redline)
                }
                .buttonStyle(.bordered)
                .disabled(redlineStrokeCount == 0)
            case .length:
                Text(String(localized: "拖动一次生成一条线长测量"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(String(localized: "撤销一条")) {
                    removeLastLengthMeasurement()
                }
                .buttonStyle(.bordered)
                .disabled(snapshot.lengthMeasurements.isEmpty)
            case .note:
                Text(String(localized: "点空白新增，点现有批注删除"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(String(localized: "撤销一个")) {
                    removeLastNote()
                }
                .buttonStyle(.bordered)
                .disabled(snapshot.notes.isEmpty)
            default:
                Text(
                    tool == .browse
                    ? String(localized: "浏览模式：可缩放、平移图纸")
                    : "\(String(localized: "当前工具"))：\(tool.title)"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if tool == .browse {
                    Text("\(String(localized: "批注")) \(snapshot.strokes.count) · \(String(localized: "测量")) \(snapshot.lengthMeasurements.count + snapshot.areaMeasurements.count) · \(String(localized: "数数")) \(snapshot.countMarkers.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if quantityHighlightTarget != nil {
                        Text(String(localized: "已高亮算量来源"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.appWarning)
                        Button(String(localized: "清除高亮")) {
                            quantityHighlightTarget = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            if tool != .browse {
                Button(String(localized: "切回浏览")) {
                    tool = .browse
                    clearInProgress()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var overlayAccessibilityLabel: String {
        String(localized: "CAD 图纸覆盖层")
    }

    private var overlayAccessibilityValue: String {
        "\(String(localized: "当前工具"))：\(tool.title)，\(String(localized: "批注"))\(snapshot.strokes.count)\(String(localized: "条"))，\(String(localized: "线长"))\(snapshot.lengthMeasurements.count)\(String(localized: "条"))，\(String(localized: "面积"))\(snapshot.areaMeasurements.count)\(String(localized: "条"))，\(String(localized: "文字批注"))\(snapshot.notes.count)\(String(localized: "条"))，\(String(localized: "数数"))\(snapshot.countMarkers.count)\(String(localized: "个"))"
    }

    private var scaleEditor: some View {
        NavigationStack {
            Form {
                Section(String(localized: "比例设置")) {
                    TextField(String(localized: "每 1pt 对应多少米"), text: $scaleDraft)
                        .keyboardType(.decimalPad)
                    Text(String(localized: "用于把屏幕测得的线长/面积换算为工程单位。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "辅助估算，现场以规范和专业判断为准。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "测量比例"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { showScaleSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        let parsed = ReportBuilder.number(scaleDraft)
                        guard parsed > 0 else { return }
                        snapshot.metersPerPoint = parsed
                        showScaleSheet = false
                    }
                }
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
                }
            }
        }
    }

    private var quantitySheet: some View {
        NavigationStack {
            List {
                Section(String(localized: "测量结果快速入算量")) {
                    if snapshot.lengthMeasurements.isEmpty && snapshot.areaMeasurements.isEmpty {
                        Text(String(localized: "先做线长或面积测量，再一键加入算量。"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(snapshot.lengthMeasurements) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text(lengthLabel(for: item.points.map(\.cgPoint)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(String(localized: "加入")) {
                                    appendQuantityFromLength(item)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        ForEach(snapshot.areaMeasurements) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text(areaLabel(for: item.points.map(\.cgPoint)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(String(localized: "加入")) {
                                    appendQuantityFromArea(item)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section(String(localized: "数数结果快速入算量")) {
                    if countCategoryStats.isEmpty {
                        Text(String(localized: "先在图纸上使用“数数”点位，再按类别加入算量。"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(countCategoryStats, id: \.category) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.category)
                                    Text("\(item.count) \(String(localized: "个"))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(String(localized: "加入")) {
                                    appendQuantityFromCountCategory(item.category)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section(String(localized: "半自动算量清单")) {
                    if snapshot.quantityItems.isEmpty {
                        Text(String(localized: "还没有算量条目。"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($snapshot.quantityItems) { $item in
                            VStack(alignment: .leading, spacing: 8) {
                                TextField(String(localized: "名称"), text: $item.name)
                                HStack {
                                    TextField(String(localized: "数量"), text: $item.quantity)
                                        .keyboardType(.decimalPad)
                                    TextField(String(localized: "单位"), text: $item.unit)
                                        .frame(width: 54)
                                    TextField(String(localized: "单价"), text: $item.unitPrice)
                                        .keyboardType(.decimalPad)
                                }
                                HStack {
                                    TextField(String(localized: "损耗率%"), text: $item.wasteRate)
                                        .keyboardType(.decimalPad)
                                    Text(item.source)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                HStack {
                                    Button(String(localized: "定位回图纸")) {
                                        locateQuantitySource(item)
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(quantityHighlightTarget(for: item) == nil)
                                    Spacer(minLength: 0)
                                }
                                Text("\(String(localized: "小计"))：¥\(Formatters.money(quantitySubtotal(item)))")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.appPrimaryAction)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    snapshot.quantityItems.removeAll { $0.id == item.id }
                                } label: {
                                    Label(String(localized: "删除"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                Section(String(localized: "汇总")) {
                    LabeledContent(String(localized: "合计"), value: "¥\(Formatters.money(quantityTotal))")
                    Text(String(localized: "本期算量为半自动：由测量结果生成基础数量后，人工可继续修正数量、单位、损耗率和单价。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "辅助估算，现场以规范和专业判断为准。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(String(localized: "半自动算量"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { showQuantitySheet = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        snapshot.quantityItems.append(
                            CADQuantityItem(
                                name: String(localized: "新条目"),
                                unit: String(localized: "项"),
                                quantity: "1",
                                unitPrice: "0",
                                wasteRate: "0",
                                source: String(localized: "手动"),
                                sourceLinkKind: .manual
                            )
                        )
                    } label: {
                        Image(systemName: "plus").visibleIconStyle()
                    }
                    .buttonStyle(.appIcon())
                }
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
                }
            }
        }
    }

    private var noteEditorSheet: some View {
        NavigationStack {
            Form {
                Section(String(localized: "批注内容")) {
                    TextField(String(localized: "输入批注说明"), text: $noteDraft, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(String(localized: "新增批注"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) {
                        showNoteSheet = false
                        pendingNotePoint = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        guard let point = pendingNotePoint else {
                            showNoteSheet = false
                            return
                        }
                        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        snapshot.notes.append(
                            CADTextNote(
                                text: text,
                                point: CADPoint(point),
                                createdAt: Formatters.now()
                            )
                        )
                        showNoteSheet = false
                        pendingNotePoint = nil
                    }
                    .disabled(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var textOptionsSheet: some View {
        NavigationStack {
            Form {
                Section("常用修复") {
                    Button {
                        Task {
                            await autoDetectTextOptions()
                        }
                    } label: {
                        Label(
                            isAutoDetectingText ? "正在自动识别…" : "文字自动识别",
                            systemImage: "sparkles"
                        )
                    }
                    .disabled(isAutoDetectingText || !shouldUseLibreDWGRenderer)

                    Button {
                        applyTextPreset(encoding: .gb18030, bigFont: .auto)
                    } label: {
                        Label("中文优先（GB18030/SHX 自动）", systemImage: "character.book.closed")
                    }
                    Button {
                        applyTextPreset(encoding: .big5950, bigFont: .big5)
                    } label: {
                        Label("繁体图纸（Big5）", systemImage: "textformat.alt")
                    }
                    Button {
                        applyTextPreset(encoding: .utf8, bigFont: .auto)
                    } label: {
                        Label("UTF-8 图纸", systemImage: "curlybraces")
                    }
                    Text("大多数国内 DWG 乱码先用“中文优先”。如果仍异常，再根据底部诊断里的字体或大字体文件切换。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("文字编码") {
                    Picker("编码", selection: $selectedTextEncoding) {
                        ForEach(CADDrawingTextEncoding.allCases, id: \.self) { encoding in
                            Text(encoding.displayName).tag(encoding)
                        }
                    }
                    Text("用于解决整张图纸的中文解码问题，设置会保存到当前图纸。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("SHX / 大字体") {
                    Picker("字体映射", selection: $selectedTextBigFont) {
                        ForEach(CADDrawingTextBigFont.allCases, id: \.self) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    Text("当 SHX 字体或大字体导致中文、符号显示异常时，切换这里会立即重载当前预览，并跟随这张图纸记忆。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("文字编码与字体")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        showTextEncodingDialog = false
                    }
                }
            }
            .onChange(of: selectedTextEncoding) { _, encoding in
                applyTextEncoding(encoding)
            }
            .onChange(of: selectedTextBigFont) { _, profile in
                applyTextBigFont(profile)
            }
        }
    }

    private func switchToDrawing(_ drawing: ProjectDrawing) {
        guard drawing.id != activeRequest.drawingID else { return }
        persistSnapshotIfNeeded(snapshot)
        nativeCanvasTransform = nil

        let previewTarget = ProjectDetailDrawingHelper.matchingRenderablePreview(
            for: drawing,
            in: store.projectDrawings
        ) ?? drawing

        switch ProjectDetailAssetActions.previewDrawingURL(for: previewTarget) {
        case .success(let url):
            let nextRequest = previewRequest(for: previewTarget, fileURL: url)
            activeRequest = nextRequest
            selectedTextEncoding = nextRequest.textEncoding
            selectedTextBigFont = nextRequest.textBigFont
            snapshot = restoredSnapshot(for: nextRequest)
            quantityHighlightTarget = nil
            if snapshot.metersPerPoint <= 0 {
                snapshot.metersPerPoint = 0.02
            }
            lastPersistedSnapshotData = encodedSnapshotData(snapshot)
            clearInProgress()
            if shouldUseLibreDWGRenderer {
                isImmersivePreview = true
            }
        case .failure(let message):
            StorageIssueLog.record("CAD 图纸切换失败：\(drawing.name.isEmpty ? drawing.fileName : drawing.name)，\(message)")
        }
    }

    @MainActor
    private func observeNativeCanvasTransform() async {
        for await notification in NotificationCenter.default.notifications(named: .libreDWGCanvasTransformDidChange) {
            guard !Task.isCancelled,
                  let userInfo = notification.userInfo,
                  let filePath = userInfo["filePath"] as? String,
                  filePath == activeRequest.fileURL.path,
                  let boundsValue = userInfo["bounds"] as? NSValue,
                  let sizeValue = userInfo["size"] as? NSValue,
                  let zoomScaleNumber = userInfo["zoomScale"] as? NSNumber,
                  let panOffsetValue = userInfo["panOffset"] as? NSValue else { continue }

            let transform = CADNativeCanvasTransform(
                bounds: boundsValue.cgRectValue,
                size: sizeValue.cgSizeValue,
                zoomScale: CGFloat(zoomScaleNumber.doubleValue),
                panOffset: panOffsetValue.cgSizeValue
            )
            nativeCanvasTransform = transform
            if snapshot.coordinateSpace == .canvas, !snapshot.hasOverlayContent {
                snapshot.coordinateSpace = .drawing
            }
        }
    }

    private func previewRequest(for drawing: ProjectDrawing, fileURL: URL) -> ProjectCADPreviewRequest {
        ProjectCADPreviewRequest(
            projectId: drawing.projectId,
            drawingID: drawing.id,
            fileURL: fileURL,
            displayName: drawing.name.isEmpty ? drawing.fileName : drawing.name,
            fileType: drawing.fileType,
            textEncoding: drawing.textEncoding,
            textBigFont: drawing.textBigFont,
            overlaySnapshotData: drawing.cadOverlaySnapshotData,
            onOverlaySnapshotChange: { drawingID, snapshotData in
                guard let index = store.projectDrawings.firstIndex(where: { $0.id == drawingID }) else { return }
                store.projectDrawings[index].cadOverlaySnapshotData = snapshotData
                store.scheduleSave()
            },
            onTextEncodingChange: { drawingID, encoding in
                guard let index = store.projectDrawings.firstIndex(where: { $0.id == drawingID }) else { return }
                store.projectDrawings[index].textEncoding = encoding
                store.scheduleSave()
            },
            onTextBigFontChange: { drawingID, profile in
                guard let index = store.projectDrawings.firstIndex(where: { $0.id == drawingID }) else { return }
                store.projectDrawings[index].textBigFont = profile
                store.scheduleSave()
            }
        )
    }

    private func restoredSnapshot(for request: ProjectCADPreviewRequest) -> CADOverlaySnapshot {
        if var decoded = decodedSnapshotData(request.overlaySnapshotData, displayName: request.displayName) {
            if decoded.coordinateSpace == .canvas, !decoded.hasOverlayContent {
                decoded.coordinateSpace = .drawing
            }
            return decoded
        }
        if var legacy = LegacyCADOverlayStorage.load(for: request.fileURL) {
            if legacy.coordinateSpace == .canvas, !legacy.hasOverlayContent {
                legacy.coordinateSpace = .drawing
            }
            return legacy
        }
        return CADOverlaySnapshot()
    }

    private func decodedSnapshotData(_ raw: String, displayName: String) -> CADOverlaySnapshot? {
        guard !raw.isEmpty,
              let data = Data(base64Encoded: raw) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(CADOverlaySnapshot.self, from: data)
        } catch {
            StorageIssueLog.record("CAD 快照解析失败：\(displayName)，\(error.localizedDescription)")
            return nil
        }
    }

    private func encodedSnapshotData(_ snapshot: CADOverlaySnapshot) -> String {
        do {
            let data = try JSONEncoder().encode(snapshot)
            return data.base64EncodedString()
        } catch {
            StorageIssueLog.record("CAD 快照编码失败：\(activeRequest.displayName)，\(error.localizedDescription)")
            return ""
        }
    }

    private func clearInProgress() {
        activeStrokePoints.removeAll()
        pendingLengthPoints.removeAll()
        pendingAreaPoints.removeAll()
        activeDragLengthPoints.removeAll()
    }

    private func selectOverlayTool(_ nextTool: CADOverlayTool) {
        if tool != nextTool {
            clearInProgress()
        }
        tool = nextTool
    }

    @MainActor
    private func debouncePersistSnapshot(_ value: CADOverlaySnapshot) async {
        guard await DebouncedTask.wait(for: .milliseconds(350)) else { return }
        persistSnapshotIfNeeded(value)
    }

    private func persistSnapshotIfNeeded(_ value: CADOverlaySnapshot) {
        let encoded = encodedSnapshotData(value)
        guard encoded != lastPersistedSnapshotData else { return }
        lastPersistedSnapshotData = encoded
        activeRequest.onOverlaySnapshotChange(activeRequest.drawingID, encoded)
    }

    private func applyTextEncoding(_ encoding: CADDrawingTextEncoding) {
        guard activeRequest.textEncoding != encoding else { return }
        activeRequest.onTextEncodingChange(activeRequest.drawingID, encoding)
        activeRequest = updatingActiveRequest(textEncoding: encoding)
    }

    private func applyTextBigFont(_ profile: CADDrawingTextBigFont) {
        guard activeRequest.textBigFont != profile else { return }
        activeRequest.onTextBigFontChange(activeRequest.drawingID, profile)
        activeRequest = updatingActiveRequest(textBigFont: profile)
    }

    private func applyTextPreset(encoding: CADDrawingTextEncoding, bigFont: CADDrawingTextBigFont) {
        selectedTextEncoding = encoding
        selectedTextBigFont = bigFont
        applyTextEncoding(encoding)
        applyTextBigFont(bigFont)
    }

    @MainActor
    private func autoDetectTextOptions() async {
        guard !isAutoDetectingText else { return }
        isAutoDetectingText = true
        defer { isAutoDetectingText = false }

        do {
            guard let result = try await CADRendererProvider.detectLibreDWGTextOptions(for: activeRequest.fileURL) else {
                alertMessage = String(localized: "当前构建没有可用的 LibreDWG 文字自动识别器。")
                showAlert = true
                return
            }
            let encoding = textEncoding(forCodePage: result.codePage) ?? .auto
            let bigFont = textBigFont(forBridgeCode: result.bigFont) ?? .auto
            applyTextPreset(encoding: encoding, bigFont: bigFont)
            alertMessage = "\(String(localized: "已应用自动识别结果"))：\(encoding.displayName) / \(bigFont.displayName)\n\(result.summary)"
            showAlert = true
        } catch {
            alertMessage = "\(String(localized: "文字自动识别失败"))：\(error.localizedDescription)"
            showAlert = true
        }
    }

    private func textEncoding(forCodePage codePage: Int32?) -> CADDrawingTextEncoding? {
        guard let codePage else { return nil }
        return CADDrawingTextEncoding.allCases.first { $0.codePageOverride == codePage }
    }

    private func textBigFont(forBridgeCode bridgeCode: Int32?) -> CADDrawingTextBigFont? {
        guard let bridgeCode else { return nil }
        return CADDrawingTextBigFont.allCases.first { $0.bridgeCode == bridgeCode }
    }

    private func updatingActiveRequest(
        textEncoding: CADDrawingTextEncoding? = nil,
        textBigFont: CADDrawingTextBigFont? = nil
    ) -> ProjectCADPreviewRequest {
        ProjectCADPreviewRequest(
            projectId: activeRequest.projectId,
            drawingID: activeRequest.drawingID,
            fileURL: activeRequest.fileURL,
            displayName: activeRequest.displayName,
            fileType: activeRequest.fileType,
            textEncoding: textEncoding ?? activeRequest.textEncoding,
            textBigFont: textBigFont ?? activeRequest.textBigFont,
            overlaySnapshotData: activeRequest.overlaySnapshotData,
            onOverlaySnapshotChange: activeRequest.onOverlaySnapshotChange,
            onTextEncodingChange: activeRequest.onTextEncodingChange,
            onTextBigFontChange: activeRequest.onTextBigFontChange
        )
    }

    private func strokeColor(_ kind: CADStroke.StrokeKind) -> Color {
        switch kind {
        case .annotation:
            return .appPrimaryAction
        case .redline:
            return .appRisk
        }
    }

    private func pathView(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func measurementPolyline(_ points: [CGPoint]) -> Path {
        pathView(points: points)
    }

    private func measurementBadge(text: String, isHighlighted: Bool = false) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isHighlighted ? Color.appWarning.opacity(0.2) : Color(uiColor: .secondarySystemGroupedBackground),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(isHighlighted ? Color.appWarning : Color.appStrokeSecondary, lineWidth: isHighlighted ? 1.4 : 0.8)
            )
    }

    private func countMarkerBadge(number: Int, category: String, isHighlighted: Bool = false) -> some View {
        HStack(spacing: 5) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isHighlighted ? Color.appWarning : Color.appPrimaryAction, in: Capsule())
            Text(category)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isHighlighted ? Color.appWarning : .primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            isHighlighted ? Color.appWarning.opacity(0.17) : Color(uiColor: .secondarySystemGroupedBackground),
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(isHighlighted ? Color.appWarning : Color.appStrokeSecondary, lineWidth: isHighlighted ? 1.4 : 0.8)
        )
    }

    private func centerPoint(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { result, point in
            CGPoint(x: result.x + point.x, y: result.y + point.y)
        }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private func lengthInMeters(for points: [CGPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var sum: Double = 0
        for idx in 1..<points.count {
            let dx = points[idx].x - points[idx - 1].x
            let dy = points[idx].y - points[idx - 1].y
            sum += sqrt(dx * dx + dy * dy)
        }
        return sum * snapshot.metersPerPoint
    }

    private func areaInSquareMeters(for points: [CGPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        var shoelace: Double = 0
        for idx in points.indices {
            let next = (idx + 1) % points.count
            shoelace += (points[idx].x * points[next].y) - (points[next].x * points[idx].y)
        }
        let pointArea = abs(shoelace) / 2
        return pointArea * snapshot.metersPerPoint * snapshot.metersPerPoint
    }

    private func lengthLabel(for points: [CGPoint]) -> String {
        "\(Formatters.number(lengthInMeters(for: points), minFraction: 2, maxFraction: 3)) m"
    }

    private func areaLabel(for points: [CGPoint]) -> String {
        "\(Formatters.number(areaInSquareMeters(for: points), minFraction: 2, maxFraction: 3)) m²"
    }

    private func finalizeContinuousLength() {
        guard pendingLengthPoints.count >= 2 else { return }
        snapshot.lengthMeasurements.append(
            CADLengthMeasurement(
                points: pendingLengthPoints.map(CADPoint.init),
                name: "\(String(localized: "连续长度")) \(snapshot.lengthMeasurements.count + 1)"
            )
        )
        pendingLengthPoints.removeAll()
    }

    private func finalizeAreaMeasurement() {
        guard pendingAreaPoints.count >= 3 else { return }
        snapshot.areaMeasurements.append(
            CADAreaMeasurement(
                points: pendingAreaPoints.map(CADPoint.init),
                name: "\(String(localized: "面积")) \(snapshot.areaMeasurements.count + 1)"
            )
        )
        pendingAreaPoints.removeAll()
    }

    private func appendQuantityFromLength(_ measurement: CADLengthMeasurement) {
        let length = lengthInMeters(for: measurement.points.map(\.cgPoint))
        snapshot.quantityItems.append(
            CADQuantityItem(
                name: measurement.name,
                unit: "m",
                quantity: Formatters.number(length, minFraction: 2, maxFraction: 3),
                unitPrice: "0",
                wasteRate: "0",
                source: String(localized: "测量-线长"),
                sourceLinkKind: .lengthMeasurement,
                sourceLinkID: measurement.id
            )
        )
    }

    private func appendQuantityFromArea(_ measurement: CADAreaMeasurement) {
        let area = areaInSquareMeters(for: measurement.points.map(\.cgPoint))
        snapshot.quantityItems.append(
            CADQuantityItem(
                name: measurement.name,
                unit: "m²",
                quantity: Formatters.number(area, minFraction: 2, maxFraction: 3),
                unitPrice: "0",
                wasteRate: "0",
                source: String(localized: "测量-面积"),
                sourceLinkKind: .areaMeasurement,
                sourceLinkID: measurement.id
            )
        )
    }

    private func appendQuantityFromCountCategory(_ category: String) {
        let count = snapshot.countMarkers.reduce(0) { result, marker in
            result + (marker.category == category ? 1 : 0)
        }
        guard count > 0 else { return }
        snapshot.quantityItems.append(
            CADQuantityItem(
                name: category,
                unit: String(localized: "个"),
                quantity: "\(count)",
                unitPrice: "0",
                wasteRate: "0",
                source: String(localized: "数数-\(category)"),
                sourceLinkKind: .countCategory,
                sourceLinkCategory: category
            )
        )
    }

    private func quantityHighlightTarget(for item: CADQuantityItem) -> CADQuantityHighlightTarget? {
        switch item.sourceLinkKind {
        case .manual:
            // 兼容旧快照：历史条目只有 source 文本，没有 sourceLink 字段
            if item.source.contains(String(localized: "测量-线长")),
               let measurement = snapshot.lengthMeasurements.last(where: { $0.name == item.name }) {
                return .length(measurement.id)
            }
            if item.source.contains(String(localized: "测量-面积")),
               let measurement = snapshot.areaMeasurements.last(where: { $0.name == item.name }) {
                return .area(measurement.id)
            }
            if let range = item.source.range(of: String(localized: "数数-")) {
                let category = String(item.source[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !category.isEmpty,
                      snapshot.countMarkers.contains(where: { $0.category == category }) else { return nil }
                return .countCategory(category)
            }
            return nil
        case .lengthMeasurement:
            guard let id = item.sourceLinkID,
                  snapshot.lengthMeasurements.contains(where: { $0.id == id }) else { return nil }
            return .length(id)
        case .areaMeasurement:
            guard let id = item.sourceLinkID,
                  snapshot.areaMeasurements.contains(where: { $0.id == id }) else { return nil }
            return .area(id)
        case .countCategory:
            let category = (item.sourceLinkCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !category.isEmpty,
                  snapshot.countMarkers.contains(where: { $0.category == category }) else { return nil }
            return .countCategory(category)
        }
    }

    private func locateQuantitySource(_ item: CADQuantityItem) {
        guard let target = quantityHighlightTarget(for: item) else {
            alertMessage = String(localized: "该算量条目来源已不存在，无法定位。")
            showAlert = true
            return
        }
        quantityHighlightTarget = target
        tool = .browse
        clearInProgress()
        showQuantitySheet = false
    }

    private func quantitySubtotal(_ item: CADQuantityItem) -> Double {
        let quantity = ReportBuilder.number(item.quantity)
        let unitPrice = ReportBuilder.number(item.unitPrice)
        let waste = ReportBuilder.number(item.wasteRate) / 100
        return quantity * max(0, 1 + waste) * unitPrice
    }

    private var annotationStrokeCount: Int {
        snapshot.strokes.reduce(0) { result, stroke in
            result + (stroke.kind == .annotation ? 1 : 0)
        }
    }

    private var redlineStrokeCount: Int {
        snapshot.strokes.reduce(0) { result, stroke in
            result + (stroke.kind == .redline ? 1 : 0)
        }
    }

    private func removeLastStroke(kind: CADStroke.StrokeKind) {
        guard let index = snapshot.strokes.lastIndex(where: { $0.kind == kind }) else { return }
        snapshot.strokes.remove(at: index)
    }

    private func removeLastLengthMeasurement() {
        guard !snapshot.lengthMeasurements.isEmpty else { return }
        _ = snapshot.lengthMeasurements.removeLast()
    }

    private func removeLastNote() {
        guard !snapshot.notes.isEmpty else { return }
        _ = snapshot.notes.removeLast()
    }

    private var overlaySnapCandidates: [CGPoint] {
        var points: [CGPoint] = []
        points.append(contentsOf: snapshot.countMarkers.map { $0.point.cgPoint })
        points.append(contentsOf: snapshot.notes.map { $0.point.cgPoint })
        for measurement in snapshot.lengthMeasurements {
            points.append(contentsOf: measurement.points.map(\.cgPoint))
        }
        for measurement in snapshot.areaMeasurements {
            points.append(contentsOf: measurement.points.map(\.cgPoint))
        }
        points.append(contentsOf: pendingLengthPoints)
        points.append(contentsOf: pendingAreaPoints)
        points.append(contentsOf: activeDragLengthPoints)
        return points
    }

    private func snappedOverlayPoint(_ rawPoint: CGPoint) -> CGPoint {
        switch tool {
        case .length, .continuousLength, .area, .note, .count:
            break
        default:
            return storedPoint(fromCanvas: rawPoint)
        }

        guard let nearest = nearestPoint(toCanvasPoint: rawPoint, inStoredPoints: overlaySnapCandidates, maxDistance: overlaySnapTolerance) else {
            return storedPoint(fromCanvas: rawPoint)
        }
        return nearest
    }

    private func nearestCountMarkerIndex(toCanvasPoint point: CGPoint) -> Int? {
        var bestIndex: Int?
        var bestDistance = overlaySnapTolerance
        for (index, marker) in snapshot.countMarkers.enumerated() {
            let target = canvasPoint(fromStored: marker.point.cgPoint)
            let distance = hypot(target.x - point.x, target.y - point.y)
            if distance <= bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func nearestNoteIndex(toCanvasPoint point: CGPoint) -> Int? {
        var bestIndex: Int?
        var bestDistance = overlaySnapTolerance
        for (index, note) in snapshot.notes.enumerated() {
            let target = canvasPoint(fromStored: note.point.cgPoint)
            let distance = hypot(target.x - point.x, target.y - point.y)
            if distance <= bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func nearestPoint(toCanvasPoint source: CGPoint, inStoredPoints points: [CGPoint], maxDistance: CGFloat) -> CGPoint? {
        var nearest: CGPoint?
        var nearestDistance = maxDistance
        for point in points {
            let canvasPoint = canvasPoint(fromStored: point)
            let distance = hypot(canvasPoint.x - source.x, canvasPoint.y - source.y)
            if distance <= nearestDistance {
                nearestDistance = distance
                nearest = point
            }
        }
        return nearest
    }
}
