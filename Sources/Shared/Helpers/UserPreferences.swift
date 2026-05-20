import Foundation
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

enum UserPreferenceKeys {
    static let useMetric = "useMetric"
    static let autoSave = "autoSave"
    static let appearanceMode = "appearanceMode"
    static let favoriteCalculators = "favoriteCalculators"
    static let companyName = "companyName"
    static let companyPhone = "companyPhone"
    static let companyAddress = "companyAddress"
    static let quoteValidityDays = "quoteValidityDays"
    static let didCompleteOnboarding = "didCompleteOnboarding"
    static let completedOnboardingVersion = "onboarding.completedVersion"
    static let hasSeenBackupGuide = "guide.backup.hasSeen"
    static let hasCompletedBackupExportTask = "task.backup.firstExportCompleted"
    static let languageCode = "languageCode"
    static let cloudBackupIncludeBusinessRecords = "cloudBackup.includeBusinessRecords"
    static let cloudBackupIncludeProjectRecords = "cloudBackup.includeProjectRecords"
    static let cloudBackupIncludeProjectFilesAndNotes = "cloudBackup.includeProjectFilesAndNotes"
    static let cloudBackupIncludeKnowledgeBase = "cloudBackup.includeKnowledgeBase"
    static let cloudBackupIncludeAttachments = "cloudBackup.includeAttachments"
    static let cloudBackupAutoInterval = "cloudBackup.autoInterval"
    static let cloudBackupAutoRequiresWiFi = "cloudBackup.autoRequiresWiFi"
    static let cloudBackupRetentionCount = "cloudBackup.retentionCount"
    static let cloudBackupLastSuccessAt = "cloudBackup.lastSuccessAt"
    static let localBackupLastSuccessAt = "backup.local.lastSuccessAt"
    static let backupHealthReminderDays = "backup.health.reminderDays"
    static let storageCleanupLargeFileThresholdMB = "storageCleanup.largeFileThresholdMB"
    static let storageCleanupTrashRetentionDays = "storageCleanup.trashRetentionDays"
    static let exportCurrencyDisplayMode = "export.currencyDisplayMode"
    static let cloudBackupAutoLastAttemptAt = "cloudBackup.autoLastAttemptAt"
    static let cloudBackupAutoLastStatus = "cloudBackup.autoLastStatus"
    static let userName = "userName"
    static let userAvatarData = "userAvatarData"
    static let drawingLibraryRecentDrawingIDs = "drawing.library.recentDrawingIDs"
    static let materialPriceSpikeThreshold = "dashboard.materialPriceSpikeThreshold"
    static let materialPriceSpikeIgnoredKeys = "dashboard.materialPriceSpikeIgnoredKeys"
    static let materialLibraryPromptAfterAdd = "materialLibrary.promptAfterAdd"
    static let materialLibraryLastTargetMode = "materialLibrary.lastTargetMode"
    static let materialLibraryLastDraftID = "materialLibrary.lastDraftID"
    static let materialLibraryLastProjectID = "materialLibrary.lastProjectID"
    static let materialLibraryKeepAppending = "materialLibrary.keepAppending"
    static let appTheme = "app.theme"
    static let dashboardIgnoredBackupRiskDay = "dashboard.risk.ignore.backup.day"
    static let dashboardIgnoredMissingReceiptRiskDay = "dashboard.risk.ignore.missingReceipt.day"
    static let dashboardIgnoredPriceSpikeRiskDay = "dashboard.risk.ignore.priceSpike.day"
    static let dashboardIgnoredNegativeStockRiskDay = "dashboard.risk.ignore.negativeStock.day"

