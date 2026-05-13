import SwiftUI

struct ProjectCADPreviewRequest: Identifiable {
    let id = UUID()
    let drawingID: UUID
    let fileURL: URL
    let displayName: String
    let fileType: String
    let textEncoding: CADDrawingTextEncoding
    let overlaySnapshotData: String
    let onOverlaySnapshotChange: (UUID, String) -> Void
    let onTextEncodingChange: (UUID, CADDrawingTextEncoding) -> Void

    var preferredTextCodePage: Int32? {
        textEncoding.codePageOverride
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

private struct CADQuantityItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var unit: String
    var quantity: String
    var unitPrice: String
    var wasteRate: String
    var source: String
}

private struct CADOverlaySnapshot: Codable, Equatable {
    var metersPerPoint: Double = 0.02
    var strokes: [CADStroke] = []
    var lengthMeasurements: [CADLengthMeasurement] = []
    var areaMeasurements: [CADAreaMeasurement] = []
    var notes: [CADTextNote] = []
    var quantityItems: [CADQuantityItem] = []
}

private enum CADOverlayTool: String, CaseIterable {
    case browse
    case annotation
    case redline
    case length
    case continuousLength
    case area
    case note

    var title: String {
        switch self {
        case .browse: return String(localized: "浏览")
        case .annotation: return String(localized: "批注")
        case .redline: return String(localized: "红线")
        case .length: return String(localized: "线长")
        case .continuousLength: return String(localized: "连续长度")
        case .area: return String(localized: "面积")
        case .note: return String(localized: "文字批注")
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
        }
    }
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
    @Environment(\.dismiss) private var dismiss

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
    @State private var lastPersistedSnapshotData = ""
    @State private var isImmersivePreview = false
    @State private var selectedTextEncoding: CADDrawingTextEncoding

    init(request: ProjectCADPreviewRequest) {
        self.request = request
        _selectedTextEncoding = State(initialValue: request.textEncoding)
    }

    private var preferredEngine: CADPreviewEngine {
        CADPreviewEngineStore.selected
    }

    private var resolvedEngine: CADPreviewEngine {
        CADPreviewCapability.resolvedEngine(preferredEngine)
    }

    private var isCADFile: Bool {
        CADPreviewCapability.isCADFile(extension: request.fileType)
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

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    if shouldShowLibreDWGUnavailable {
                        CADLibreDWGUnavailableView(
                            fileURL: request.fileURL,
                            displayName: request.displayName
                        )
                    } else if shouldUseLibreDWGRenderer,
                              let renderer = CADRendererProvider.libreDWGRenderer(
                                for: request.fileURL,
                                preferredTextCodePage: selectedTextEncoding.codePageOverride
                              ) {
                        renderer
                    } else if shouldUseExternalCADPreviewFallback {
                        CADExternalPreviewFallbackView(
                            fileURL: request.fileURL,
                            displayName: request.displayName,
                            fileType: request.fileType
                        )
                    } else {
                        AppQuickLookPreviewController(url: request.fileURL)
                    }

                    if allowsOverlayEditing {
                        overlayLayer(size: geo.size)
                            .allowsHitTesting(tool != .browse)
                    }
                }
                .background(Color.black.opacity(0.02))
            }
            .navigationTitle(request.displayName)
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
                                Text("\(String(localized: "文字编码"))：\(selectedTextEncoding.displayName)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                            }
                        }
                        if allowsOverlayEditing {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(CADOverlayTool.allCases, id: \.self) { candidate in
                                        Button {
                                            tool = candidate
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
                            .accessibilityLabel(String(localized: "文字编码"))
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
                    ShareLink(item: request.fileURL) {
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
                snapshot = restoredSnapshot()
                if snapshot.metersPerPoint <= 0 {
                    snapshot.metersPerPoint = 0.02
                }
                lastPersistedSnapshotData = encodedSnapshotData(snapshot)
                selectedTextEncoding = request.textEncoding
                if shouldUseLibreDWGRenderer {
                    isImmersivePreview = true
                }
            }
            .task(id: snapshot) {
                await debouncePersistSnapshot(snapshot)
            }
            .onDisappear {
                persistSnapshotIfNeeded(snapshot)
            }
            .confirmationDialog(String(localized: "清空批注和测量？"), isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button(String(localized: "清空全部"), role: .destructive) {
                    snapshot = CADOverlaySnapshot(metersPerPoint: snapshot.metersPerPoint)
                    clearInProgress()
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "将删除本图纸的批注、红线、测量和算量数据。"))
            }
            .confirmationDialog(String(localized: "文字编码"), isPresented: $showTextEncodingDialog, titleVisibility: .visible) {
                ForEach(CADDrawingTextEncoding.allCases, id: \.self) { encoding in
                    Button(encoding.displayName) {
                        applyTextEncoding(encoding)
                    }
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "当图纸文字出现乱码时，可切换编码后立即重载当前预览。"))
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

    @ViewBuilder
    private func overlayLayer(size: CGSize) -> some View {
        ZStack {
            ForEach(snapshot.strokes) { stroke in
                pathView(points: stroke.points.map(\.cgPoint))
                    .stroke(strokeColor(stroke.kind), style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round))
            }

            ForEach(snapshot.lengthMeasurements) { measurement in
                measurementPolyline(measurement.points.map(\.cgPoint))
                    .stroke(Color.appStrokeInfo, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: measurement.points.count > 2 ? [4, 2] : []))
                if let center = centerPoint(of: measurement.points.map(\.cgPoint)) {
                    measurementBadge(text: lengthLabel(for: measurement.points.map(\.cgPoint)))
                        .position(center)
                }
            }

            ForEach(snapshot.areaMeasurements) { area in
                let points = area.points.map(\.cgPoint)
                if points.count >= 3 {
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                        path.closeSubpath()
                    }
                    .fill(Color.appSuccessSurfaceSubtle)

                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                        path.closeSubpath()
                    }
                    .stroke(Color.appStrokeSuccess, style: StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [5, 3]))

                    if let center = centerPoint(of: points) {
                        measurementBadge(text: areaLabel(for: points))
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
                .position(note.point.cgPoint)
            }

            if !activeStrokePoints.isEmpty {
                pathView(points: activeStrokePoints)
                    .stroke(
                        strokeColor(tool == .redline ? .redline : .annotation),
                        style: StrokeStyle(lineWidth: tool == .redline ? 3 : 2, lineCap: .round, lineJoin: .round)
                    )
            }

            if !activeDragLengthPoints.isEmpty {
                measurementPolyline(activeDragLengthPoints)
                    .stroke(Color.appStrokeInfo, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                if let center = centerPoint(of: activeDragLengthPoints) {
                    measurementBadge(text: lengthLabel(for: activeDragLengthPoints))
                        .position(center)
                }
            }

            if !pendingLengthPoints.isEmpty {
                measurementPolyline(pendingLengthPoints)
                    .stroke(Color.appStrokeInfo, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 2]))
            }

