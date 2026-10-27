import Foundation

enum TransferLimitProfile: String, CaseIterable {
    case production
    case staging
    case development

    fileprivate static func parse(_ raw: String?) -> TransferLimitProfile? {
        guard let normalized = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !normalized.isEmpty else {
            return nil
        }
        switch normalized {
        case "production", "prod", "release", "生产":
            return .production
        case "staging", "stage", "pre", "预发":
            return .staging
        case "development", "dev", "debug", "local", "开发":
            return .development
        default:
            return nil
        }
    }
}

struct TransferLimitSet: Equatable {
    let maxImportBytes: Int
    let backupArchiveWarningBytes: Int
    let projectPackageWarningBytes: Int
}

enum TransferLimitPolicy {
    static let profileEnvironmentKey = "SITEKEEPER_LIMIT_PROFILE"
    static let profileUserDefaultsKey = UserPreferenceKeys.transferLimitProfile

    static var activeProfile: TransferLimitProfile {
        let preferenceStore = UserPreferencesStore.shared
        return resolveProfile(
            userDefaultRaw: preferenceStore.string(
                profileUserDefaultsKey,
                default: "",
                trimWhitespace: false
            ),
            environmentRaw: ProcessInfo.processInfo.environment[profileEnvironmentKey]
        )
    }

    static var limits: TransferLimitSet {
        limits(for: activeProfile)
    }

    static var maxImportBytes: Int { limits.maxImportBytes }
    static var backupArchiveWarningBytes: Int { limits.backupArchiveWarningBytes }
    static var projectPackageWarningBytes: Int { limits.projectPackageWarningBytes }
    static var allowsSampleDataImport: Bool { allowsSampleDataImport(for: activeProfile) }

    static func setRuntimeProfileOverride(_ profile: TransferLimitProfile?) {
        let preferenceStore = UserPreferencesStore.shared
        if let profile {
            preferenceStore.set(profile.rawValue, for: profileUserDefaultsKey)
        } else {
            preferenceStore.removeObject(for: profileUserDefaultsKey)
        }
    }

    static func resolveProfile(userDefaultRaw: String?, environmentRaw: String?) -> TransferLimitProfile {
        if let profile = TransferLimitProfile.parse(userDefaultRaw) {
            return profile
        }
        if let profile = TransferLimitProfile.parse(environmentRaw) {
            return profile
        }
        return .production
    }

    static func limits(for profile: TransferLimitProfile) -> TransferLimitSet {
        switch profile {
        case .production:
            return TransferLimitSet(
                maxImportBytes: 500 * 1024 * 1024,
                backupArchiveWarningBytes: 1024 * 1024 * 1024,
                projectPackageWarningBytes: 1024 * 1024 * 1024
            )
        case .staging:
            return TransferLimitSet(
                maxImportBytes: 700 * 1024 * 1024,
                backupArchiveWarningBytes: 1024 * 1024 * 1024,
                projectPackageWarningBytes: 1024 * 1024 * 1024
            )
        case .development:
            return TransferLimitSet(
                maxImportBytes: 1024 * 1024 * 1024,
                backupArchiveWarningBytes: 1024 * 1024 * 1024,
                projectPackageWarningBytes: 1024 * 1024 * 1024
            )
        }
    }

    static func allowsSampleDataImport(for profile: TransferLimitProfile) -> Bool {
        profile != .production
    }

    static func formattedBytes(_ bytes: Int) -> String {
        QuickNoteAttachmentStorage.formattedFileSize(bytes)
    }

    static func genericTooLargeMessage(itemName: String, size: Int, limit: Int = maxImportBytes) -> String {
        "\(itemName)过大（\(formattedBytes(size))），请控制在 \(formattedBytes(limit)) 内。"
    }

    static func fileTooLargeMessage(fileName: String, size: Int, limit: Int = maxImportBytes) -> String {
        "\(fileName)（文件过大：\(formattedBytes(size))，上限 \(formattedBytes(limit))）"
    }
}

enum ImportLimitPolicy {
    static var maxImportBytes: Int { TransferLimitPolicy.maxImportBytes }

    static func formattedBytes(_ bytes: Int) -> String {
        TransferLimitPolicy.formattedBytes(bytes)
    }

    static func genericTooLargeMessage(itemName: String, size: Int, limit: Int = maxImportBytes) -> String {
        TransferLimitPolicy.genericTooLargeMessage(itemName: itemName, size: size, limit: limit)
    }

    static func fileTooLargeMessage(fileName: String, size: Int, limit: Int = maxImportBytes) -> String {
        TransferLimitPolicy.fileTooLargeMessage(fileName: fileName, size: size, limit: limit)
    }
}
