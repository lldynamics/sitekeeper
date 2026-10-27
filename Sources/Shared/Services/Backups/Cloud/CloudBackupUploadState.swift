import Foundation

enum CloudBackupUploadState: Equatable, Sendable {
    case pending
    case uploaded
    case failed(String)

    var statusMessage: String {
        switch self {
        case .pending:
            AppLocalization.string("备份已在本机生成，等待 iCloud 同步；请刷新查看上传状态。")
        case .uploaded:
            AppLocalization.string("备份已上传到 iCloud。")
        case .failed(let message):
            String(format: AppLocalization.string("iCloud 上传失败：%@。本机备份仍保留，请检查网络和云端空间后刷新。"), message)
        }
    }

    static func evaluate(archive: CloudBackupUploadObservation, digest: CloudBackupUploadObservation) -> Self {
        if let error = archive.errorMessage ?? digest.errorMessage { return .failed(error) }
        return archive.isUploaded == true && digest.isUploaded == true ? .uploaded : .pending
    }
}

struct CloudBackupUploadObservation: Sendable {
    let isUploaded: Bool?
    var errorMessage: String?
}

enum CloudBackupRetentionPolicy {
    static var unconfirmedStatusMessage: String {
        AppLocalization.string("备份上传状态暂时无法确认，已暂停重复自动备份。请刷新列表或重新手动备份。")
    }

    static func automaticBackupBlockReason(in files: [CloudBackupFile], pendingFileName: String) -> String? {
        guard !pendingFileName.isEmpty else { return nil }
        guard let file = files.first(where: { $0.fileName == pendingFileName }) else { return unconfirmedStatusMessage }
        return file.uploadState == .uploaded ? nil : file.uploadState.statusMessage
    }

    static func pendingUpload(in files: [CloudBackupFile], fileName: String) -> CloudBackupFile? {
        files.first { $0.fileName == fileName && $0.uploadState != .uploaded }
    }

    /// Pending/failed uploads never count toward retention and are never deleted here.
    static func removableBackups(_ files: [CloudBackupFile], keeping count: Int) -> [CloudBackupFile] {
        guard count > 0 else { return [] }
        return Array(files.filter { $0.uploadState == .uploaded }
            .sorted { lhs, rhs in
                if lhs.modifiedAt == rhs.modifiedAt { return lhs.fileName > rhs.fileName }
                return lhs.modifiedAt > rhs.modifiedAt
            }.dropFirst(count))
    }

    static func latestConfirmedDate(_ files: [CloudBackupFile]) -> Date? {
        files.filter { $0.uploadState == .uploaded }.map(\.modifiedAt).max()
    }
}