            if !pendingAreaPoints.isEmpty {
                measurementPolyline(pendingAreaPoints)
                    .stroke(Color.appStrokeSuccess, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [3, 3]))
            }
        }
        .contentShape(Rectangle())
        .gesture(overlayDragGesture)
        .simultaneousGesture(overlayTapGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(overlayAccessibilityLabel)
        .accessibilityValue(overlayAccessibilityValue)
        .accessibilityHint(String(localized: "双击并拖动可绘制或测量，数据会自动保存。"))
    }

    private var overlayDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                switch tool {
                case .annotation, .redline:
                    activeStrokePoints.append(value.location)
                case .length:
                    if activeDragLengthPoints.isEmpty {
                        activeDragLengthPoints = [value.startLocation, value.location]
                    } else {
                        activeDragLengthPoints[1] = value.location
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
                    pendingLengthPoints.append(value.location)
                case .area:
                    pendingAreaPoints.append(value.location)
                case .note:
                    pendingNotePoint = value.location
                    noteDraft = ""
                    showNoteSheet = true
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
            default:
                Text(
                    tool == .browse
                    ? String(localized: "浏览模式：可缩放、平移图纸")
                    : "\(String(localized: "当前工具"))：\(tool.title)"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        "\(String(localized: "当前工具"))：\(tool.title)，\(String(localized: "批注"))\(snapshot.strokes.count)\(String(localized: "条"))，\(String(localized: "线长"))\(snapshot.lengthMeasurements.count)\(String(localized: "条"))，\(String(localized: "面积"))\(snapshot.areaMeasurements.count)\(String(localized: "条"))，\(String(localized: "文字批注"))\(snapshot.notes.count)\(String(localized: "条"))"
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
                                name: "新条目",
                                unit: "项",
                                quantity: "1",
                                unitPrice: "0",
                                wasteRate: "0",
                                source: String(localized: "手动")
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

    private func restoredSnapshot() -> CADOverlaySnapshot {
        if let decoded = decodedSnapshotData(request.overlaySnapshotData) {
            return decoded
        }
        if let legacy = LegacyCADOverlayStorage.load(for: request.fileURL) {
            return legacy
        }
        return CADOverlaySnapshot()
    }

    private func decodedSnapshotData(_ raw: String) -> CADOverlaySnapshot? {
        guard !raw.isEmpty,
              let data = Data(base64Encoded: raw) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(CADOverlaySnapshot.self, from: data)
        } catch {
            StorageIssueLog.record("CAD 快照解析失败：\(request.displayName)，\(error.localizedDescription)")
            return nil
        }
    }

    private func encodedSnapshotData(_ snapshot: CADOverlaySnapshot) -> String {
        do {
            let data = try JSONEncoder().encode(snapshot)
            return data.base64EncodedString()
        } catch {
            StorageIssueLog.record("CAD 快照编码失败：\(request.displayName)，\(error.localizedDescription)")
            return ""
        }
    }

    private func clearInProgress() {
        activeStrokePoints.removeAll()
        pendingLengthPoints.removeAll()
        pendingAreaPoints.removeAll()
        activeDragLengthPoints.removeAll()
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
        request.onOverlaySnapshotChange(request.drawingID, encoded)
    }

    private func applyTextEncoding(_ encoding: CADDrawingTextEncoding) {
        guard selectedTextEncoding != encoding else { return }
        selectedTextEncoding = encoding
        request.onTextEncodingChange(request.drawingID, encoding)
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

    private func measurementBadge(text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.appStrokeSecondary, lineWidth: 0.8))
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
                source: String(localized: "测量-线长")
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
                source: String(localized: "测量-面积")
            )
        )
    }

    private func quantitySubtotal(_ item: CADQuantityItem) -> Double {
        let quantity = ReportBuilder.number(item.quantity)
        let unitPrice = ReportBuilder.number(item.unitPrice)
        let waste = ReportBuilder.number(item.wasteRate) / 100
        return quantity * max(0, 1 + waste) * unitPrice
    }
}
