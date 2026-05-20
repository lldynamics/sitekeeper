import SwiftUI
#if os(iOS)
import UIKit
#endif

extension CADPreviewContainer {
    private var initialRendererViewState: CADRendererViewState? {
        guard activeRequest.cadViewState.hasSavedViewport else { return nil }
        let state = activeRequest.cadViewState
        let viewportCenter: CGPoint?
        if let x = state.viewportCenterX, let y = state.viewportCenterY {
            viewportCenter = CGPoint(x: CGFloat(x), y: CGFloat(y))
        } else {
            viewportCenter = nil
        }
        return CADRendererViewState(
            zoomScale: CGFloat(state.zoomScale),
            panOffset: CGSize(width: CGFloat(state.panOffsetX), height: CGFloat(state.panOffsetY)),
            viewportCenter: viewportCenter,
            usesSavedVisibleLayers: state.usesSavedVisibleLayers,
            visibleLayerNames: state.visibleLayerNames
        )
    }

    private var rendererCallbacks: CADRendererCallbacks {
        let expectedFilePath = activeRequest.fileURL.path
        return CADRendererCallbacks(
            onCanvasTransformChange: { transform in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    handleRendererCanvasTransform(transform)
                }
            },
            onViewStateChange: { viewState in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    handleRendererViewState(viewState)
                }
            },
            onTextRepairPresetRequest: { codePage, bigFont in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    handleRendererTextRepairPresetRequest(codePage: codePage, bigFont: bigFont)
                }
            },
            onSnapPointsChange: { points in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    handleRendererSnapPoints(points)
                }
            },
            onTextAutoDetectionChange: { result in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    handleRendererTextAutoDetection(result)
                }
            },
            onOpenQualityChange: { quality in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    cadOpenQuality = quality
                }
            },
            onOpenTraceChange: { trace in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    lastCADOpenTrace = trace
                }
            },
            onPerformanceSample: { sample in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    handleRendererPerformanceSample(sample)
                }
            },
            onFallbackRecommendation: { reason in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    handleRendererFallbackRecommendation(reason)
                }
            }
        )
    }

    var previewContent: AnyView {
        if isCADFile {
            if isDWGFile {
                return AnyView(
                    CADViewerRoute(
                        request: activeRequest,
                        showsToolbar: false,
                        initialViewState: initialRendererViewState,
                        callbacks: rendererCallbacks,
                        selectedLayoutID: nativeCADCurrentLayoutID,
                        visibleLayerIDs: nativeCADVisibleLayerIDs,
                        onLayoutsChanged: { layouts in
                            nativeCADLayouts = layouts
                            let nextLayoutID = NativeCADViewerEntry.defaultLayoutID(layouts)
                            if let current = nativeCADCurrentLayoutID,
                               layouts.contains(where: { $0.id == current }) {
                                return
                            }
                            nativeCADCurrentLayoutID = nextLayoutID
                        },
                        onSelectedLayoutIDChanged: { layoutID in
                            nativeCADCurrentLayoutID = layoutID
                        },
                        onLayersChanged: { layers in
                            nativeCADLayers = layers
                        },
                        onVisibleLayerIDsChanged: { layerIDs in
                            nativeCADVisibleLayerIDs = layerIDs
                        },
                        onClose: {
                            dismiss()
                        },
                        onReportIssue: {
                            Task { @MainActor in
                                await exportDiagnosticLog()
                            }
                        }
                    )
                )
            }
            if shouldUseCADKernelRenderer,
               let renderer = CADRendererProvider.renderer(
                for: activeRequest.fileURL,
                preferredTextCodePage: activeRequest.preferredTextCodePage,
                preferredTextBigFont: activeRequest.preferredTextBigFontCode,
                initialViewState: cadKernelInitialViewState,
                fontMappings: activeRequest.rendererFontMappings,
                callbacks: rendererCallbacks
               ) {
                return renderer
            }
            return AnyView(
                CADKernelUnavailableView(
                    fileURL: activeRequest.fileURL,
                    message: unsupportedKernelMessage,
                    technicalDetails: cadOpenTechnicalDetails,
                    onReportIssue: {
                        Task { @MainActor in
                            await exportDiagnosticLog()
                        }
                    }
                )
            )
        }
        return AnyView(AppQuickLookPreviewController(url: activeRequest.fileURL))
    }

    private var cadKernelInitialViewState: CADRendererViewState {
        CADRendererViewState(
            zoomScale: CGFloat(currentCADViewState.zoomScale),
            panOffset: CGSize(
                width: currentCADViewState.panOffsetX,
                height: currentCADViewState.panOffsetY
            ),
            viewportCenter: cadKernelViewportCenter,
            usesSavedVisibleLayers: currentCADViewState.usesSavedVisibleLayers,
            visibleLayerNames: currentCADViewState.visibleLayerNames
        )
    }

    private var cadKernelViewportCenter: CGPoint? {
        guard let x = currentCADViewState.viewportCenterX,
              let y = currentCADViewState.viewportCenterY else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    @MainActor
    private func handleRendererCanvasTransform(_ rendererTransform: CADRendererCanvasTransform) {
        let transform = CADNativeCanvasTransform(rendererTransform)
        nativeCanvasTransform = transform
        if snapshot.coordinateSpace == .canvas {
            snapshot.convertCanvasPointsToDrawingCoordinates(using: transform)
        }
    }

    @MainActor
    private func handleRendererViewState(_ rendererViewState: CADRendererViewState) {
        let layerNames = Array(Set(rendererViewState.visibleLayerNames))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let next = CADDrawingViewState(
            zoomScale: Double(rendererViewState.zoomScale),
            panOffsetX: Double(rendererViewState.panOffset.width),
            panOffsetY: Double(rendererViewState.panOffset.height),
            viewportCenterX: rendererViewState.viewportCenter.map { Double($0.x) },
            viewportCenterY: rendererViewState.viewportCenter.map { Double($0.y) },
            usesSavedVisibleLayers: rendererViewState.usesSavedVisibleLayers,
            visibleLayerNames: layerNames
        )
        currentCADViewState = next
        persistCADViewStateIfNeeded(next)
    }

    func saveCurrentViewState(showConfirmation: Bool = false) {
        persistCADViewStateIfNeeded(currentCADViewState, force: true)
        activeRequest.onTextEncodingChange(activeRequest.drawingID, selectedTextEncoding)
        activeRequest.onTextBigFontChange(activeRequest.drawingID, selectedTextBigFont)
        activeRequest.onTextSchemeSnapshotChange(activeRequest.drawingID, textSchemeSnapshot)
        if showConfirmation {
            alertMessage = String(localized: "已保存当前缩放、位置、图层显示和文字编码。")
            showAlert = true
        }
    }

    private func setCADViewerMode(_ mode: CADViewerMode) {
        guard selectedCADViewerMode != mode || forceFallbackForPerformance else { return }
        cadViewerModeRaw = mode.rawValue
        forceFallbackForPerformance = false
        forceFallbackReason = nil
        lastRendererPerformance = nil
        cadOpenQuality = nil
        nativeCanvasTransform = nil
        nativeSnapPoints.removeAll()
        nativeEndpointSnapPoints.removeAll()
        nativeMidpointSnapPoints.removeAll()
        nativeCenterSnapPoints.removeAll()
        nativeSnapSourcePoints.removeAll()
        nativeSnapPointBuckets = CADNativeSnapPointBuckets()
        clearInProgress()
        cadPreviewReloadToken = UUID()
        AppHaptics.impact(.light, intensity: 0.55)
    }

    func migrateNativeCADFeatureDefaultsIfNeeded() {
        guard cadFeatureDefaultsVersion < 2 else { return }
        if cadFeatureDefaultsVersion < 1 {
            rendersCADTextOverlays = true
        }
        rendersCADHatchBoundaries = false
        publishesCADSnapIntersections = publishesCADSnapPoints && publishesCADSnapIntersections
        cadFeatureDefaultsVersion = 2
    }

    private func persistCADViewStateIfNeeded(_ viewState: CADDrawingViewState, force: Bool = false) {
        guard force || viewState != lastPersistedCADViewState else { return }
        lastPersistedCADViewState = viewState
        activeRequest.onViewStateChange(activeRequest.drawingID, viewState)
        activeRequest = updatingActiveRequest(cadViewState: viewState)
    }

    @MainActor
    private func handleRendererTextRepairPresetRequest(codePage: Int32?, bigFont: Int32?) {
        let encoding = textEncoding(forCodePage: codePage) ?? .gbk936
        let profile = textBigFont(forBridgeCode: bigFont) ?? .gbcbig
        applyTextPreset(
            encoding: encoding,
            bigFont: profile,
            resetAutoDetectScore: true
        )
        alertMessage = String(
            format: String(localized: "已切换为 %@ / %@。"),
            encoding.displayName,
            profile.displayName
        )
        showAlert = true
    }

    @MainActor
    private func handleRendererSnapPoints(_ payloads: [CADRendererSnapPointPayload]) {
        let buckets = CADNativeSnapPointBuckets(sourcePoints: payloads.compactMap(CADNativeSnapSourcePoint.init))
        if buckets.sourcePoints.isEmpty {
            nativeSnapPoints.removeAll()
            nativeSnapSourcePoints.removeAll()
            nativeEndpointSnapPoints.removeAll()
            nativeMidpointSnapPoints.removeAll()
            nativeCenterSnapPoints.removeAll()
            nativeSnapPointBuckets = CADNativeSnapPointBuckets()
            return
        }

        applyNativeSnapPointBuckets(buckets)
    }

    @MainActor
    private func handleRendererPerformanceSample(_ sample: CADRendererPerformanceSnapshot) {
        lastRendererPerformance = sample
    }

    @MainActor
    private func handleRendererFallbackRecommendation(_ reason: String) {
        guard !forceFallbackForPerformance else { return }
        forceFallbackForPerformance = true
        forceFallbackReason = reason
        cadPreviewReloadToken = UUID()
        alertMessage = reason
        showAlert = true
    }

    @MainActor
    private func applyNativeSnapPointBuckets(_ buckets: CADNativeSnapPointBuckets) {
        nativeSnapSourcePoints = buckets.sourcePoints
        nativeSnapPoints = buckets.allPoints
        nativeEndpointSnapPoints = buckets.endpointPoints
        nativeMidpointSnapPoints = buckets.midpointPoints
        nativeCenterSnapPoints = buckets.centerPoints
        nativeSnapPointBuckets = buckets
    }

    @MainActor
    private func handleRendererTextAutoDetection(_ result: CADTextAutoDetectionResult) {
        let snapshot = CADDrawingTextSchemeSnapshot(
            codePage: result.codePage,
            bigFont: result.bigFont,
            styleName: result.styleName,
            fontFile: result.fontFile,
            bigFontFile: result.bigFontFile,
            autoDetectScore: result.autoDetectScore,
            styleSummary: result.styleSummary,
            matchedFontSummary: result.matchedFontSummary,
            unresolvedFontSummary: result.unresolvedFontSummary,
            fontResolutionSummary: result.fontResolutionSummary,
            rawTextBytesHexSample: result.rawTextBytesHexSample,
            detectionSummary: result.detectionSummary ?? result.summary
        )
        applyPreviewAutoDetectedTextOptions(snapshot: snapshot)
    }

    func fallbackNativeSnapPointBuckets() -> CADNativeSnapPointBuckets {
        var result: [CADNativeSnapSourcePoint] = []
        func append(_ point: CGPoint, kind: CADNativeSnapPointKind, primitiveKind: CADNativePrimitiveKind) {
            result.append(
                CADNativeSnapSourcePoint(
                    point: point,
                    snapKind: kind,
                    layer: "0",
                    primitiveKind: primitiveKind,
                    styleRGB: 0,
                    styleWidth: 1,
                    styleName: nil
                )
            )
        }
        nativeEndpointSnapPoints.forEach { append($0, kind: .endpoint, primitiveKind: .line) }
        nativeMidpointSnapPoints.forEach { append($0, kind: .midpoint, primitiveKind: .line) }
        nativeCenterSnapPoints.forEach { append($0, kind: .center, primitiveKind: .circle) }
        nativeSnapPointBuckets.intersectionPoints.forEach { append($0, kind: .intersection, primitiveKind: .line) }
        if result.isEmpty {
            nativeSnapPoints.forEach { append($0, kind: .endpoint, primitiveKind: .line) }
        }
        return CADNativeSnapPointBuckets(sourcePoints: result)
    }
}
