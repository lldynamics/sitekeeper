import Foundation
import Observation
import SwiftUI
import Testing
@testable import sitekeeper

@Suite(.serialized)
@MainActor
struct AppPresentationTests {
    @Test func languageChangesResolveStringsAndStaticCalculatorCopyWithoutRestart() {
        let preferences = UserPreferencesStore.shared
        let previous = preferences.string(UserPreferenceKeys.languageCode)
        defer { restore(previous, key: UserPreferenceKeys.languageCode) }

        preferences.set(AppLanguage.chinese.rawValue, for: UserPreferenceKeys.languageCode)
        #expect(AppLocalization.string("项目") == "项目")
        #expect(CalculatorResultLabel.input == "输入")
        #expect(ToolboxCatalog.practicalTools.first?.title == "水印相机")
        let tutorialIDs = ConstructionMethodTutorialBlockCatalog.quickTools.map(\.id)
        let changed = PresentationObservationFlag()
        withObservationTracking {
            _ = AppLocalization.string("项目")
        } onChange: { changed.set() }

        preferences.set(AppLanguage.english.rawValue, for: UserPreferenceKeys.languageCode)
        #expect(changed.isSet)
        #expect(AppLocalization.string("项目") == "Projects")
        #expect(CalculatorResultLabel.input == "Input")
        #expect(ToolboxCatalog.practicalTools.first?.title == "Watermark Camera")
        #expect(ConstructionMethodTutorialBlockCatalog.quickTools.map(\.id) == tutorialIDs)
        #expect(Tab.dashboard.title == "Dashboard")
        #expect(PaymentStatus.partial.displayName == "Partially Paid")
        #expect(ProjectFinancialStatus.active.displayName == "Active")
        #expect(AppTheme.dropboxBlue.displayName == "Sky Blue")
        #expect(String(format: AppLocalization.string("%lld 天"), Int64(12)) == "12 days")

        preferences.set(AppLanguage.chinese.rawValue, for: UserPreferenceKeys.languageCode)
        #expect(AppLocalization.string("项目") == "项目")
        #expect(CalculatorResultLabel.input == "输入")
    }

    @Test func themeColorReadsParticipateInObservation() {
        let preferences = UserPreferencesStore.shared
        let previous = preferences.string(UserPreferenceKeys.appTheme)
        defer { restore(previous, key: UserPreferenceKeys.appTheme) }
        preferences.set(AppTheme.dropboxBlue.rawValue, for: UserPreferenceKeys.appTheme)
        let blue = UIColor(Color.appPrimaryAction).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let changed = PresentationObservationFlag()
        withObservationTracking {
            _ = Color.appPrimaryAction
            _ = Color.appFinanceSurface
        } onChange: { changed.set() }

        AppTheme.warmAmber.apply()
        #expect(changed.isSet)
        #expect(AppTheme.current == .warmAmber)
        let amber = UIColor(Color.appPrimaryAction).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        #expect(!blue.isEqual(amber))
    }

    @Test func resourceBundlesAndUnknownKeysHavePredictableFallbacks() {
        #expect(AppLocalization.localizedBundle(language: .english).bundleURL.lastPathComponent == "en.lproj")
        #expect(AppLocalization.localizedBundle(language: .chinese).bundleURL.lastPathComponent == "zh-Hans.lproj")
        #expect(AppLocalization.string("uiux-missing-key") == "uiux-missing-key")
        #expect(["zh-Hans", "en"].contains(AppLanguage.system.resourceLanguageCode))
    }

    private func restore(_ value: String, key: String) {
        if value.isEmpty {
            UserPreferencesStore.shared.removeObject(for: key)
        } else {
            UserPreferencesStore.shared.set(value, for: key)
        }
    }
}

private final class PresentationObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        defer { lock.unlock() }
        value = true
    }
}
