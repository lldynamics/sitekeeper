import SwiftUI
#if os(iOS)
import UIKit
#endif

extension CADPreviewContainer {
    var isCADFile: Bool {
        CADDrawingCapability.isCADFile(extension: activeRequest.fileType)
    }

    var isDWGFile: Bool {
        let declaredType = activeRequest.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pathExtension = activeRequest.fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return declaredType == "dwg" || pathExtension == "dwg"
    }

    var selectedCADViewerMode: CADViewerMode {
        CADViewerMode(rawValue: cadViewerModeRaw) ?? .auto
    }

    var shouldUseFallbackViewer: Bool {
        false
    }

    private var shouldShowCADKernelUnavailable: Bool {
        isCADFile && !CADRendererProvider.isRendererBound
    }

    private var shouldShowCADKernelUnbound: Bool {
        isCADFile && !CADRendererProvider.isRendererBound
    }

    var shouldUseCADKernelRenderer: Bool {
        guard !isDWGFile else { return false }
        return Self.shouldEnterInteractiveCADCanvas(
            isCADFile: isCADFile,
            rendererBound: CADRendererProvider.isRendererBound,
            route: cadOpenRoute
        )
    }

    var canUseCADTextRepair: Bool {
        isCADFile && (isDWGFile || shouldUseCADKernelRenderer)
    }

    var allowsOverlayEditing: Bool {
        if isDWGFile {
            return true
        }
        guard isCADFile else { return true }
        if case .rendered = cadOpenRoute {
            return true
        }
        return false
    }

    private var shouldUseCADOverlayHost: Bool {
        isCADFile && (isDWGFile || shouldUseCADKernelRenderer)
    }

    var unsupportedKernelMessage: String {
        switch cadOpenRoute {
        case .unsupported(let result):
            return result.message
        case .rendered(let result):
            return result.message.isEmpty ? CADViewerMessages.interactivePreviewUnavailableMessage : result.message
        }
    }

    static func shouldEnterInteractiveCADCanvas(
        isCADFile: Bool,
        rendererBound: Bool,
        route: CADOpenRoute
    ) -> Bool {
        guard isCADFile, rendererBound else { return false }
        if case .rendered = route {
            return true
        }
        return false
    }

    var engineStatusHint: String? {
        nil
    }

    @MainActor
    private func refreshCADOpenRoute() async {
        guard isCADFile else { return }
        cadOpenQuality = nil
        lastRendererPerformance = nil
        forceFallbackForPerformance = false
        forceFallbackReason = nil
        cadOpenRoute = unsupportedOpenRoute(message: CADViewerMessages.interactivePreviewUnavailableMessage)
        cadOpenRoute = await CADOpenRouter.route(for: activeRequest.cadFile)
        cadPreviewReloadToken = UUID()
    }

    var cadOpenTechnicalDetails: CADOpenTechnicalDetails? {
        switch cadOpenRoute {
        case .rendered(let result), .unsupported(let result):
            return result.technicalDetails
        }
    }

    var body: some View {
        applyPresentationModifiers(
            to: Group {
                if !shouldUseCADOverlayHost {
                    previewContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    CADCanvasHost(
                        isImmersivePreview: isImmersivePreview,
                        allowsOverlayEditing: allowsOverlayEditing,
                        overlayHitTestingEnabled: overlayHitTestingEnabled,
                        immersiveTopSafePadding: immersiveTopSafePadding,
                        immersiveBottomSafePadding: immersiveBottomSafePadding
                    ) {
                        previewContent
                    } overlayLayer: { size in
                        overlayLayer(size: size)
                    } immersiveOverlayControls: {
                        immersiveOverlayControls
                    } immersiveTopControls: {
                        immersiveTopControls
                    }
                    .ignoresSafeArea(.container, edges: isImmersivePreview ? .all : [])
                    .statusBarHidden(isImmersivePreview)
                    .safeAreaInset(edge: .top) {
                        if !isImmersivePreview {
                            standardTopBar
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        if allowsOverlayEditing && !isImmersivePreview {
                            bottomControlBar
                        }
                    }
                }
            }
            .onAppear {
                prepareForCurrentRequest()
                Task { @MainActor in
                    await bootstrapCADOpenRoute()
                }
            }
            .task(id: snapshot) {
                await debouncePersistSnapshot(snapshot)
            }
            .onChange(of: selectedStrokeLayer) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: selectedAnnotationColorHex) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: selectedMeasurementColorHex) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: selectedNoteColorHex) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: hiddenOverlayGroups) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: hiddenStrokeLayers) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: hiddenOverlayColorHexes) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: enabledSnapModes) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onDisappear {
                saveCurrentViewState()
                persistSnapshotIfNeeded(snapshot)
            }
        )
    }

    private func prepareForCurrentRequest() {
        migrateCADPoCFeatureDefaultsIfNeeded()
        snapshot = restoredSnapshot(for: activeRequest)
        snapshot.normalizeMeasurementScale()
        applyOverlayDisplayPreferences(from: snapshot)
        if !countCategoryOptions.contains(selectedCountCategory) {
            selectedCountCategory = countCategoryOptions.first ?? String(localized: "点位")
        }
        lastPersistedSnapshotData = encodedSnapshotData(snapshot)
        overlayUndoStack.removeAll()
        overlayRedoStack.removeAll()
        isDeletingOverlayItem = false
        selectedTextEncoding = activeRequest.textEncoding
        selectedTextBigFont = activeRequest.textBigFont
        textSchemeSnapshot = activeRequest.textSchemeSnapshot
        currentCADViewState = activeRequest.cadViewState
        lastPersistedCADViewState = activeRequest.cadViewState
        nativeCADLayers = []
        nativeCADLayouts = []
        nativeCADCurrentLayoutID = nil
        let savedCADLayerIDs = Set(activeRequest.cadViewState.visibleLayerNames)
        nativeCADVisibleLayerIDs = activeRequest.cadViewState.usesSavedVisibleLayers && !savedCADLayerIDs.isEmpty
            ? savedCADLayerIDs
            : nil
        lastRendererPerformance = nil
        lastCADOpenTrace = nil
        forceFallbackForPerformance = false
        forceFallbackReason = nil
        if isCADFile, !isDWGFile, CADRendererProvider.isRendererBound {
            cadOpenRoute = unsupportedOpenRoute(message: CADViewerMessages.interactivePreviewUnavailableMessage)
        }
    }

    @MainActor
    private func bootstrapCADOpenRoute() async {
        if isDWGFile {
            cadOpenRoute = unsupportedOpenRoute(message: CADViewerMessages.interactivePreviewUnavailableMessage)
        } else if isCADFile {
            await refreshCADOpenRoute()
        } else {
            cadOpenRoute = unsupportedOpenRoute(message: CADOpenRouter.unsupportedOpenMessage)
        }
    }

    private func unsupportedOpenRoute(message: String) -> CADOpenRoute {
        .unsupported(
            CADOpenResult(
                drawingId: activeRequest.drawingID,
                openState: .unsupported,
                message: message,
                technicalDetails: nil
            )
        )
    }
}
