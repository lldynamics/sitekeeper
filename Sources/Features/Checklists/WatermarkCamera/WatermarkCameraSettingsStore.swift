import Foundation
import Observation

@Observable
final class WatermarkCameraSettingsStore {
    static let managedPreferenceKeys: [String] = [
        UserPreferenceKeys.watermarkCameraSelectedProjectId,
        UserPreferenceKeys.watermarkCameraProjectName,
        UserPreferenceKeys.watermarkCameraPhotographer,
        UserPreferenceKeys.watermarkCameraLocationText,
        UserPreferenceKeys.watermarkCameraTemplateRaw,
        UserPreferenceKeys.watermarkCameraTag,
        UserPreferenceKeys.watermarkCameraAutoSaveToAlbum,
        UserPreferenceKeys.watermarkCameraAutoOpenLogDraft,
        UserPreferenceKeys.watermarkCameraExportQualityRaw,
        UserPreferenceKeys.watermarkCameraShowGrid,
        UserPreferenceKeys.watermarkCameraFlashEnabled,
        UserPreferenceKeys.watermarkCameraBurstCount
    ]

    private static let defaultTemplateRaw = CameraWatermarkTemplate.constructionLog.rawValue
    private static let defaultExportQualityRaw = WatermarkExportQuality.standard.rawValue
    private static let defaultAutoSaveToAlbum = true
    private static let defaultAutoOpenLogDraft = false
    private static let defaultShowGrid = true
    private static let defaultFlashEnabled = false
    private static let minBurstCount = 1
    private static let maxBurstCount = 5

    private static var defaultTag: String {
        AppLocalization.string("wm_camera_default_tag")
    }

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

        selectedProjectIdRaw = Self.normalizedSelectedProjectIdRaw(
            preferences.string(UserPreferenceKeys.watermarkCameraSelectedProjectId)
        )
        projectName = preferences.string(UserPreferenceKeys.watermarkCameraProjectName)
        photographer = preferences.string(UserPreferenceKeys.watermarkCameraPhotographer)
        locationText = preferences.string(UserPreferenceKeys.watermarkCameraLocationText)
        templateRaw = Self.normalizedTemplateRaw(
            preferences.string(
                UserPreferenceKeys.watermarkCameraTemplateRaw,
                default: Self.defaultTemplateRaw
            )
        )
        tag = Self.normalizedTag(
            preferences.string(
                UserPreferenceKeys.watermarkCameraTag,
                default: Self.defaultTag
            )
        )
        autoSaveToAlbum = preferences.bool(
            UserPreferenceKeys.watermarkCameraAutoSaveToAlbum,
            default: Self.defaultAutoSaveToAlbum
        )
        autoOpenLogDraft = preferences.bool(
            UserPreferenceKeys.watermarkCameraAutoOpenLogDraft,
            default: Self.defaultAutoOpenLogDraft
        )
        exportQualityRaw = Self.normalizedExportQualityRaw(
            preferences.string(
                UserPreferenceKeys.watermarkCameraExportQualityRaw,
                default: Self.defaultExportQualityRaw
            )
        )
        showGrid = preferences.bool(
            UserPreferenceKeys.watermarkCameraShowGrid,
            default: Self.defaultShowGrid
        )
        flashEnabled = preferences.bool(
            UserPreferenceKeys.watermarkCameraFlashEnabled,
            default: Self.defaultFlashEnabled
        )
        burstCount = Self.normalizedBurstCount(
            preferences.int(UserPreferenceKeys.watermarkCameraBurstCount, default: Self.minBurstCount)
        )
        persistCurrentSettings()
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
        Self.normalizedBurstCount(burstCount)
    }

    func normalizeBurstCount() {
        burstCount = boundedBurstCount
    }

    private func persistCurrentSettings() {
        preferences.set(selectedProjectIdRaw, for: UserPreferenceKeys.watermarkCameraSelectedProjectId)
        preferences.set(projectName, for: UserPreferenceKeys.watermarkCameraProjectName)
        preferences.set(photographer, for: UserPreferenceKeys.watermarkCameraPhotographer)
        preferences.set(locationText, for: UserPreferenceKeys.watermarkCameraLocationText)
        preferences.set(templateRaw, for: UserPreferenceKeys.watermarkCameraTemplateRaw)
        preferences.set(tag, for: UserPreferenceKeys.watermarkCameraTag)
        preferences.set(autoSaveToAlbum, for: UserPreferenceKeys.watermarkCameraAutoSaveToAlbum)
        preferences.set(autoOpenLogDraft, for: UserPreferenceKeys.watermarkCameraAutoOpenLogDraft)
        preferences.set(exportQualityRaw, for: UserPreferenceKeys.watermarkCameraExportQualityRaw)
        preferences.set(showGrid, for: UserPreferenceKeys.watermarkCameraShowGrid)
        preferences.set(flashEnabled, for: UserPreferenceKeys.watermarkCameraFlashEnabled)
        preferences.set(burstCount, for: UserPreferenceKeys.watermarkCameraBurstCount)
    }

    private static func normalizedSelectedProjectIdRaw(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let projectID = UUID(uuidString: trimmed) else { return "" }
        return projectID.uuidString
    }

    private static func normalizedTemplateRaw(_ raw: String) -> String {
        CameraWatermarkTemplate(rawValue: raw) == nil ? defaultTemplateRaw : raw
    }

    private static func normalizedExportQualityRaw(_ raw: String) -> String {
        WatermarkExportQuality(rawValue: raw) == nil ? defaultExportQualityRaw : raw
    }

    private static func normalizedTag(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultTag : trimmed
    }

    private static func normalizedBurstCount(_ value: Int) -> Int {
        min(maxBurstCount, max(minBurstCount, value))
    }
}
