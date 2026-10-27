import Foundation

enum StorageCleanupTrashRetentionOption: Int, CaseIterable, Identifiable {
    case days3 = 3
    case days7 = 7
    case days14 = 14
    case days30 = 30

    static let defaultDays = Self.days7.rawValue

    var id: Int { rawValue }
    var days: Int { rawValue }
    var displayName: String {
        String(format: AppLocalization.string("%lld 天"), Int64(rawValue))
    }

    static func normalizedDays(_ days: Int) -> Int {
        allCases.min { lhs, rhs in
            abs(lhs.rawValue - days) < abs(rhs.rawValue - days)
        }?.rawValue ?? defaultDays
    }
}

enum StorageCleanupLargeFileThresholdOption: Int, CaseIterable, Identifiable {
    case mb5 = 5
    case mb20 = 20
    case mb50 = 50
    case mb100 = 100

    static let defaultMegabytes = Self.mb5.rawValue

    var id: Int { rawValue }
    var megabytes: Int { rawValue }
    var bytes: Int { rawValue * 1024 * 1024 }
    var displayName: String { QuickNoteAttachmentStorage.formattedFileSize(bytes) }

    static func bytes(for megabytes: Int) -> Int {
        normalizedMegabytes(megabytes) * 1024 * 1024
    }

    static func normalizedMegabytes(_ megabytes: Int) -> Int {
        allCases.min { lhs, rhs in
            abs(lhs.rawValue - megabytes) < abs(rhs.rawValue - megabytes)
        }?.rawValue ?? defaultMegabytes
    }
}

enum StorageCleanupLargeFileRuleSuggestion {
    case photo
    case video
    case ticket

    var bytes: Int {
        switch self {
        case .photo:
            return 5 * 1024 * 1024
        case .video:
            return 50 * 1024 * 1024
        case .ticket:
            return 20 * 1024 * 1024
        }
    }
}
