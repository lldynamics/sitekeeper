import Foundation

struct CloudBackupFile: Identifiable, Equatable {
    let id: String
    let fileURL: URL
    let fileName: String
    let byteSize: Int
    let modifiedAt: Date

    var formattedSize: String {
        QuickNoteAttachmentStorage.formattedFileSize(byteSize)
    }

    var formattedModifiedAt: String {
        Formatters.dateTime.string(from: modifiedAt)
    }
}

enum CloudBackupError: LocalizedError {
    case iCloudUnavailable
    case cloudFileNotDownloaded
    case backupNotFound
    case invalidBackupFile

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "未能访问 iCloud。请确认已登录 Apple ID，并在系统设置中允许本 App 使用 iCloud。"
        case .cloudFileNotDownloaded:
            return "云端备份仍在从 iCloud 下载，请稍后再试。"
        case .backupNotFound:
            return "未找到可恢复的 iCloud 备份。"
        case .invalidBackupFile:
            return "iCloud 备份文件无效。"
        }
    }
}

enum CloudBackupService {
    static let containerIdentifier = "iCloud.com.chengjinfang.sitekeeper"
    private static let backupsDirectoryName = "Backups"
    private static let backupFilePrefix = "sitekeeper-cloud-backup"
    private static let backupFileExtension = "zip"

    static func containerRootURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier)
    }

    static func makeBackupFileName(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(backupFilePrefix)-\(formatter.string(from: date)).\(backupFileExtension)"
    }

    static func latestBackup() throws -> CloudBackupFile? {
        try listBackups().first
    }

    static func listBackups() throws -> [CloudBackupFile] {
        let directory = try backupsDirectoryURL(createIfNeeded: true)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return urls
            .filter { $0.pathExtension.lowercased() == backupFileExtension }
            .compactMap(cloudBackupFile(from:))
            .sorted { lhs, rhs in
                if lhs.modifiedAt == rhs.modifiedAt {
                    return lhs.fileName > rhs.fileName
                }
                return lhs.modifiedAt > rhs.modifiedAt
            }
    }

    static func saveArchiveToCloud(
        archiveFileURL: URL,
        fileName: String = makeBackupFileName(),
        keepMostRecent retainedCount: Int = 5
    ) throws -> CloudBackupFile {
        let directory = try backupsDirectoryURL(createIfNeeded: true)
        let targetURL = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.copyItem(at: archiveFileURL, to: targetURL)
        try pruneOldBackups(keepMostRecent: retainedCount)
        guard let file = cloudBackupFile(from: targetURL) else {
            throw CloudBackupError.invalidBackupFile
        }
        return file
    }

    static func copyBackupToTemporaryFile(_ file: CloudBackupFile) throws -> URL {
        try ensureCloudFileIsReady(file.fileURL)
        guard FileManager.default.fileExists(atPath: file.fileURL.path) else {
            throw CloudBackupError.backupNotFound
        }

        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("icloud-backup-import-\(UUID().uuidString).zip")
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.copyItem(at: file.fileURL, to: targetURL)
        return targetURL
    }

    private static func backupsDirectoryURL(createIfNeeded: Bool) throws -> URL {
        guard let root = containerRootURL() else {
            throw CloudBackupError.iCloudUnavailable
        }
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let directory = documents.appendingPathComponent(backupsDirectoryName, isDirectory: true)
        if createIfNeeded {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private static func pruneOldBackups(keepMostRecent retainedCount: Int) throws {
        guard retainedCount > 0 else { return }
        let backups = try listBackups()
        for file in backups.dropFirst(retainedCount) {
            do {
                try FileManager.default.removeItem(at: file.fileURL)
            } catch {
                StorageIssueLog.record("云备份历史清理失败：\(file.fileURL.lastPathComponent)，\(error.localizedDescription)")
            }
        }
    }

    private static func cloudBackupFile(from url: URL) -> CloudBackupFile? {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
        } catch {
            StorageIssueLog.record("读取云备份元信息失败：\(url.lastPathComponent)，\(error.localizedDescription)")
            return nil
        }
        guard values.isRegularFile != false else {
            return nil
        }
        return CloudBackupFile(
            id: url.lastPathComponent,
            fileURL: url,
            fileName: url.lastPathComponent,
            byteSize: values.fileSize ?? QuickNoteAttachmentStorage.fileSize(at: url),
            modifiedAt: values.contentModificationDate ?? Date.distantPast
        )
    }

    private static func ensureCloudFileIsReady(_ url: URL) throws {
        let values: URLResourceValues?
        do {
            values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        } catch {
            StorageIssueLog.record("读取云端下载状态失败：\(url.lastPathComponent)，\(error.localizedDescription)")
            values = nil
        }
        if let status = values?.ubiquitousItemDownloadingStatus,
           status != .current {
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            } catch {
                StorageIssueLog.record("触发云备份下载失败：\(url.lastPathComponent)，\(error.localizedDescription)")
            }
            throw CloudBackupError.cloudFileNotDownloaded
        }
    }
}