    enum Calculator {
        static let breakerCurrent = "calc.breaker.current"
        static let breakerLoadType = "calc.breaker.loadType"
        static let concreteGrade = "calc.concrete.grade"
        static let concreteLength = "calc.concrete.length"
        static let concreteThickness = "calc.concrete.thickness"
        static let concreteWaste = "calc.concrete.waste"
        static let concreteWidth = "calc.concrete.width"
        static let conduitInnerDia = "calc.conduit.innerDia"
        static let conduitWireCount = "calc.conduit.wireCount"
        static let conduitWireDia = "calc.conduit.wireDia"
        static let currentIsThreePhase = "calc.current.isThreePhase"
        static let currentPower = "calc.current.power"
        static let currentPowerFactor = "calc.current.powerFactor"
        static let currentVoltage = "calc.current.voltage"
        static let rebarDia = "calc.rebar.dia"
        static let rebarLen = "calc.rebar.len"
        static let rebarPrice = "calc.rebar.price"
        static let rebarQty = "calc.rebar.qty"
        static let tileBox = "calc.tile.box"
        static let tileRoomLength = "calc.tile.roomLength"
        static let tileRoomWidth = "calc.tile.roomWidth"
        static let tileTileLength = "calc.tile.tileLength"
        static let tileTileWidth = "calc.tile.tileWidth"
        static let tileWaste = "calc.tile.waste"
        static let trayCables = "calc.tray.cables"
        static let trayHeight = "calc.tray.height"
        static let trayWidth = "calc.tray.width"
        static let unitCategory = "calc.unit.category"
        static let unitFromUnit = "calc.unit.fromUnit"
        static let unitInputValue = "calc.unit.inputValue"
        static let unitToUnit = "calc.unit.toUnit"
        static let voltageDropCurrent = "calc.voltageDrop.current"
        static let voltageDropIsLoopLength = "calc.voltageDrop.isLoopLength"
        static let voltageDropLength = "calc.voltageDrop.length"
        static let voltageDropMaterial = "calc.voltageDrop.material"
        static let voltageDropSection = "calc.voltageDrop.section"
        static let voltageDropVoltage = "calc.voltageDrop.voltage"
        static let wallDoors = "calc.wall.doors"
        static let wallHeight = "calc.wall.height"
        static let wallL1 = "calc.wall.l1"
        static let wallL2 = "calc.wall.l2"
        static let wallL3 = "calc.wall.l3"
        static let wallL4 = "calc.wall.l4"
        static let wallWindows = "calc.wall.windows"
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
            return .autoupdatingCurrent
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

