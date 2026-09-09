import Foundation
import Testing
@testable import sitekeeper

struct WatermarkCameraTests {
    @Test func watermarkLinesUseCapturedTime() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2026
        components.month = 5
        components.day = 3
        components.hour = 9
        components.minute = 8
        let capturedAt = try #require(components.date)

        let context = CameraWatermarkContext(
            projectName: "测试工程",
            template: .constructionLog,
            tag: "现场",
            photographer: "金工",
            locationText: "31.23000, 121.47000"
        )
        let lines = context.lines(capturedAt: capturedAt)

        #expect(lines.contains("时间: \(Formatters.dateTime.string(from: capturedAt))"))
        #expect(lines.contains("工程: 测试工程"))
        #expect(lines.contains("拍摄: 金工"))
    }

    @Test func dailyLogSeedPhotoKeepsDraftMetadata() throws {
        let capturedAt = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 10, minute: 15)))
        let data = Data([0x01, 0x02, 0x03])
        let seed = DailyLogSeedPhoto(data: data, note: "来源: 水印相机", tag: .rectificationBefore, capturedAt: capturedAt)
        let draft = seed.photoDraft

        #expect(draft.data == data)
        #expect(draft.note == "来源: 水印相机")
        #expect(draft.tag == .rectificationBefore)
        #expect(seed.capturedAt == capturedAt)
    }

    @Test func dailyLogPhotoImportSessionRejectsResultsFromOlderDraft() {
        var session = DailyLogPhotoImportSession()
        let firstDraftToken = session.beginImport()

        session.reset()
        let secondDraftToken = session.beginImport()

        #expect(!session.accepts(firstDraftToken))
        #expect(session.accepts(secondDraftToken))
        session.finishImport(firstDraftToken)
        #expect(session.isImporting)
        session.finishImport(secondDraftToken)
        #expect(!session.isImporting)
    }

    @Test func dailyLogPhotoImportSessionRejectsSupersededLoad() {
        var session = DailyLogPhotoImportSession()
        let firstImportToken = session.beginImport()
        let replacementImportToken = session.beginImport()

        #expect(!session.accepts(firstImportToken))
        #expect(session.accepts(replacementImportToken))
    }

    @Test func dailyLogCalendarIndexGroupsLargeCollectionsByDate() throws {
        let targetDate = try #require(Formatters.date.date(from: "2026-05-03"))
        let logs = (0..<10_000).map { index in
            DailyLog(
                date: index.isMultiple(of: 2) ? "2026-05-03" : "2026-05-04",
                weather: "晴",
                content: "日志 \(index)",
                workers: "1"
            )
        }

        let index = DailyLogCalendarIndex(logs: logs)
        let selectedLogs = index.logs(on: targetDate)

        #expect(selectedLogs.count == 5_000)
        #expect(selectedLogs.allSatisfy { $0.date == "2026-05-03" })
    }

    @Test func settingsStorePersistsWatermarkCameraChoices() throws {
        let (defaults, preferences) = try makeIsolatedPreferences()
        let settings = WatermarkCameraSettingsStore(preferences: preferences)
        let projectId = UUID()

        settings.selectedProjectId = projectId
        settings.projectName = "测试工地"
        settings.photographer = "张工"
        settings.locationText = "1.00000, 2.00000"
        settings.template = .rectification
        settings.tag = "整改前"
        settings.autoSaveToAlbum = false
        settings.autoOpenLogDraft = true
        settings.exportQuality = .high
        settings.showGrid = false
        settings.flashEnabled = true
        settings.burstCount = 9
        settings.normalizeBurstCount()

        let restored = WatermarkCameraSettingsStore(preferences: preferences)
        #expect(restored.selectedProjectId == projectId)
        #expect(restored.projectName == "测试工地")
        #expect(restored.photographer == "张工")
        #expect(restored.locationText == "1.00000, 2.00000")
        #expect(restored.template == .rectification)
        #expect(restored.tag == "整改前")
        #expect(restored.autoSaveToAlbum == false)
        #expect(restored.autoOpenLogDraft == true)
        #expect(restored.exportQuality == .high)
        #expect(restored.showGrid == false)
        #expect(restored.flashEnabled == true)
        #expect(restored.burstCount == 5)

        #expect(defaults.string(forKey: UserPreferenceKeys.watermarkCameraSelectedProjectId) == projectId.uuidString)
        #expect(defaults.string(forKey: UserPreferenceKeys.watermarkCameraProjectName) == "测试工地")
        #expect(defaults.string(forKey: UserPreferenceKeys.watermarkCameraPhotographer) == "张工")
        #expect(defaults.string(forKey: UserPreferenceKeys.watermarkCameraLocationText) == "1.00000, 2.00000")
        #expect(defaults.string(forKey: UserPreferenceKeys.watermarkCameraTemplateRaw) == CameraWatermarkTemplate.rectification.rawValue)
        #expect(defaults.string(forKey: UserPreferenceKeys.watermarkCameraTag) == "整改前")
        #expect(defaults.bool(forKey: UserPreferenceKeys.watermarkCameraAutoSaveToAlbum) == false)
        #expect(defaults.bool(forKey: UserPreferenceKeys.watermarkCameraAutoOpenLogDraft) == true)
        #expect(defaults.string(forKey: UserPreferenceKeys.watermarkCameraExportQualityRaw) == WatermarkExportQuality.high.rawValue)
        #expect(defaults.bool(forKey: UserPreferenceKeys.watermarkCameraShowGrid) == false)
        #expect(defaults.bool(forKey: UserPreferenceKeys.watermarkCameraFlashEnabled) == true)
        #expect(defaults.integer(forKey: UserPreferenceKeys.watermarkCameraBurstCount) == 5)
    }

    @Test func settingsStoreLoadsDefaultValuesWhenNoPersistedData() throws {
        let (defaults, preferences) = try makeIsolatedPreferences()
        let settings = WatermarkCameraSettingsStore(preferences: preferences)

        #expect(settings.selectedProjectId == nil)
        #expect(settings.selectedProjectIdRaw.isEmpty)
        #expect(settings.projectName.isEmpty)
        #expect(settings.photographer.isEmpty)
        #expect(settings.locationText.isEmpty)
        #expect(settings.template == .constructionLog)
        #expect(settings.tag == String(localized: "wm_camera_default_tag"))
        #expect(settings.autoSaveToAlbum == true)
        #expect(settings.autoOpenLogDraft == false)
        #expect(settings.exportQuality == .standard)
        #expect(settings.showGrid == true)
        #expect(settings.flashEnabled == false)
        #expect(settings.burstCount == 1)
        #expect(settings.boundedBurstCount == 1)

        #expect(Set(WatermarkCameraSettingsStore.managedPreferenceKeys).count == WatermarkCameraSettingsStore.managedPreferenceKeys.count)
        for key in WatermarkCameraSettingsStore.managedPreferenceKeys {
            #expect(defaults.object(forKey: key) != nil)
        }
    }

    @Test func settingsStoreMigratesLegacyValuesAndNormalizesInvalidFields() throws {
        let (defaults, preferences) = try makeIsolatedPreferences()

        defaults.set("not-a-uuid", forKey: UserPreferenceKeys.watermarkCameraSelectedProjectId)
        defaults.set("  现场工程  ", forKey: UserPreferenceKeys.watermarkCameraProjectName)
        defaults.set("  李工  ", forKey: UserPreferenceKeys.watermarkCameraPhotographer)
        defaults.set("  ", forKey: UserPreferenceKeys.watermarkCameraLocationText)
        defaults.set("legacy-template", forKey: UserPreferenceKeys.watermarkCameraTemplateRaw)
        defaults.set("   ", forKey: UserPreferenceKeys.watermarkCameraTag)
        defaults.set(false, forKey: UserPreferenceKeys.watermarkCameraAutoSaveToAlbum)
        defaults.set(true, forKey: UserPreferenceKeys.watermarkCameraAutoOpenLogDraft)
        defaults.set("legacy-quality", forKey: UserPreferenceKeys.watermarkCameraExportQualityRaw)
        defaults.set(false, forKey: UserPreferenceKeys.watermarkCameraShowGrid)
        defaults.set(true, forKey: UserPreferenceKeys.watermarkCameraFlashEnabled)
        defaults.set(99, forKey: UserPreferenceKeys.watermarkCameraBurstCount)

        let settings = WatermarkCameraSettingsStore(preferences: preferences)

        #expect(settings.selectedProjectId == nil)
        #expect(settings.selectedProjectIdRaw.isEmpty)
        #expect(settings.projectName == "现场工程")
        #expect(settings.photographer == "李工")
        #expect(settings.locationText.isEmpty)
        #expect(settings.template == .constructionLog)
        #expect(settings.templateRaw == CameraWatermarkTemplate.constructionLog.rawValue)
        #expect(settings.tag == String(localized: "wm_camera_default_tag"))
        #expect(settings.autoSaveToAlbum == false)
        #expect(settings.autoOpenLogDraft == true)
        #expect(settings.exportQuality == .standard)
        #expect(settings.exportQualityRaw == WatermarkExportQuality.standard.rawValue)
        #expect(settings.showGrid == false)
        #expect(settings.flashEnabled == true)
        #expect(settings.burstCount == 5)

        #expect(defaults.string(forKey: UserPreferenceKeys.watermarkCameraSelectedProjectId) == "")
        #expect(defaults.string(forKey: UserPreferenceKeys.watermarkCameraProjectName) == "现场工程")
        #expect(defaults.string(forKey: UserPreferenceKeys.watermarkCameraPhotographer) == "李工")
        #expect(defaults.string(forKey: UserPreferenceKeys.watermarkCameraLocationText) == "")
        #expect(defaults.string(forKey: UserPreferenceKeys.watermarkCameraTemplateRaw) == CameraWatermarkTemplate.constructionLog.rawValue)
        #expect(defaults.string(forKey: UserPreferenceKeys.watermarkCameraTag) == String(localized: "wm_camera_default_tag"))
        #expect(defaults.string(forKey: UserPreferenceKeys.watermarkCameraExportQualityRaw) == WatermarkExportQuality.standard.rawValue)
        #expect(defaults.integer(forKey: UserPreferenceKeys.watermarkCameraBurstCount) == 5)
    }

    private func makeIsolatedPreferences() throws -> (defaults: UserDefaults, preferences: UserPreferencesStore) {
        let suiteName = "WatermarkCameraTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let preferences = UserPreferencesStore(defaults: defaults)
        return (defaults, preferences)
    }
}
