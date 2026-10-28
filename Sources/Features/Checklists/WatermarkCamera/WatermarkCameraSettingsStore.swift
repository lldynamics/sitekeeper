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
    ] + WatermarkCameraPreferenceKeys.all

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

    private struct ProjectDetails: Codable {
        var workSection: String
        var floor: String
        var process: String
    }
    @ObservationIgnored private var projectDetails: [String: ProjectDetails] = [:]
    @ObservationIgnored private var isLoadingProjectDetails = false
    private static func projectKey(_ raw: String) -> String { raw.isEmpty ? "unlinked" : raw }

    var selectedProjectIdRaw: String {
        didSet {
            guard oldValue != selectedProjectIdRaw else { return }
            saveProjectDetails(for: oldValue)
            preferences.set(selectedProjectIdRaw, for: UserPreferenceKeys.watermarkCameraSelectedProjectId)
            let details = projectDetails[Self.projectKey(selectedProjectIdRaw)]
            isLoadingProjectDetails = true
            workSection = details?.workSection ?? ""
            floor = details?.floor ?? ""
            process = details?.process ?? ""
            isLoadingProjectDetails = false
        }
    }
    var projectName: String {
        didSet { preferences.set(projectName, for: UserPreferenceKeys.watermarkCameraProjectName) }
    }
    var photographer: String {
        didSet { preferences.set(photographer, for: UserPreferenceKeys.watermarkCameraPhotographer) }
    }
    var locationText: String {
        didSet {
            preferences.set(locationText, for: UserPreferenceKeys.watermarkCameraLocationText)
            if !isApplyingDeviceLocation {
                locationWasRestored = false
                locationSnapshot = locationText.isEmpty ? nil : .manual(text: locationText)
            }
        }
    }
    @ObservationIgnored private var isApplyingDeviceLocation = false
    private var locationWasRestored = true
    var locationSnapshot: WatermarkLocationSnapshot? {
        didSet { persistLocationSnapshot() }
    }
    var workSection: String {
        didSet { persistProjectDetails() }
    }
    var floor: String {
        didSet { persistProjectDetails() }
    }
    var process: String {
        didSet { persistProjectDetails() }
    }
    var issueNumber: String {
        didSet { preferences.set(issueNumber, for: WatermarkCameraPreferenceKeys.issueNumber) }
    }
    var completedQuantity: String {
        didSet { preferences.set(completedQuantity, for: WatermarkCameraPreferenceKeys.completedQuantity) }
    }
    var receiptNote: String {
        didSet { preferences.set(receiptNote, for: WatermarkCameraPreferenceKeys.receiptNote) }
    }
    var style: WatermarkCameraStyle {
        didSet {
            preferences.set(style.position.rawValue, for: WatermarkCameraPreferenceKeys.stylePosition)
            preferences.set(style.detail.rawValue, for: WatermarkCameraPreferenceKeys.styleDetail)
        }
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
        let savedLocationText = preferences.string(UserPreferenceKeys.watermarkCameraLocationText)
        locationText = savedLocationText
        let savedLocation = preferences.data(WatermarkCameraPreferenceKeys.locationSnapshot)
            .flatMap { try? JSONDecoder().decode(WatermarkLocationSnapshot.self, from: $0) }
        locationSnapshot = savedLocation?.text == savedLocationText ? savedLocation
            : (savedLocationText.isEmpty ? nil : .manual(text: savedLocationText))
        workSection = preferences.string(WatermarkCameraPreferenceKeys.workSection)
        floor = preferences.string(WatermarkCameraPreferenceKeys.floor)
        process = preferences.string(WatermarkCameraPreferenceKeys.process)
        issueNumber = preferences.string(WatermarkCameraPreferenceKeys.issueNumber)
        completedQuantity = preferences.string(WatermarkCameraPreferenceKeys.completedQuantity)
        receiptNote = preferences.string(WatermarkCameraPreferenceKeys.receiptNote)
        style = WatermarkCameraStyle(
            position: WatermarkCameraStyle.Position(rawValue: preferences.string(WatermarkCameraPreferenceKeys.stylePosition)) ?? .bottomRight,
            detail: WatermarkCameraStyle.Detail(rawValue: preferences.string(WatermarkCameraPreferenceKeys.styleDetail)) ?? .full
        )
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
        projectDetails = preferences.data(WatermarkCameraPreferenceKeys.projectDetails)
            .flatMap { try? JSONDecoder().decode([String: ProjectDetails].self, from: $0) } ?? [:]
        let key = Self.projectKey(selectedProjectIdRaw)
        if let details = projectDetails[key] {
            workSection = details.workSection
            floor = details.floor
            process = details.process
        } else {
            // The old global values belong only to the project selected at migration.
            projectDetails[key] = ProjectDetails(workSection: workSection, floor: floor, process: process)
        }
        persistCurrentSettings()
        saveProjectDetails(for: selectedProjectIdRaw)
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

    func setManualLocation(_ text: String) {
        locationText = text
    }

    func acceptDeviceLocation(_ snapshot: WatermarkLocationSnapshot) {
        guard snapshot.provenance == .device, snapshot.freshness() != .invalid else { return }
        isApplyingDeviceLocation = true
        locationText = snapshot.text
        isApplyingDeviceLocation = false
        locationWasRestored = false
        locationSnapshot = snapshot
    }

    func locationStatusText(at now: Date = Date()) -> String {
        guard let snapshot = locationSnapshot, !locationText.isEmpty else { return "" }
        if locationWasRestored {
            if snapshot.provenance == .manual { return AppLocalization.string("上次填写的位置，请核对") }
            let dateText = snapshot.timestamp.map { Formatters.dateTime.string(from: $0) } ?? AppLocalization.string("未知时间")
            return String(format: AppLocalization.string("上次定位（%@），请核对或重新定位"), dateText)
        }
        return snapshot.statusText(at: now)
    }

    private func persistProjectDetails() {
        guard !isLoadingProjectDetails else { return }
        saveProjectDetails(for: selectedProjectIdRaw)
        // Keep the legacy keys in sync for older backups and versions.
        preferences.set(workSection, for: WatermarkCameraPreferenceKeys.workSection)
        preferences.set(floor, for: WatermarkCameraPreferenceKeys.floor)
        preferences.set(process, for: WatermarkCameraPreferenceKeys.process)
    }

    private func saveProjectDetails(for raw: String) {
        projectDetails[Self.projectKey(raw)] = ProjectDetails(workSection: workSection, floor: floor, process: process)
        if let data = try? JSONEncoder().encode(projectDetails) {
            preferences.set(data, for: WatermarkCameraPreferenceKeys.projectDetails)
        }
    }

    private func persistLocationSnapshot() {
        if let data = try? JSONEncoder().encode(locationSnapshot) {
            preferences.set(data, for: WatermarkCameraPreferenceKeys.locationSnapshot)
        }
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
        preferences.set(workSection, for: WatermarkCameraPreferenceKeys.workSection)
        preferences.set(floor, for: WatermarkCameraPreferenceKeys.floor)
        preferences.set(process, for: WatermarkCameraPreferenceKeys.process)
        preferences.set(issueNumber, for: WatermarkCameraPreferenceKeys.issueNumber)
        preferences.set(completedQuantity, for: WatermarkCameraPreferenceKeys.completedQuantity)
        preferences.set(receiptNote, for: WatermarkCameraPreferenceKeys.receiptNote)
        preferences.set(style.position.rawValue, for: WatermarkCameraPreferenceKeys.stylePosition)
        preferences.set(style.detail.rawValue, for: WatermarkCameraPreferenceKeys.styleDetail)
        persistLocationSnapshot()
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
