import SwiftUI
#if os(iOS)
import UIKit
#endif

struct CADCanvasHost<Renderer: View, Overlay: View, ImmersiveOverlay: View, ImmersiveTop: View>: View {
    let isImmersivePreview: Bool
    let allowsOverlayEditing: Bool
    let overlayHitTestingEnabled: Bool
    let immersiveTopSafePadding: CGFloat
    let immersiveBottomSafePadding: CGFloat
    @ViewBuilder let renderer: () -> Renderer
    @ViewBuilder let overlayLayer: (CGSize) -> Overlay
    @ViewBuilder let immersiveOverlayControls: () -> ImmersiveOverlay
    @ViewBuilder let immersiveTopControls: () -> ImmersiveTop

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                renderer()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if allowsOverlayEditing {
                    overlayLayer(geo.size)
                        .allowsHitTesting(overlayHitTestingEnabled)
                        .zIndex(1)
                }
                if allowsOverlayEditing && isImmersivePreview {
                    immersiveOverlayControls()
                        .padding(.horizontal, 12)
                        .padding(.bottom, immersiveBottomSafePadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .zIndex(2)
                }
                if isImmersivePreview {
                    immersiveTopControls()
                        .padding(.horizontal, 12)
                        .padding(.top, immersiveTopSafePadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .zIndex(3)
                }
            }
            .background(Color.black.opacity(0.02))
        }
    }
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
            HStack(spacing: 8) {
                floatingCircleButton(systemImage: "xmark", label: String(localized: "完成")) {
                    dismiss()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeRequest.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    HStack(spacing: 5) {
                        Image(systemName: engineStatusIcon)
                            .font(.caption2)
                            .foregroundStyle(engineStatusTint)
                        Text(engineStatusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if allowsOverlayEditing {
                            Text("· \(unitHint)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    floatingCircleButton(
                        systemImage: "hand.tap",
                        label: String(localized: "看图"),
                        active: tool == .browse
                    ) {
                        selectOverlayTool(.browse)
                    }

                    if allowsOverlayEditing {
                        floatingCircleButton(
                            systemImage: "square.3.layers.3d",
                            label: String(localized: "图层"),
                            active: showOverlayLayerSheet
                        ) {
                            showOverlayLayerSheet = true
                        }

                        floatingCircleButton(
                            systemImage: "magnifyingglass",
                            label: String(localized: "搜索")
                        ) {
                            showDrawingTreeSheet = true
                        }

                        Menu {
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
                            Divider()
                            Button {
                                openScaleCalibrationSheet()
                            } label: {
                                Label(String(localized: "测量标定"), systemImage: "slider.horizontal.3")
                            }
                        } label: {
                            floatingCircleMenuLabel(
                                systemImage: "ruler",
                                label: String(localized: "测量"),
                                active: tool == .length || tool == .continuousLength || tool == .area
                            )
                        }
                        .disabled(!canCaptureDrawingOverlay)
                        .opacity(canCaptureDrawingOverlay ? 1 : 0.45)

                        Menu {
                            Button {
                                selectOverlayTool(.annotation)
                            } label: {
                                Label(String(localized: "批注"), systemImage: "highlighter")
                            }
                            Button {
                                selectOverlayTool(.redline)
                            } label: {
                                Label(String(localized: "红线"), systemImage: "scribble")
                            }
                            Button {
                                selectOverlayTool(.note)
                            } label: {
                                Label(String(localized: "文字批注"), systemImage: "text.bubble")
                            }
                        } label: {
                            floatingCircleMenuLabel(
                                systemImage: "highlighter",
                                label: String(localized: "批注"),
                                active: tool == .annotation || tool == .redline || tool == .note
                            )
                        }
                        .disabled(!canCaptureDrawingOverlay)
                        .opacity(canCaptureDrawingOverlay ? 1 : 0.45)

                        floatingCircleButton(
                            systemImage: "number.circle",
                            label: String(localized: "数数"),
                            active: tool == .count,
                            disabled: !canCaptureDrawingOverlay
                        ) {
                            selectOverlayTool(.count)
                        }

                        floatingCircleButton(
                            systemImage: "sum",
                            label: String(localized: "算量"),
                            active: showQuantitySheet
                        ) {
                            showQuantitySheet = true
                        }
                    }

                    Menu {
                        Button {
                            showShareSheet = true
                        } label: {
                            Label(String(localized: "分享图纸"), systemImage: "square.and.arrow.up")
                        }
                        if hasMultipleProjectDrawings {
                            Button {
                                showDrawingTreeSheet = true
                            } label: {
                                Label(String(localized: "图纸包目录树"), systemImage: "list.bullet.indent")
                            }
                        }
                        if shouldUseLibreDWGRenderer {
                            Button {
                                showTextEncodingDialog = true
                            } label: {
                                Label(String(localized: "文字编码与字体"), systemImage: "character.textbox")
                            }
                        }
                        if allowsOverlayEditing {
                            Button {
                                showAnnotationExportFormatDialog = true
                            } label: {
                                Label(String(localized: "导出批注测量"), systemImage: "doc.text")
                            }
                            .disabled(!snapshot.hasOverlayContent)
                        }
                        if isCADFile {
                            Button {
                                Task {
                                    await exportDiagnosticLog()
                                }
                            } label: {
                                Label(String(localized: "导出 CAD 诊断日志"), systemImage: isExportingDiagnosticLog ? "hourglass" : "doc.text.magnifyingglass")
                            }
                            .disabled(isExportingDiagnosticLog)
                        }
                        Divider()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isImmersivePreview = false
                            }
                        } label: {
                            Label(String(localized: "退出全屏"), systemImage: "arrow.down.right.and.arrow.up.left")
                        }
                        if allowsOverlayEditing {
                            Button(role: .destructive) {
                                showResetConfirm = true
                            } label: {
                                Label(String(localized: "清空覆盖层"), systemImage: "trash")
                            }
                        }
                    } label: {
                        floatingCircleMenuLabel(
                            systemImage: "ellipsis",
                            label: String(localized: "更多"),
                            active: false
                        )
                    }
                }
                .padding(2)
            }
        }
    }

    @ViewBuilder
    func topToolButton(for candidate: CADOverlayTool) -> some View {
        let labelTitle = candidate.title
        let labelIcon = candidate.icon
        Button {
            selectOverlayTool(candidate)
        } label: {
            Label(labelTitle, systemImage: labelIcon)
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(tool == candidate ? .appPrimaryAction : .secondary)
        .disabled(!isOverlayToolEnabled(candidate))
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

    func floatingCircleMenuLabel(
        systemImage: String,
        label: String,
        active: Bool
    ) -> some View {
        Image(systemName: systemImage)
            .font(.headline)
            .frame(width: 38, height: 38)
            .contentShape(Circle())
            .foregroundStyle(active ? Color.white : Color.appPrimaryAction)
            .background {
                Circle().fill(active ? AnyShapeStyle(Color.appPrimaryAction) : AnyShapeStyle(.regularMaterial))
            }
            .accessibilityLabel(label)
    }

    var immersiveOverlayControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasMultipleProjectDrawings {
                drawingTabStrip
            }

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
