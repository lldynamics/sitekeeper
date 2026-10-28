import Foundation
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

enum AppLocalization {
    // Resource lookup needs the selected language bundle; locale also controls
    // interpolation. SwiftUI's locale cannot update an already resolved String.
    static func string(
        _ key: String.LocalizationValue,
        table: String? = nil,
        bundle: Bundle = .main,
        locale: Locale? = nil,
        comment: StaticString? = nil
    ) -> String {
        let language = AppLanguage.current
        return String(
            localized: key,
            table: table,
            bundle: localizedBundle(language: language, bundle: bundle),
            locale: locale ?? language.preferredLocale,
            comment: comment
        )
    }

    static func localizedBundle(language: AppLanguage, bundle: Bundle = .main) -> Bundle {
        guard let path = bundle.path(forResource: language.resourceLanguageCode, ofType: "lproj"),
              let localized = Bundle(path: path) else { return bundle }
        return localized
    }
}

enum AppAppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }
}

enum AppLanguage: String, CaseIterable {
    case system = "system"
    case chinese = "zh-Hans"
    case english = "en"

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    var preferredLocale: Locale {
        switch self {
        case .system:
            return Locale(identifier: resourceLanguageCode)
        case .chinese, .english:
            return Locale(identifier: rawValue)
        }
    }

    var appleLanguageCodes: [String]? {
        switch self {
        case .system:
            return nil
        case .chinese, .english:
            return [rawValue]
        }
    }

    var resourceLanguageCode: String {
        guard self == .system else { return rawValue }
        // The app domain can contain our previous in-app choice. Resolve the
        // system option from device preferences rather than that override.
        let languages = UserPreferencesStore.shared.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
            ?? Locale.preferredLanguages
        return Bundle.preferredLocalizations(from: ["zh-Hans", "en"], forPreferences: languages).first ?? "en"
    }

    static var current: AppLanguage {
        let stored = UserPreferencesStore.shared.string(
            UserPreferenceKeys.languageCode,
            default: "",
            trimWhitespace: false
        )
        return StringEnumFallback.value(stored, default: .chinese)
    }

    static func apply(_ language: AppLanguage) {
        if let appleLanguageCodes = language.appleLanguageCodes {
            UserPreferencesStore.shared.set(appleLanguageCodes, for: "AppleLanguages")
        } else {
            UserPreferencesStore.shared.removeObject(for: "AppleLanguages")
        }
        UserPreferencesStore.shared.set(language.rawValue, for: UserPreferenceKeys.languageCode)
        syncWidgetLanguage(language)
        reloadWidgetLanguage()
    }

    static func restoreFromStorage() {
        let stored = UserPreferencesStore.shared.string(
            UserPreferenceKeys.languageCode,
            default: "",
            trimWhitespace: false
        )
        let lang = StringEnumFallback.value(stored, default: AppLanguage.chinese)
        if let appleLanguageCodes = lang.appleLanguageCodes {
            UserPreferencesStore.shared.set(appleLanguageCodes, for: "AppleLanguages")
        } else {
            UserPreferencesStore.shared.removeObject(for: "AppleLanguages")
        }
        syncWidgetLanguage(lang)
        reloadWidgetLanguage()
    }

    private static func syncWidgetLanguage(_ language: AppLanguage) {
        guard let defaults = UserDefaults(suiteName: WidgetSharedDefaults.suiteName) else { return }
        defaults.set(language.rawValue, forKey: WidgetSharedDefaults.languageCodeKey)
        if let appleLanguageCodes = language.appleLanguageCodes {
            defaults.set(appleLanguageCodes, forKey: WidgetSharedDefaults.appleLanguagesKey)
        } else {
            defaults.removeObject(forKey: WidgetSharedDefaults.appleLanguagesKey)
        }
    }

    private static func reloadWidgetLanguage() {
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedDefaults.widgetKind)
#endif
    }
}

struct ThemePalette {
    let primary: Color
    let success: Color
    let warning: Color
    let risk: Color
    let doc: Color
    let finance: Color
    let inventory: Color
    let people: Color
    let journal: Color
    let photo: Color
    let calculations: Color
    let quotation: Color
    let primaryUIColor: UIColor
    let successUIColor: UIColor
    let warningUIColor: UIColor
    let riskUIColor: UIColor
    let docUIColor: UIColor
    let financeUIColor: UIColor
    let inventoryUIColor: UIColor
    let peopleUIColor: UIColor
    let journalUIColor: UIColor
    let photoUIColor: UIColor
    let calculationsUIColor: UIColor
    let quotationUIColor: UIColor
}

