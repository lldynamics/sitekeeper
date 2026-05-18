import SwiftUI
#if os(iOS)
import UIKit
#endif
struct CADPreviewContainer: View {
    let request: ProjectCADPreviewRequest
    @Environment(\.dismiss) var dismiss
    @Environment(DataStore.self) var store

    @State var activeRequest: ProjectCADPreviewRequest
    @State var tool: CADOverlayTool = .browse
    @State var snapshot = CADOverlaySnapshot()
    @State var activeStrokePoints: [CGPoint] = []
    @State var pendingLengthPoints: [CGPoint] = []
    @State var pendingAreaPoints: [CGPoint] = []
    @State var activeDragLengthPoints: [CGPoint] = []
    @State var activeDragArrowPoints: [CGPoint] = []
    @State var showQuantitySheet = false
    @State var showResetConfirm = false
    @State var showScaleSheet = false
    @State var showOverlayLayerSheet = false
    @State var showAnnotationExportFormatDialog = false
    @State var showTextEncodingDialog = false
    @State var scaleDraft = ""
    @State var calibrationActualMetersDraft = ""
    @State var selectedCalibrationMeasurementID: UUID?
    @State var newOverlayLayerName = ""
    @State var customOverlayColor = Color(red: 0.89, green: 0.29, blue: 0.48)
    @State var pendingNotePoint: CGPoint?
    @State var noteDraft = ""
    @State var showNoteSheet = false
    @State var pendingIssueMarkerPoint: CGPoint?
    @State var showIssuePhotoCamera = false
    @State var selectedCountCategory = String(localized: "点位")
    @State var lastPersistedSnapshotData = ""
    @State var isImmersivePreview = false
    @State var selectedTextEncoding: CADDrawingTextEncoding
    @State var selectedTextBigFont: CADDrawingTextBigFont
    @State var textSchemeSnapshot: CADDrawingTextSchemeSnapshot
    @State var cadOpenQuality: CADOpenQualitySnapshot?
    @State var projectFontMappingBigFont: CADDrawingTextBigFont = .gbcbig
    @State var showCADDisplayFontImporter = false
    @State var currentCADViewState: CADDrawingViewState
    @State var lastPersistedCADViewState: CADDrawingViewState
    @State var isApplyingTextPreset = false
    @State var selectedStrokeLayer = String(localized: "现场批注")
    @State var selectedAnnotationColorHex = "2F80ED"
    @State var selectedMeasurementColorHex = "2F80ED"
    @State var selectedNoteColorHex = "F2994A"
    @State var hiddenOverlayGroups: Set<CADOverlayVisibilityGroup> = []
    @State var hiddenStrokeLayers: Set<String> = []
    @State var hiddenOverlayColorHexes: Set<String> = []
    @State var isSelectingStroke = false
    @State var isDeletingOverlayItem = false
    @State var selectedStrokeID: UUID?
    @State var overlayUndoStack: [CADOverlaySnapshot] = []
    @State var overlayRedoStack: [CADOverlaySnapshot] = []
    @State var isAutoDetectingText = false
    @State var isExportingDiagnosticLog = false
    @State var diagnosticExportPayload: ExportPayload?
    @State var annotationExportPayload: ExportPayload?
    @State var fallbackScreenshotPayload: ExportPayload?
    @State var quantityHighlightTarget: CADQuantityHighlightTarget?
    @State var nativeCanvasTransform: CADNativeCanvasTransform?
    @State var nativeSnapPoints: [CGPoint] = []
    @State var nativeEndpointSnapPoints: [CGPoint] = []
    @State var nativeMidpointSnapPoints: [CGPoint] = []
    @State var nativeCenterSnapPoints: [CGPoint] = []
    @State var nativeSnapSourcePoints: [CADNativeSnapSourcePoint] = []
    @State var nativeSnapPointBuckets = CADNativeSnapPointBuckets()
    @State var nativeCADLayouts: [CADPoC.CADLayout] = []
    @State var nativeCADCurrentLayoutID: String?
    @State var nativeCADLayers: [CADPoC.CADLayer] = []
    @State var nativeCADVisibleLayerIDs: Set<String>?
    @State var enabledSnapModes: Set<CADSnapMode> = Set(CADSnapMode.allCases)
    @State var cadPreviewReloadToken = UUID()
    @State var lastRendererPerformance: CADRendererPerformanceSnapshot?
    @State var lastCADOpenTrace: CADPoC.CADOpenTrace?
    @State var forceFallbackForPerformance = false
    @State var forceFallbackReason: String?
    @State var alertMessage = ""
    @State var showAlert = false
    @State var showShareSheet = false
    @State var cadOpenRoute: CADOpenRoute = .unsupported(
        CADOpenResult(
            drawingId: UUID(),
            openState: .unsupported,
            message: CADViewerMessages.interactivePreviewUnavailableMessage,
            technicalDetails: nil
        )
    )
    @AppStorage("cadViewerMode") var cadViewerModeRaw = CADViewerMode.auto.rawValue
    @AppStorage("cad.metal.poc.showsOverviewMap") var showsCADOverviewMap = false
    @AppStorage("cad.metal.poc.rendersTextOverlays") var rendersCADTextOverlays = true
    @AppStorage("cad.metal.poc.rendersLineTypes") var rendersCADLineTypes = false
    @AppStorage("cad.metal.poc.rendersLineWeights") var rendersCADLineWeights = false
    @AppStorage("cad.metal.poc.rendersDimensionDetails") var rendersCADDimensionDetails = false
    @AppStorage("cad.metal.poc.buildsTextSearchIndex") var buildsCADTextSearchIndex = false
    @AppStorage("cad.metal.poc.publishesSnapPoints") var publishesCADSnapPoints = false
    @AppStorage("cad.metal.poc.publishesSnapIntersections") var publishesCADSnapIntersections = false
    @AppStorage("cad.metal.poc.rendersHatchBoundaries") var rendersCADHatchBoundaries = false
    @AppStorage("cad.metal.poc.rendersHatches") var rendersCADHatches = false
    @AppStorage("cad.metal.poc.rendersPlaceholders") var rendersCADPlaceholders = false
    @AppStorage("cad.metal.poc.showsRendererDiagnostics") var showsCADRendererDiagnostics = false
    @AppStorage("cad.metal.poc.featureDefaultsVersion") var cadFeatureDefaultsVersion = 0
    @AppStorage("cad.metal.poc.textDisplayFont") var cadTextDisplayFontRaw = CADDrawingTextDisplayFont.auto.rawValue
    @AppStorage("cad.metal.poc.importedTextFontName") var cadImportedTextFontName = ""
    @AppStorage("cad.metal.poc.importedTextFontPath") var cadImportedTextFontPath = ""
    let overlaySnapTolerance: CGFloat = 14
    let activeStrokeSamplingCanvasDistance: CGFloat = 3
    let activeStrokePointLimit = 4096
    let overlayUndoLimit = 40

    init(request: ProjectCADPreviewRequest) {
        self.request = request
        _activeRequest = State(initialValue: request)
        _selectedTextEncoding = State(initialValue: request.textEncoding)
        _selectedTextBigFont = State(initialValue: request.textBigFont)
        _textSchemeSnapshot = State(initialValue: request.textSchemeSnapshot)
        _currentCADViewState = State(initialValue: request.cadViewState)
        _lastPersistedCADViewState = State(initialValue: request.cadViewState)
    }
}
