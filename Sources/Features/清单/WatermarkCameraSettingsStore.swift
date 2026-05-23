import Foundation
import Observation

@Observable
final class WatermarkCameraSettingsStore {
    @ObservationIgnored private let preferences: UserPreferencesStore

    var selectedProjectIdRaw: String {
        didSet { preferences.set(selectedProjectIdRaw, for: UserPreferenceKeys.watermarkCameraSelectedProjectId) }
    }
    var projectName: String {
        didSet { preferences.set(projectName, for: UserPreferenceKeys.watermarkCameraProjectName) }
    }
    var photographer: String {
        didSet { preferences.set(photographer, for: UserPreferenceKeys.watermarkCameraPhotographer) }
    }
    var locationText: String {
        didSet { preferences.set(locationText, for: UserPreferenceKeys.watermarkCameraLocationText) }
    }
    var templateRaw: String {
        didSet { preferences.set(templateRaw, for: UserPreferenceKeys.watermarkCameraTemplateRaw) }
    }
    var tag: String {
        didSet { preferences.set(tag, for: UserPreferenceKeys.watermarkCameraTag) }
    }
    var autoSaveToAlbum: Bool {
        didSet { preferences.set(autoSaveToAlbum, for: UserPreferenceKeys.watermarkCameraAutoSaveToAlbum) }
    }
    var autoOpenLogDraft: Bool {
        didSet { preferences.set(autoOpenLogDraft, for: UserPreferenceKeys.watermarkCameraAutoOpenLogDraft) }
    }
    var exportQualityRaw: String {
        didSet { preferences.set(exportQualityRaw, for: UserPreferenceKeys.watermarkCameraExportQualityRaw) }
    }
    var showGrid: Bool {
        didSet { preferences.set(showGrid, for: UserPreferenceKeys.watermarkCameraShowGrid) }
    }
    var flashEnabled: Bool {
        didSet { preferences.set(flashEnabled, for: UserPreferenceKeys.watermarkCameraFlashEnabled) }
    }
    var burstCount: Int {
        didSet { preferences.set(burstCount, for: UserPreferenceKeys.watermarkCameraBurstCount) }
    }

    init(preferences: UserPreferencesStore = .shared) {
        self.preferences = preferences
        selectedProjectIdRaw = preferences.string(UserPreferenceKeys.watermarkCameraSelectedProjectId)
        projectName = preferences.string(UserPreferenceKeys.watermarkCameraProjectName)
        photographer = preferences.string(UserPreferenceKeys.watermarkCameraPhotographer)
        locationText = preferences.string(UserPreferenceKeys.watermarkCameraLocationText)
        templateRaw = preferences.string(
            UserPreferenceKeys.watermarkCameraTemplateRaw,
            default: CameraWatermarkTemplate.constructionLog.rawValue
        )
        tag = preferences.string(
            UserPreferenceKeys.watermarkCameraTag,
            default: String(localized: "wm_camera_default_tag")
        )
        autoSaveToAlbum = preferences.bool(UserPreferenceKeys.watermarkCameraAutoSaveToAlbum, default: true)
        autoOpenLogDraft = preferences.bool(UserPreferenceKeys.watermarkCameraAutoOpenLogDraft, default: false)
        exportQualityRaw = preferences.string(
            UserPreferenceKeys.watermarkCameraExportQualityRaw,
            default: WatermarkExportQuality.standard.rawValue
        )
        showGrid = preferences.bool(UserPreferenceKeys.watermarkCameraShowGrid, default: true)
        flashEnabled = preferences.bool(UserPreferenceKeys.watermarkCameraFlashEnabled, default: false)
        burstCount = preferences.int(UserPreferenceKeys.watermarkCameraBurstCount, default: 1)
        normalizeBurstCount()
    }

    var selectedProjectId: UUID? {
        get { UUID(uuidString: selectedProjectIdRaw) }
        set { selectedProjectIdRaw = newValue?.uuidString ?? "" }
    }

    var template: CameraWatermarkTemplate {
        get { StringEnumFallback.value(templateRaw, default: CameraWatermarkTemplate.constructionLog) }
        set { templateRaw = newValue.rawValue }
    }

    var exportQuality: WatermarkExportQuality {
        get { StringEnumFallback.value(exportQualityRaw, default: WatermarkExportQuality.standard) }
        set { exportQualityRaw = newValue.rawValue }
    }

    var boundedBurstCount: Int {
        min(5, max(1, burstCount))
    }

    func normalizeBurstCount() {
        burstCount = boundedBurstCount
    }
}