enum AppTheme: String, CaseIterable {
    case dropboxBlue = "dropbox_blue"
    case jiangnanSpring = "jiangnan_spring"
    case warmAmber = "warm_amber"

    var displayName: String {
        switch self {
        case .dropboxBlue: return AppLocalization.string("晴空蓝")
        case .jiangnanSpring: return AppLocalization.string("江南春")
        case .warmAmber: return AppLocalization.string("暖橙")
        }
    }

    static var current: AppTheme {
        let stored = UserPreferencesStore.shared.string(
            UserPreferenceKeys.appTheme,
            default: "",
            trimWhitespace: false
        )
        return StringEnumFallback.value(stored, default: .jiangnanSpring)
    }

    func apply() {
        UserPreferencesStore.shared.set(rawValue, for: UserPreferenceKeys.appTheme)
    }

    var palette: ThemePalette {
        switch self {
        case .dropboxBlue:
            return ThemePalette(
                primary: Color(light: UIColor(red: 0.00, green: 0.38, blue: 1.00, alpha: 1),
                               dark: UIColor(red: 0.25, green: 0.55, blue: 1.00, alpha: 1)),
                success: Color(light: UIColor(red: 0.18, green: 0.56, blue: 0.25, alpha: 1),
                               dark: UIColor(red: 0.50, green: 0.82, blue: 0.46, alpha: 1)),
                warning: Color(light: UIColor(red: 0.84, green: 0.55, blue: 0.11, alpha: 1),
                               dark: UIColor(red: 0.92, green: 0.65, blue: 0.22, alpha: 1)),
                risk: Color(light: UIColor(red: 0.78, green: 0.16, blue: 0.16, alpha: 1),
                            dark: UIColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1)),
                doc: Color(light: UIColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 1),
                           dark: UIColor(red: 0.55, green: 0.55, blue: 1.00, alpha: 1)),
                finance: Color(light: UIColor(red: 0.00, green: 0.38, blue: 1.00, alpha: 1),
                               dark: UIColor(red: 0.25, green: 0.55, blue: 1.00, alpha: 1)),
                inventory: Color(light: UIColor(red: 0.18, green: 0.56, blue: 0.25, alpha: 1),
                                 dark: UIColor(red: 0.50, green: 0.82, blue: 0.46, alpha: 1)),
                people: Color(light: UIColor(red: 0.55, green: 0.55, blue: 0.67, alpha: 1),
                              dark: UIColor(red: 0.68, green: 0.68, blue: 0.78, alpha: 1)),
                journal: Color(light: UIColor(red: 0.75, green: 0.69, blue: 0.56, alpha: 1),
                               dark: UIColor(red: 0.82, green: 0.76, blue: 0.64, alpha: 1)),
                photo: Color(light: UIColor(red: 0.72, green: 0.44, blue: 0.44, alpha: 1),
                             dark: UIColor(red: 0.80, green: 0.54, blue: 0.54, alpha: 1)),
                calculations: Color(light: UIColor(red: 0.35, green: 0.56, blue: 0.77, alpha: 1),
                                    dark: UIColor(red: 0.50, green: 0.68, blue: 0.85, alpha: 1)),
                quotation: Color(light: UIColor(red: 0.48, green: 0.63, blue: 0.62, alpha: 1),
                                 dark: UIColor(red: 0.60, green: 0.73, blue: 0.72, alpha: 1)),
                primaryUIColor: UIColor(red: 0.00, green: 0.38, blue: 1.00, alpha: 1),
                successUIColor: UIColor(red: 0.18, green: 0.56, blue: 0.25, alpha: 1),
                warningUIColor: UIColor(red: 0.84, green: 0.55, blue: 0.11, alpha: 1),
                riskUIColor: UIColor(red: 0.78, green: 0.16, blue: 0.16, alpha: 1),
                docUIColor: UIColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 1),
                financeUIColor: UIColor(red: 0.00, green: 0.38, blue: 1.00, alpha: 1),
                inventoryUIColor: UIColor(red: 0.18, green: 0.56, blue: 0.25, alpha: 1),
                peopleUIColor: UIColor(red: 0.55, green: 0.55, blue: 0.67, alpha: 1),
                journalUIColor: UIColor(red: 0.75, green: 0.69, blue: 0.56, alpha: 1),
                photoUIColor: UIColor(red: 0.72, green: 0.44, blue: 0.44, alpha: 1),
                calculationsUIColor: UIColor(red: 0.35, green: 0.56, blue: 0.77, alpha: 1),
                quotationUIColor: UIColor(red: 0.48, green: 0.63, blue: 0.62, alpha: 1)
            )

        case .jiangnanSpring:
            return ThemePalette(
                primary: Color(light: UIColor(red: 0.16, green: 0.48, blue: 0.26, alpha: 1),
                               dark: UIColor(red: 0.42, green: 0.78, blue: 0.50, alpha: 1)),
                success: Color(light: UIColor(red: 0.18, green: 0.52, blue: 0.24, alpha: 1),
                               dark: UIColor(red: 0.46, green: 0.76, blue: 0.48, alpha: 1)),
                warning: Color(light: UIColor(red: 0.88, green: 0.45, blue: 0.08, alpha: 1),
                               dark: UIColor(red: 0.94, green: 0.56, blue: 0.18, alpha: 1)),
                risk: Color(light: UIColor(red: 0.82, green: 0.18, blue: 0.22, alpha: 1),
                            dark: UIColor(red: 0.92, green: 0.35, blue: 0.38, alpha: 1)),
                doc: Color(light: UIColor(red: 0.22, green: 0.48, blue: 0.64, alpha: 1),
                           dark: UIColor(red: 0.52, green: 0.72, blue: 0.84, alpha: 1)),
                finance: Color(light: UIColor(red: 0.76, green: 0.48, blue: 0.12, alpha: 1),
                               dark: UIColor(red: 0.88, green: 0.68, blue: 0.32, alpha: 1)),
                inventory: Color(light: UIColor(red: 0.52, green: 0.42, blue: 0.68, alpha: 1),
                                 dark: UIColor(red: 0.70, green: 0.64, blue: 0.78, alpha: 1)),
                people: Color(light: UIColor(red: 0.32, green: 0.54, blue: 0.56, alpha: 1),
                              dark: UIColor(red: 0.60, green: 0.74, blue: 0.74, alpha: 1)),
                journal: Color(light: UIColor(red: 0.68, green: 0.58, blue: 0.42, alpha: 1),
                               dark: UIColor(red: 0.85, green: 0.79, blue: 0.67, alpha: 1)),
                photo: Color(light: UIColor(red: 0.72, green: 0.36, blue: 0.36, alpha: 1),
                             dark: UIColor(red: 0.80, green: 0.54, blue: 0.52, alpha: 1)),
                calculations: Color(light: UIColor(red: 0.32, green: 0.54, blue: 0.68, alpha: 1),
                                    dark: UIColor(red: 0.54, green: 0.72, blue: 0.80, alpha: 1)),
                quotation: Color(light: UIColor(red: 0.68, green: 0.52, blue: 0.38, alpha: 1),
                                 dark: UIColor(red: 0.84, green: 0.69, blue: 0.56, alpha: 1)),
                primaryUIColor: UIColor(red: 0.16, green: 0.48, blue: 0.26, alpha: 1),
                successUIColor: UIColor(red: 0.18, green: 0.52, blue: 0.24, alpha: 1),
                warningUIColor: UIColor(red: 0.88, green: 0.45, blue: 0.08, alpha: 1),
                riskUIColor: UIColor(red: 0.82, green: 0.18, blue: 0.22, alpha: 1),
                docUIColor: UIColor(red: 0.22, green: 0.48, blue: 0.64, alpha: 1),
                financeUIColor: UIColor(red: 0.76, green: 0.48, blue: 0.12, alpha: 1),
                inventoryUIColor: UIColor(red: 0.52, green: 0.42, blue: 0.68, alpha: 1),
                peopleUIColor: UIColor(red: 0.32, green: 0.54, blue: 0.56, alpha: 1),
                journalUIColor: UIColor(red: 0.68, green: 0.58, blue: 0.42, alpha: 1),
                photoUIColor: UIColor(red: 0.72, green: 0.36, blue: 0.36, alpha: 1),
                calculationsUIColor: UIColor(red: 0.32, green: 0.54, blue: 0.68, alpha: 1),
                quotationUIColor: UIColor(red: 0.68, green: 0.52, blue: 0.38, alpha: 1)
            )

        case .warmAmber:
            return ThemePalette(
                primary: Color(light: UIColor(red: 0.90, green: 0.40, blue: 0.10, alpha: 1),
                               dark: UIColor(red: 0.94, green: 0.52, blue: 0.29, alpha: 1)),
                success: Color(light: UIColor(red: 0.18, green: 0.56, blue: 0.25, alpha: 1),
                               dark: UIColor(red: 0.50, green: 0.82, blue: 0.46, alpha: 1)),
                warning: Color(light: UIColor(red: 0.88, green: 0.50, blue: 0.08, alpha: 1),
                               dark: UIColor(red: 0.94, green: 0.60, blue: 0.20, alpha: 1)),
                risk: Color(light: UIColor(red: 0.78, green: 0.16, blue: 0.16, alpha: 1),
                            dark: UIColor(red: 0.90, green: 0.30, blue: 0.30, alpha: 1)),
                doc: Color(light: UIColor(red: 0.30, green: 0.55, blue: 0.75, alpha: 1),
                           dark: UIColor(red: 0.45, green: 0.65, blue: 0.82, alpha: 1)),
                finance: Color(light: UIColor(red: 0.90, green: 0.40, blue: 0.10, alpha: 1),
                               dark: UIColor(red: 0.94, green: 0.52, blue: 0.29, alpha: 1)),
                inventory: Color(light: UIColor(red: 0.18, green: 0.56, blue: 0.25, alpha: 1),
                                 dark: UIColor(red: 0.50, green: 0.82, blue: 0.46, alpha: 1)),
                people: Color(light: UIColor(red: 0.30, green: 0.55, blue: 0.75, alpha: 1),
                              dark: UIColor(red: 0.45, green: 0.65, blue: 0.82, alpha: 1)),
                journal: Color(light: UIColor(red: 0.77, green: 0.66, blue: 0.49, alpha: 1),
                               dark: UIColor(red: 0.84, green: 0.74, blue: 0.58, alpha: 1)),
                photo: Color(light: UIColor(red: 0.72, green: 0.44, blue: 0.44, alpha: 1),
                             dark: UIColor(red: 0.80, green: 0.54, blue: 0.54, alpha: 1)),
                calculations: Color(light: UIColor(red: 0.83, green: 0.56, blue: 0.35, alpha: 1),
                                    dark: UIColor(red: 0.90, green: 0.65, blue: 0.44, alpha: 1)),
                quotation: Color(light: UIColor(red: 0.77, green: 0.61, blue: 0.38, alpha: 1),
                                 dark: UIColor(red: 0.84, green: 0.69, blue: 0.48, alpha: 1)),
                primaryUIColor: UIColor(red: 0.90, green: 0.40, blue: 0.10, alpha: 1),
                successUIColor: UIColor(red: 0.18, green: 0.56, blue: 0.25, alpha: 1),
                warningUIColor: UIColor(red: 0.88, green: 0.50, blue: 0.08, alpha: 1),
                riskUIColor: UIColor(red: 0.78, green: 0.16, blue: 0.16, alpha: 1),
                docUIColor: UIColor(red: 0.30, green: 0.55, blue: 0.75, alpha: 1),
                financeUIColor: UIColor(red: 0.90, green: 0.40, blue: 0.10, alpha: 1),
                inventoryUIColor: UIColor(red: 0.18, green: 0.56, blue: 0.25, alpha: 1),
                peopleUIColor: UIColor(red: 0.30, green: 0.55, blue: 0.75, alpha: 1),
                journalUIColor: UIColor(red: 0.77, green: 0.66, blue: 0.49, alpha: 1),
                photoUIColor: UIColor(red: 0.72, green: 0.44, blue: 0.44, alpha: 1),
                calculationsUIColor: UIColor(red: 0.83, green: 0.56, blue: 0.35, alpha: 1),
                quotationUIColor: UIColor(red: 0.77, green: 0.61, blue: 0.38, alpha: 1)
            )
        }
    }
}

// App-only presentation stays outside the model compiled into the widget target.
extension WidgetProjectStatus {
    var displayName: String {
        switch self {
        case .active:
            return AppLocalization.string("widget_project_status_active")
        case .paused:
            return AppLocalization.string("widget_project_status_paused")
        case .completed:
            return AppLocalization.string("widget_project_status_completed")
        case .settled:
            return AppLocalization.string("widget_project_status_settled")
        case .archived:
            return AppLocalization.string("widget_project_status_archived")
        case .unknown:
            return AppLocalization.string("widget_project_status_unknown")
        }
    }
}
