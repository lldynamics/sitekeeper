import Foundation

enum UserPreferenceKeys {
    static let useMetric = "useMetric"
    static let autoSave = "autoSave"
    static let darkMode = "darkMode"
    static let appearanceMode = "appearanceMode"
    static let favoriteCalculators = "favoriteCalculators"
    static let companyName = "companyName"
    static let companyPhone = "companyPhone"
    static let companyAddress = "companyAddress"
    static let quoteValidityDays = "quoteValidityDays"
    static let didCompleteOnboarding = "didCompleteOnboarding"
    static let completedOnboardingVersion = "onboarding.completedVersion"
    static let hasSeenBackupGuide = "guide.backup.hasSeen"
    static let hasSeenProjectFileRootGuide = "guide.projectFile.root.hasSeen"
    static let hasSeenProjectFileCategoryGuide = "guide.projectFile.category.hasSeen"
    static let hasCompletedBackupExportTask = "task.backup.firstExportCompleted"
    static let languageCode = "languageCode"
    static let cloudBackupIncludeBusinessRecords = "cloudBackup.includeBusinessRecords"
    static let cloudBackupIncludeProjectRecords = "cloudBackup.includeProjectRecords"
    static let cloudBackupIncludeProjectFilesAndNotes = "cloudBackup.includeProjectFilesAndNotes"
    static let cloudBackupIncludeKnowledgeBase = "cloudBackup.includeKnowledgeBase"
    static let cloudBackupIncludeAttachments = "cloudBackup.includeAttachments"
    static let cloudBackupAutoInterval = "cloudBackup.autoInterval"
    static let cloudBackupAutoRequiresWiFi = "cloudBackup.autoRequiresWiFi"
    static let cloudBackupLastSuccessAt = "cloudBackup.lastSuccessAt"
    static let cloudBackupAutoLastAttemptAt = "cloudBackup.autoLastAttemptAt"
    static let cloudBackupAutoLastStatus = "cloudBackup.autoLastStatus"
    static let userName = "userName"
    static let cadPreviewEngine = "cad.preview.engine"
    static let showTemplates = "feature.showTemplates"
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
    case chinese = "zh-Hans"
    case english = "en"

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    var appleLanguageCode: String {
        rawValue
    }

    static var current: AppLanguage {
        let stored = UserDefaults.standard.string(forKey: UserPreferenceKeys.languageCode) ?? ""
        return StringEnumFallback.value(stored, default: .chinese)
    }

    static func apply(_ language: AppLanguage) {
        UserDefaults.standard.set([language.appleLanguageCode], forKey: "AppleLanguages")
        UserDefaults.standard.set(language.rawValue, forKey: UserPreferenceKeys.languageCode)
    }

    static func restoreFromStorage() {
        let stored = UserDefaults.standard.string(forKey: UserPreferenceKeys.languageCode) ?? ""
        let lang = StringEnumFallback.value(stored, default: AppLanguage.chinese)
        UserDefaults.standard.set([lang.appleLanguageCode], forKey: "AppleLanguages")
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
}

enum AppPolicy {
    static let privacyPolicyLastUpdated = "2026年5月9日"
}

enum AppFeatureFlags {
    static var allowsSampleDataImport: Bool {
        TransferLimitPolicy.allowsSampleDataImport
    }

    static var showTemplates: Bool {
        UserPreferences.bool(UserPreferenceKeys.showTemplates, default: false)
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
        guard let numeric = Double(quantity.replacingOccurrences(of: ",", with: ".")) else {
            return "\(quantity) \(translatedUnit(unit, useMetric: useMetric))"
        }
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
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")) else { return false }
        return value >= 0
    }
}
