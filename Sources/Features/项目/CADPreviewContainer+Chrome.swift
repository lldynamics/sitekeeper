import SwiftUI
#if os(iOS)
import UIKit
#endif

enum CADCommandBarChrome {
    case standard
    case immersive
}

extension CADPreviewContainer {
    var immersiveTopSafePadding: CGFloat {
#if os(iOS)
        return max(currentWindowSafeAreaInsets.top, 8) + 8
#else
        return 16
#endif
    }

    var immersiveBottomSafePadding: CGFloat {
#if os(iOS)
        return max(currentWindowSafeAreaInsets.bottom, 0) + 12
#else
        return 12
#endif
    }

#if os(iOS)
    private var currentWindowSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets ?? .zero
    }
#endif

    var immersiveTopControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            cadCommandHeader(chrome: .immersive)
            cadPrimaryCommandBar(chrome: .immersive)
        }
    }

    func floatingCircleButton(
        systemImage: String,
        label: String,
        active: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? .secondary : (active ? .white : Color.appPrimaryAction))
        .background {
            Circle().fill(active ? AnyShapeStyle(Color.appPrimaryAction) : AnyShapeStyle(.regularMaterial))
        }
        .opacity(disabled ? 0.45 : 1)
        .disabled(disabled)
            .accessibilityLabel(label)
    }

    @ViewBuilder
    func cadCommandHeader(chrome: CADCommandBarChrome) -> some View {
        HStack(spacing: chrome == .immersive ? 8 : 10) {
            cadIconButton(
                systemImage: "xmark",
                label: String(localized: "完成"),
                chrome: chrome
            ) {
                dismiss()
            }

            VStack(alignment: .leading, spacing: chrome == .immersive ? 2 : 3) {
                Text(activeRequest.displayName)
                    .font(chrome == .immersive ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(chrome == .immersive ? 0.78 : 0.75)
                if allowsOverlayEditing {
                    Text(unitHint)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            .padding(.horizontal, chrome == .immersive ? 10 : 0)
            .padding(.vertical, chrome == .immersive ? 7 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if chrome == .immersive {
                    Capsule().fill(.regularMaterial)
                }
            }

            if allowsOverlayEditing {
                cadIconButton(
                    systemImage: "arrow.uturn.backward",
                    label: String(localized: "撤销上一步"),
                    chrome: chrome,
                    disabled: !canUndoOverlayChange
                ) {
                    undoLastOverlayChange()
                }

                cadIconButton(
                    systemImage: "arrow.uturn.forward",
                    label: String(localized: "前进一步"),
                    chrome: chrome,
                    disabled: !canRedoOverlayChange
                ) {
                    redoOverlayChange()
                }
            }

            cadIconButton(
                systemImage: isImmersivePreview ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                label: isImmersivePreview ? String(localized: "退出全屏") : String(localized: "全屏图纸"),
                chrome: chrome
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isImmersivePreview.toggle()
                }
            }

            cadMoreMenu(chrome: chrome)
        }
    }

    var isMeasurementWorkflowActive: Bool {
        tool == .length ||
            tool == .continuousLength ||
            tool == .area ||
            tool == .count ||
            showScaleSheet ||
            showQuantitySheet
    }

    var isAnnotationWorkflowActive: Bool {
        tool == .annotation ||
            tool == .cloud ||
            tool == .arrow ||
            tool == .note ||
            tool == .issueMarker
    }

    @ViewBuilder
    func cadPrimaryCommandBar(chrome: CADCommandBarChrome) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                cadCommandButton(
                    systemImage: "hand.tap",
                    label: String(localized: "看图"),
                    active: tool == .browse,
                    chrome: chrome
                ) {
                    selectOverlayTool(.browse)
                }

                if allowsOverlayEditing {
                    cadCommandButton(
                        systemImage: "rectangle.3.group",
                        label: String(localized: "显示"),
                        active: showOverlayLayerSheet,
                        chrome: chrome
                    ) {
                        showOverlayLayerSheet = true
                    }

                    if shouldShowNativeCADLayoutMenu {
                        cadDrawingLayoutMenu(chrome: chrome)
                    }

                    if shouldShowNativeCADLayerMenu {
                        cadDrawingLayerMenu(chrome: chrome)
                    }

                    if isDWGFile {
                        cadPerformanceMenu(chrome: chrome)
                    }

                    cadMeasurementMenu(chrome: chrome)
                    cadAnnotationMenu(chrome: chrome)
                }
            }
            .padding(chrome == .immersive ? 2 : 0)
        }
    }

    var shouldShowNativeCADLayerMenu: Bool {
        isDWGFile && !nativeCADLayers.isEmpty
    }

    var shouldShowNativeCADLayoutMenu: Bool {
        isDWGFile && !nativeCADLayouts.isEmpty
    }

    var nativeCADCurrentLayout: NativeCAD.CADLayout? {
        nativeCADLayouts.first { $0.id == nativeCADCurrentLayoutID }
            ?? nativeCADLayouts.first(where: \.isModelSpace)
            ?? nativeCADLayouts.first
    }

    var nativeCADLayoutMenuTitle: String {
        guard let layout = nativeCADCurrentLayout else {
            return String(localized: "模型/布局")
        }
        return layout.isModelSpace ? String(localized: "模型") : nativeCADLayoutDisplayName(layout)
    }

    var nativeCADLayoutMenuIcon: String {
        guard let layout = nativeCADCurrentLayout else { return "rectangle.3.group" }
        return layout.isModelSpace ? "cube.transparent" : "rectangle.on.rectangle"
    }

    var nativeCADSelectedLayoutIsPaperSpace: Bool {
        nativeCADCurrentLayout.map { !$0.isModelSpace } ?? false
    }

    @ViewBuilder
    func cadDrawingLayoutMenu(chrome: CADCommandBarChrome) -> some View {
        switch chrome {
        case .standard:
            Menu {
                cadDrawingLayoutMenuContent
            } label: {
                cadCommandMenuLabel(
                    systemImage: nativeCADLayoutMenuIcon,
                    label: nativeCADLayoutMenuTitle,
                    active: nativeCADSelectedLayoutIsPaperSpace,
                    chrome: chrome
                )
            }
            .buttonStyle(.bordered)
            .tint(nativeCADSelectedLayoutIsPaperSpace ? .appPrimaryAction : .secondary)
            .accessibilityLabel(String(localized: "选择模型或布局"))
        case .immersive:
            Menu {
                cadDrawingLayoutMenuContent
            } label: {
                cadCommandMenuLabel(
                    systemImage: nativeCADLayoutMenuIcon,
                    label: nativeCADLayoutMenuTitle,
                    active: nativeCADSelectedLayoutIsPaperSpace,
                    chrome: chrome
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "选择模型或布局"))
        }
    }

    @ViewBuilder
    var cadDrawingLayoutMenuContent: some View {
        ForEach(nativeCADLayouts) { layout in
            Button {
                selectNativeCADLayout(layout.id)
            } label: {
                Label(
                    nativeCADLayoutDisplayName(layout),
                    systemImage: layout.id == nativeCADCurrentLayout?.id ? "checkmark.circle.fill" : nativeCADLayoutIcon(layout)
                )
            }
        }
    }

    func nativeCADLayoutDisplayName(_ layout: NativeCAD.CADLayout) -> String {
        if layout.isModelSpace {
            return String(localized: "模型")
        }
        let trimmed = layout.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? layout.id : trimmed
    }

    func nativeCADLayoutIcon(_ layout: NativeCAD.CADLayout) -> String {
        layout.isModelSpace ? "cube.transparent" : "rectangle.on.rectangle"
    }

    func selectNativeCADLayout(_ layoutID: String) {
        guard nativeCADCurrentLayoutID != layoutID else { return }
        nativeCADCurrentLayoutID = layoutID
        nativeCanvasTransform = nil
        nativeSnapPoints.removeAll()
        nativeSnapSourcePoints.removeAll()
        nativeEndpointSnapPoints.removeAll()
        nativeMidpointSnapPoints.removeAll()
        nativeCenterSnapPoints.removeAll()
        nativeSnapPointBuckets = CADNativeSnapPointBuckets()
        clearInProgress()
    }

    var nativeCADHiddenLayerCount: Int {
        nativeCADLayers.filter { !isNativeCADLayerVisible($0) }.count
    }

    @ViewBuilder
    func cadDrawingLayerMenu(chrome: CADCommandBarChrome) -> some View {
        switch chrome {
        case .standard:
            Menu {
                cadDrawingLayerMenuContent
            } label: {
                cadCommandMenuLabel(
                    systemImage: "square.3.layers.3d",
                    label: String(localized: "图层"),
                    active: nativeCADHiddenLayerCount > 0,
                    chrome: chrome
                )
            }
            .buttonStyle(.bordered)
            .tint(nativeCADHiddenLayerCount > 0 ? .appPrimaryAction : .secondary)
        case .immersive:
            Menu {
                cadDrawingLayerMenuContent
            } label: {
                cadCommandMenuLabel(
                    systemImage: "square.3.layers.3d",
                    label: String(localized: "图层"),
                    active: nativeCADHiddenLayerCount > 0,
                    chrome: chrome
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    func cadMeasurementMenu(chrome: CADCommandBarChrome) -> some View {
        switch chrome {
        case .standard:
            Menu {
                cadMeasurementMenuContent
            } label: {
                cadCommandMenuLabel(
                    systemImage: "ruler",
                    label: String(localized: "测量"),
                    active: isMeasurementWorkflowActive,
                    chrome: chrome
                )
            }
            .buttonStyle(.bordered)
            .tint(isMeasurementWorkflowActive ? .appPrimaryAction : .secondary)
            .disabled(!canCaptureDrawingOverlay)
            .opacity(canCaptureDrawingOverlay ? 1 : 0.45)
        case .immersive:
            Menu {
                cadMeasurementMenuContent
            } label: {
                cadCommandMenuLabel(
                    systemImage: "ruler",
                    label: String(localized: "测量"),
                    active: isMeasurementWorkflowActive,
                    chrome: chrome
                )
            }
            .buttonStyle(.plain)
            .disabled(!canCaptureDrawingOverlay)
            .opacity(canCaptureDrawingOverlay ? 1 : 0.45)
        }
    }

    @ViewBuilder
    func cadAnnotationMenu(chrome: CADCommandBarChrome) -> some View {
        switch chrome {
        case .standard:
            Menu {
                cadAnnotationMenuContent
            } label: {
                cadCommandMenuLabel(
                    systemImage: "highlighter",
                    label: String(localized: "批注"),
                    active: isAnnotationWorkflowActive,
                    chrome: chrome
                )
            }
            .buttonStyle(.bordered)
            .tint(isAnnotationWorkflowActive ? .appPrimaryAction : .secondary)
            .disabled(!canCaptureDrawingOverlay)
            .opacity(canCaptureDrawingOverlay ? 1 : 0.45)
        case .immersive:
            Menu {
                cadAnnotationMenuContent
            } label: {
                cadCommandMenuLabel(
                    systemImage: "highlighter",
                    label: String(localized: "批注"),
                    active: isAnnotationWorkflowActive,
                    chrome: chrome
                )
            }
            .buttonStyle(.plain)
            .disabled(!canCaptureDrawingOverlay)
            .opacity(canCaptureDrawingOverlay ? 1 : 0.45)
        }
    }

    @ViewBuilder
    func cadMoreMenu(chrome: CADCommandBarChrome) -> some View {
        switch chrome {
        case .standard:
            Menu {
                cadMoreMenuContent
            } label: {
                cadCommandMenuLabel(
                    systemImage: "ellipsis",
                    label: String(localized: "更多"),
                    active: false,
                    chrome: chrome
                )
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(String(localized: "更多图纸操作"))
        case .immersive:
            Menu {
                cadMoreMenuContent
            } label: {
                cadCommandMenuLabel(
                    systemImage: "ellipsis",
                    label: String(localized: "更多"),
                    active: false,
                    chrome: chrome
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "更多图纸操作"))
        }
    }

    @ViewBuilder
    var cadMeasurementMenuContent: some View {
        Button {
            selectOverlayTool(.length)
        } label: {
            Label(String(localized: "线长"), systemImage: "ruler")
        }
        Button {
            selectOverlayTool(.continuousLength)
        } label: {
            Label(String(localized: "连续长度"), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
        }
        Button {
            selectOverlayTool(.area)
        } label: {
            Label(String(localized: "面积"), systemImage: "square.dashed")
        }
        Button {
            selectOverlayTool(.count)
        } label: {
            Label(String(localized: "数数"), systemImage: "number.circle")
        }
        Divider()
        Button {
            openScaleCalibrationSheet()
        } label: {
            Label(String(localized: "标定"), systemImage: "slider.horizontal.3")
        }
        Button {
            showQuantitySheet = true
        } label: {
            Label(String(localized: "入算量"), systemImage: "sum")
        }
    }

    @ViewBuilder
    var cadDrawingLayerMenuContent: some View {
        Button {
            showAllNativeCADLayers()
        } label: {
            Label(String(localized: "显示全部图层"), systemImage: "eye")
        }

        Divider()

        ForEach(nativeCADLayers) { layer in
            Button {
                toggleNativeCADLayer(layer.id)
            } label: {
                Label(layer.name, systemImage: isNativeCADLayerVisible(layer) ? "checkmark.circle.fill" : "circle")
            }
        }
    }

    func isNativeCADLayerVisible(_ layer: NativeCAD.CADLayer) -> Bool {
        nativeCADVisibleLayerIDs?.contains(layer.id) ?? layer.isVisible
    }

    func toggleNativeCADLayer(_ layerID: String) {
        var nextVisible = nativeCADVisibleLayerIDs ?? Set(nativeCADLayers.filter(\.isVisible).map(\.id))
        if nextVisible.contains(layerID) {
            nextVisible.remove(layerID)
        } else {
            nextVisible.insert(layerID)
        }
        nativeCADVisibleLayerIDs = nextVisible
    }

    func showAllNativeCADLayers() {
        nativeCADVisibleLayerIDs = Set(nativeCADLayers.map(\.id))
    }

    var cadPerformanceOptionEnabledCount: Int {
        [
            rendersCADTextOverlays,
            rendersCADLineTypes,
            rendersCADLineWeights,
            rendersCADDimensionDetails,
            buildsCADTextSearchIndex,
            publishesCADSnapPoints,
            publishesCADSnapIntersections,
            rendersCADHatchBoundaries,
            rendersCADHatches,
            rendersCADPlaceholders,
            showsCADOverviewMap,
            showsCADRendererDiagnostics
        ].filter { $0 }.count
    }

    @ViewBuilder
    func cadPerformanceMenu(chrome: CADCommandBarChrome) -> some View {
        switch chrome {
        case .standard:
            Menu {
                cadPerformanceMenuContent
            } label: {
                cadCommandMenuLabel(
                    systemImage: "speedometer",
                    label: cadPerformanceMenuTitle,
                    active: cadPerformanceOptionEnabledCount > 0,
                    chrome: chrome
                )
            }
            .buttonStyle(.bordered)
            .tint(cadPerformanceOptionEnabledCount > 0 ? .appPrimaryAction : .secondary)
        case .immersive:
            Menu {
                cadPerformanceMenuContent
            } label: {
                cadCommandMenuLabel(
                    systemImage: "speedometer",
                    label: cadPerformanceMenuTitle,
                    active: cadPerformanceOptionEnabledCount > 0,
                    chrome: chrome
                )
            }
            .buttonStyle(.plain)
        }
    }

    var cadPerformanceMenuTitle: String {
        cadPerformanceOptionEnabledCount == 0
            ? String(localized: "性能优先")
            : "\(String(localized: "细节")) \(cadPerformanceOptionEnabledCount)"
    }

    @ViewBuilder
    var cadPerformanceMenuContent: some View {
        Button {
            rendersCADTextOverlays.toggle()
        } label: {
            Label(String(localized: "文字显示"), systemImage: rendersCADTextOverlays ? "checkmark.circle.fill" : "circle")
        }
        Button {
            buildsCADTextSearchIndex.toggle()
        } label: {
            Label(String(localized: "文字搜索索引"), systemImage: buildsCADTextSearchIndex ? "checkmark.circle.fill" : "circle")
        }
        Button {
            rendersCADLineTypes.toggle()
        } label: {
            Label(String(localized: "虚线/点划线"), systemImage: rendersCADLineTypes ? "checkmark.circle.fill" : "circle")
        }
        Button {
            rendersCADLineWeights.toggle()
        } label: {
            Label(String(localized: "线宽"), systemImage: rendersCADLineWeights ? "checkmark.circle.fill" : "circle")
        }
        Button {
            rendersCADDimensionDetails.toggle()
        } label: {
            Label(String(localized: "标注箭头"), systemImage: rendersCADDimensionDetails ? "checkmark.circle.fill" : "circle")
        }
        Button {
            publishesCADSnapPoints.toggle()
        } label: {
            Label(String(localized: "吸附点"), systemImage: publishesCADSnapPoints ? "checkmark.circle.fill" : "circle")
        }
        Button {
            publishesCADSnapIntersections.toggle()
        } label: {
            Label(String(localized: "交点吸附"), systemImage: publishesCADSnapIntersections ? "checkmark.circle.fill" : "circle")
        }
        .disabled(!publishesCADSnapPoints)
        Button {
            rendersCADHatchBoundaries.toggle()
        } label: {
            Label(String(localized: "填充细节"), systemImage: rendersCADHatchBoundaries ? "checkmark.circle.fill" : "circle")
        }
        Button {
            rendersCADHatches.toggle()
        } label: {
            Label(String(localized: "填充实体"), systemImage: rendersCADHatches ? "checkmark.circle.fill" : "circle")
        }
        Button {
            rendersCADPlaceholders.toggle()
        } label: {
            Label(String(localized: "占位对象"), systemImage: rendersCADPlaceholders ? "checkmark.circle.fill" : "circle")
        }
        Button {
            showsCADOverviewMap.toggle()
        } label: {
            Label(String(localized: "全局小窗"), systemImage: showsCADOverviewMap ? "checkmark.circle.fill" : "circle")
        }
        Divider()
        Button {
            showsCADRendererDiagnostics.toggle()
        } label: {
            Label(String(localized: "渲染诊断"), systemImage: showsCADRendererDiagnostics ? "checkmark.circle.fill" : "circle")
        }
    }

    @ViewBuilder
    var cadAnnotationMenuContent: some View {
        Button {
            selectOverlayTool(.annotation)
        } label: {
            Label(String(localized: "手绘批注"), systemImage: "highlighter")
        }
        Button {
            selectOverlayTool(.cloud)
        } label: {
            Label(String(localized: "云线"), systemImage: "cloud")
        }
        Button {
            selectOverlayTool(.arrow)
        } label: {
            Label(String(localized: "箭头"), systemImage: "arrow.up.right")
        }
        Button {
            selectOverlayTool(.note)
        } label: {
            Label(String(localized: "文字批注"), systemImage: "text.bubble")
        }
        Button {
            selectOverlayTool(.issueMarker)
        } label: {
            Label(String(localized: "拍照问题点"), systemImage: "camera.viewfinder")
        }
    }

    @ViewBuilder
    var cadMoreMenuContent: some View {
        Button {
            showShareSheet = true
        } label: {
            Label(String(localized: "分享原 CAD 文件"), systemImage: "square.and.arrow.up")
        }
        if shouldUseCADKernelRenderer {
            Button {
                saveCurrentViewState(showConfirmation: true)
            } label: {
                Label(String(localized: "保存当前视图状态"), systemImage: "bookmark")
            }
        }
        if canUseCADTextRepair {
            Button {
                showTextEncodingDialog = true
            } label: {
                Label(String(localized: "文字修复"), systemImage: "character.textbox")
            }
        }
        if allowsOverlayEditing {
            Menu {
                Button {
                    showAnnotationExportFormatDialog = true
                } label: {
                    Label(String(localized: "批注测量"), systemImage: "doc.text")
                }
                .disabled(!snapshot.hasOverlayContent)
            } label: {
                Label(String(localized: "导出"), systemImage: "square.and.arrow.up.on.square")
            }
            Divider()
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label(String(localized: "清空覆盖层"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    func cadIconButton(
        systemImage: String,
        label: String,
        chrome: CADCommandBarChrome,
        active: Bool = false,
        destructive: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        switch chrome {
        case .standard:
            Button(role: destructive ? .destructive : nil, action: action) {
                Image(systemName: systemImage)
                    .visibleIconStyle()
                    .foregroundStyle(active ? Color.appRisk : Color.primary)
            }
            .disabled(disabled)
            .accessibilityLabel(label)
        case .immersive:
            floatingCircleButton(
                systemImage: systemImage,
                label: label,
                active: active,
                disabled: disabled,
                action: action
            )
        }
    }

    @ViewBuilder
    func cadCommandButton(
        systemImage: String,
        label: String,
        active: Bool,
        chrome: CADCommandBarChrome,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        switch chrome {
        case .standard:
            Button(action: action) {
                Label(label, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(active ? .appPrimaryAction : .secondary)
            .disabled(disabled)
            .opacity(disabled ? 0.45 : 1)
        case .immersive:
            floatingCircleButton(
                systemImage: systemImage,
                label: label,
                active: active,
                disabled: disabled,
                action: action
            )
        }
    }

    func cadCommandMenuLabel(
        systemImage: String,
        label: String,
        active: Bool,
        chrome: CADCommandBarChrome
    ) -> some View {
        floatingCircleMenuLabel(
            systemImage: systemImage,
            label: label,
            active: active,
            chrome: chrome
        )
    }

    func floatingCircleMenuLabel(
        systemImage: String,
        label: String,
        active: Bool,
        chrome: CADCommandBarChrome = .immersive
    ) -> some View {
        Group {
            switch chrome {
            case .standard:
                Label(label, systemImage: systemImage)
                    .font(.caption.weight(.semibold))
            case .immersive:
                Image(systemName: systemImage)
                    .font(.headline)
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
                    .foregroundStyle(active ? Color.white : Color.appPrimaryAction)
                    .background {
                        Circle().fill(active ? AnyShapeStyle(Color.appPrimaryAction) : AnyShapeStyle(.regularMaterial))
                    }
            }
        }
        .accessibilityLabel(label)
    }

    var immersiveOverlayControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(tool.guidance, systemImage: tool.icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tool == .browse ? .secondary : Color.appPrimaryAction)
                .lineLimit(2)

            ScrollView(.horizontal, showsIndicators: false) {
                bottomControlBarContent
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 0.8)
        )
    }
}
