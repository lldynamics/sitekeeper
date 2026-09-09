import Foundation

struct CloudBackupContentOptions: Equatable {
    var includeBusinessRecords = true
    var includeProjectRecords = true
    var includeProjectFilesAndNotes = true
    var includeKnowledgeBase = true
    var includeAttachments = true

    static let all = CloudBackupContentOptions()

    var hasSelectedContent: Bool {
        includeBusinessRecords || includeProjectRecords || includeProjectFilesAndNotes || includeKnowledgeBase
    }

    func normalized() -> CloudBackupContentOptions {
        var copy = self
        if !copy.includeProjectRecords {
            copy.includeProjectFilesAndNotes = false
            copy.includeAttachments = false
        }
        if !copy.includeProjectFilesAndNotes {
            copy.includeAttachments = false
        }
        return copy
    }
}

enum CloudBackupAutoInterval: String, CaseIterable {
    case disabled
    case daily
    case every3Days
    case weekly

    var title: String {
        switch self {
        case .disabled:
            return "关闭"
        case .daily:
            return "每天"
        case .every3Days:
            return "每3天"
        case .weekly:
            return "每周"
        }
    }

    var minimumInterval: TimeInterval? {
        switch self {
        case .disabled:
            return nil
        case .daily:
            return 24 * 60 * 60
        case .every3Days:
            return 3 * 24 * 60 * 60
        case .weekly:
            return 7 * 24 * 60 * 60
        }
    }
}

enum CloudBackupRetentionCountOption: Int, CaseIterable, Identifiable {
    case keep3 = 3
    case keep5 = 5
    case keep10 = 10
    case keep20 = 20

    static let defaultValue = keep5.rawValue

    var id: Int { rawValue }

    var title: String {
        String(format: String(localized: "保留最近 %lld 份"), Int64(rawValue))
    }

    static func normalized(_ value: Int) -> Int {
        allCases.first(where: { $0.rawValue == value })?.rawValue ?? defaultValue
    }
}

enum CloudBackupSettingsStore {
    static func loadContentOptions() -> CloudBackupContentOptions {
        CloudBackupContentOptions(
            includeBusinessRecords: UserPreferences.bool(UserPreferenceKeys.cloudBackupIncludeBusinessRecords, default: true),
            includeProjectRecords: UserPreferences.bool(UserPreferenceKeys.cloudBackupIncludeProjectRecords, default: true),
            includeProjectFilesAndNotes: UserPreferences.bool(UserPreferenceKeys.cloudBackupIncludeProjectFilesAndNotes, default: true),
            includeKnowledgeBase: UserPreferences.bool(UserPreferenceKeys.cloudBackupIncludeKnowledgeBase, default: true),
            includeAttachments: UserPreferences.bool(UserPreferenceKeys.cloudBackupIncludeAttachments, default: true)
        ).normalized()
    }

    static func loadAutoInterval() -> CloudBackupAutoInterval {
        let rawValue = UserPreferences.string(UserPreferenceKeys.cloudBackupAutoInterval, default: CloudBackupAutoInterval.disabled.rawValue)
        return StringEnumFallback.value(rawValue, default: .disabled)
    }

    static func loadAutoBackupRequiresWiFi() -> Bool {
        UserPreferences.bool(UserPreferenceKeys.cloudBackupAutoRequiresWiFi, default: false)
    }

    static func loadRetentionCount() -> Int {
        let rawValue = UserPreferences.int(
            UserPreferenceKeys.cloudBackupRetentionCount,
            default: CloudBackupRetentionCountOption.defaultValue
        )
        return CloudBackupRetentionCountOption.normalized(rawValue)
    }

    static func loadLastSuccessDate() -> Date? {
        UserPreferencesStore.shared.unixDate(for: UserPreferenceKeys.cloudBackupLastSuccessAt)
    }

    static func saveLastSuccessDate(_ date: Date) {
        UserPreferencesStore.shared.setUnixDate(date, for: UserPreferenceKeys.cloudBackupLastSuccessAt)
    }

    static func loadPendingFileName() -> String {
        UserPreferences.string(UserPreferenceKeys.cloudBackupPendingFileName, default: "")
    }

    static func savePendingFileName(_ name: String) {
        UserPreferencesStore.shared.set(name, for: UserPreferenceKeys.cloudBackupPendingFileName)
    }

    static func loadAutoLastAttemptDate() -> Date? {
        UserPreferencesStore.shared.unixDate(for: UserPreferenceKeys.cloudBackupAutoLastAttemptAt)
    }

    static func saveAutoLastAttemptDate(_ date: Date) {
        UserPreferencesStore.shared.setUnixDate(date, for: UserPreferenceKeys.cloudBackupAutoLastAttemptAt)
    }

    static func saveAutoLastStatus(_ value: String) {
        UserPreferencesStore.shared.set(value, for: UserPreferenceKeys.cloudBackupAutoLastStatus)
    }
}

enum CloudBackupContentError: LocalizedError {
    case noSelection

    var errorDescription: String? {
        switch self {
        case .noSelection:
            return "请至少选择一类需要备份的内容。"
        }
    }
}

struct CloudBackupExecutionResult {
    let savedFile: CloudBackupFile
    let allBackups: [CloudBackupFile]
}