    static var current: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: UserPreferenceKeys.languageCode) ?? ""
        return StringEnumFallback.value(stored, default: .chinese)
    }

    static func apply(_ language: AppLanguage) {
        if let appleLanguageCodes = language.appleLanguageCodes {
            UserDefaults.standard.set(appleLanguageCodes, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.set(language.rawValue, forKey: UserPreferenceKeys.languageCode)
        syncWidgetLanguage(language)
        reloadWidgetLanguage()
    }

    static func restoreFromStorage() {
        let stored = UserDefaults.standard.string(forKey: UserPreferenceKeys.languageCode) ?? ""
        let lang = StringEnumFallback.value(stored, default: AppLanguage.chinese)
        if let appleLanguageCodes = lang.appleLanguageCodes {
            UserDefaults.standard.set(appleLanguageCodes, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
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

// MARK: - 主题色

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
        case .dropboxBlue: return String(localized: "晴空蓝")
        case .jiangnanSpring: return String(localized: "江南春")
        case .warmAmber: return String(localized: "暖橙")
        }
    }

    static var current: AppTheme {
        let stored = UserDefaults.standard.string(forKey: UserPreferenceKeys.appTheme) ?? ""
        return StringEnumFallback.value(stored, default: .jiangnanSpring)
    }

    func apply() {
        UserDefaults.standard.set(rawValue, forKey: UserPreferenceKeys.appTheme)
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
                primary: Color(light: UIColor(red: 0.48, green: 0.69, blue: 0.42, alpha: 1),
                               dark: UIColor(red: 0.58, green: 0.78, blue: 0.52, alpha: 1)),
                success: Color(light: UIColor(red: 0.35, green: 0.62, blue: 0.35, alpha: 1),
                               dark: UIColor(red: 0.50, green: 0.75, blue: 0.48, alpha: 1)),
                warning: Color(light: UIColor(red: 0.91, green: 0.57, blue: 0.64, alpha: 1),
                               dark: UIColor(red: 0.85, green: 0.62, blue: 0.68, alpha: 1)),
                risk: Color(light: UIColor(red: 0.35, green: 0.31, blue: 0.28, alpha: 1),
                            dark: UIColor(red: 0.55, green: 0.50, blue: 0.45, alpha: 1)),
                doc: Color(light: UIColor(red: 0.55, green: 0.66, blue: 0.73, alpha: 1),
                           dark: UIColor(red: 0.65, green: 0.75, blue: 0.80, alpha: 1)),
                finance: Color(light: UIColor(red: 0.83, green: 0.66, blue: 0.33, alpha: 1),
                               dark: UIColor(red: 0.88, green: 0.72, blue: 0.44, alpha: 1)),
                inventory: Color(light: UIColor(red: 0.61, green: 0.55, blue: 0.71, alpha: 1),
                                dark: UIColor(red: 0.70, green: 0.64, blue: 0.78, alpha: 1)),
                people: Color(light: UIColor(red: 0.49, green: 0.65, blue: 0.65, alpha: 1),
                              dark: UIColor(red: 0.60, green: 0.74, blue: 0.74, alpha: 1)),
                journal: Color(light: UIColor(red: 0.78, green: 0.72, blue: 0.59, alpha: 1),
                               dark: UIColor(red: 0.85, green: 0.79, blue: 0.67, alpha: 1)),
                photo: Color(light: UIColor(red: 0.72, green: 0.44, blue: 0.42, alpha: 1),
                             dark: UIColor(red: 0.80, green: 0.54, blue: 0.52, alpha: 1)),
                calculations: Color(light: UIColor(red: 0.42, green: 0.62, blue: 0.71, alpha: 1),
                                    dark: UIColor(red: 0.54, green: 0.72, blue: 0.80, alpha: 1)),
                quotation: Color(light: UIColor(red: 0.77, green: 0.61, blue: 0.48, alpha: 1),
                                 dark: UIColor(red: 0.84, green: 0.69, blue: 0.56, alpha: 1)),
                primaryUIColor: UIColor(red: 0.48, green: 0.69, blue: 0.42, alpha: 1),
                successUIColor: UIColor(red: 0.35, green: 0.62, blue: 0.35, alpha: 1),
                warningUIColor: UIColor(red: 0.91, green: 0.57, blue: 0.64, alpha: 1),
                riskUIColor: UIColor(red: 0.35, green: 0.31, blue: 0.28, alpha: 1),
                docUIColor: UIColor(red: 0.55, green: 0.66, blue: 0.73, alpha: 1),
                financeUIColor: UIColor(red: 0.83, green: 0.66, blue: 0.33, alpha: 1),
                inventoryUIColor: UIColor(red: 0.61, green: 0.55, blue: 0.71, alpha: 1),
                peopleUIColor: UIColor(red: 0.49, green: 0.65, blue: 0.65, alpha: 1),
                journalUIColor: UIColor(red: 0.78, green: 0.72, blue: 0.59, alpha: 1),
                photoUIColor: UIColor(red: 0.72, green: 0.44, blue: 0.42, alpha: 1),
                calculationsUIColor: UIColor(red: 0.42, green: 0.62, blue: 0.71, alpha: 1),
                quotationUIColor: UIColor(red: 0.77, green: 0.61, blue: 0.48, alpha: 1)
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

enum AppContact {
    static let supportEmail = "support@chengjinfang.com"
}

enum AppBrand {
    static var displayName: String {
        let info = Bundle.main.infoDictionary
        if let name = info?["CFBundleDisplayName"] as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        if let name = info?[kCFBundleNameKey as String] as? String,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "工地掌柜"
    }

    static var exportFilePrefix: String {
        displayName
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "0"
    }
}

enum AppPolicy {
    static let privacyPolicyLastUpdated = "2026年5月15日"
}

enum AppFeatureFlags {
    static var allowsSampleDataImport: Bool {
#if DEBUG
        TransferLimitPolicy.allowsSampleDataImport
#else
        false
#endif
    }

}

enum UserPreferences {
    static func bool(_ key: String, default defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    static func string(_ key: String, default defaultValue: String = "") -> String {
        let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? defaultValue : value
    }

    static func int(_ key: String, default defaultValue: Int) -> Int {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.integer(forKey: key)
    }
}

enum UnitDisplay {
    static func quantityWithUnit(_ quantity: String, unit: String, useMetric: Bool) -> String {
        guard !useMetric else { return "\(quantity) \(unit)" }
        guard let numericDecimal = DataValueParser.decimalValueIfPresent(from: quantity, requiresEntireString: true) else {
            return "\(quantity) \(translatedUnit(unit, useMetric: useMetric))"
        }
        let numeric = NSDecimalNumber(decimal: numericDecimal).doubleValue
        guard let converted = convert(value: numeric, from: unit) else {
            return "\(quantity) \(translatedUnit(unit, useMetric: useMetric))"
        }
        return "\(trim(converted.value)) \(converted.unit)"
    }

    static func translatedUnit(_ unit: String, useMetric: Bool) -> String {
        guard !useMetric else { return unit }
        if unit == "h" { return "hr" }
        return convert(value: 1, from: unit)?.unit ?? unit
    }

    private static func convert(value: Double, from unit: String) -> (value: Double, unit: String)? {
        switch unit {
        case "米", "m":
            return (value * 3.28084, "ft")
        case "厘米", "cm":
            return (value * 0.393701, "in")
        case "毫米", "mm":
            return (value * 0.0393701, "in")
        case "平方米", "m²":
            return (value * 10.7639, "ft²")
        case "立方米", "m³":
            return (value * 35.3147, "ft³")
        case "千克", "公斤", "kg":
            return (value * 2.20462, "lb")
        case "吨", "t":
            return (value * 1.10231, "ton")
        default:
            return nil
        }
    }

    private static func trim(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

enum InputValidator {
    static func nonNegativeNumber(_ text: String) -> Bool {
        guard let value = DataValueParser.decimalValueIfPresent(from: text, requiresEntireString: true) else {
            return false
        }
        return value >= .zero
    }

    static func validate(
        _ text: String,
        kind: NumericInputKind,
        requirement: NumericInputRequirement
    ) -> NumericInputValidation {
        NumericInputSupport.validate(text, kind: kind, requirement: requirement)
    }
}
