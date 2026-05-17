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
            return String(localized: "未能访问 iCloud。请确认已登录 Apple ID，并在系统设置中允许本 App 使用 iCloud。")
        case .cloudFileNotDownloaded:
            return String(localized: "云端备份仍在从 iCloud 下载，请稍后再试。")
        case .backupNotFound:
            return String(localized: "未找到可恢复的 iCloud 备份。")
        case .invalidBackupFile:
            return String(localized: "iCloud 备份文件无效。")
        }
    }
}

enum CloudBackupService {
    static let containerIdentifier = "iCloud.com.chengjinfang.sitekeeper"
    private static let backupsDirectoryName = "Backups"
    private static let backupFilePrefix = "sitekeeper-cloud-backup"
    private static let backupFileExtension = "zip"

    private static func recordIssue(
        _ event: String,
        fileURL: URL? = nil,
        details: [String: String] = [:],
        error: Error? = nil
    ) {
        var payload = details
        if let fileURL {
            payload["file"] = fileURL.lastPathComponent
        }
        StorageIssueLog.recordEvent(
            event,
            category: .cloudBackup,
            details: payload,
            error: error
        )
    }

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
        try FileOps.replaceByCopyWithRollback(
            from: archiveFileURL,
            to: targetURL,
            context: .init(
                event: "cloud_backup.save_archive",
                category: .cloudBackup,
                source: "CloudBackupService.saveArchiveToCloud"
            )
        )
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
        try FileOps.replaceByCopyWithRollback(
            from: file.fileURL,
            to: targetURL,
            context: .init(
                event: "cloud_backup.copy_to_temporary",
                category: .cloudBackup,
                source: "CloudBackupService.copyBackupToTemporaryFile"
            )
        )
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
                _ = try FileOps.removeIfExists(
                    at: file.fileURL,
                    context: .init(
                        event: "cloud_backup.retention_prune",
                        category: .cloudBackup,
                        source: "CloudBackupService.pruneOldBackups"
                    )
                )
            } catch {
                recordIssue(
                    "cloud_backup.retention_prune_failed",
                    fileURL: file.fileURL,
                    details: ["retentionCount": String(retainedCount)],
                    error: error
                )
            }
        }
    }

    private static func cloudBackupFile(from url: URL) -> CloudBackupFile? {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey])
        } catch {
            recordIssue("cloud_backup.metadata_read_failed", fileURL: url, error: error)
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
            recordIssue("cloud_backup.download_status_read_failed", fileURL: url, error: error)
            values = nil
        }
        if let status = values?.ubiquitousItemDownloadingStatus,
           status != .current {
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            } catch {
                recordIssue("cloud_backup.download_start_failed", fileURL: url, error: error)
            }
            throw CloudBackupError.cloudFileNotDownloaded
        }
    }
}
