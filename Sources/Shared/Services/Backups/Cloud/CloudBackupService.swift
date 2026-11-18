import Foundation

struct CloudBackupFile: Identifiable, Equatable {
    let id: String
    let fileURL: URL
    let fileName: String
    let byteSize: Int
    let modifiedAt: Date
    var uploadState: CloudBackupUploadState = .pending
    var scope: CloudBackupScope?

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
            return AppLocalization.string("未能访问 iCloud。请确认已登录 Apple ID，并在系统设置中允许本 App 使用 iCloud。")
        case .cloudFileNotDownloaded:
            return AppLocalization.string("云端备份仍在从 iCloud 下载，请稍后再试。")
        case .backupNotFound:
            return AppLocalization.string("未找到可恢复的 iCloud 备份。")
        case .invalidBackupFile:
            return AppLocalization.string("iCloud 备份文件无效。")
        }
    }
}

enum CloudBackupService {
    static let containerIdentifier = "iCloud.com.chengjinfang.sitekeeper"
    private static let backupsDirectoryName = "Backups"
    private static let backupFilePrefix = "sitekeeper-cloud-backup"
    private static let backupFileExtension = "zip"
    private static let digestFileExtension = "sha256"

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

    static func makeBackupFileName(date: Date = Date(), scope: CloudBackupScope? = nil) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let scopeComponent = scope.map { "-\($0.rawValue)" } ?? ""
        return "\(backupFilePrefix)-\(formatter.string(from: date))\(scopeComponent)-\(UUID().uuidString).\(backupFileExtension)"
    }

    /// Scope is also recorded in the ZIP manifest. Reading the generated name
    /// lets other devices list and retain cloud placeholders without downloading them.
    static func scope(forBackupFileName name: String) -> CloudBackupScope? {
        let prefix = backupFilePrefix + "-"
        let suffix = "." + backupFileExtension
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let stem = name.dropFirst(prefix.count).dropLast(suffix.count)
        let uuidLength = 36
        guard UUID(uuidString: String(stem.suffix(uuidLength))) != nil,
              stem.dropLast(uuidLength).last == "-" else { return nil }
        let components = stem.dropLast(uuidLength + 1).split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3, components[0].count == 8, components[1].count == 6,
              components[0].allSatisfy(\.isNumber), components[1].allSatisfy(\.isNumber) else { return nil }
        return CloudBackupScope(rawValue: String(components[2]))
    }

    static func listBackups() throws -> [CloudBackupFile] {
        let directory = try backupsDirectoryURL(createIfNeeded: true)
        return try coordinatedRead(at: directory) { coordinatedDirectory in
            let urls = try FileManager.default.contentsOfDirectory(
                at: coordinatedDirectory,
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
    }

    static func saveArchiveToCloud(archiveFileURL: URL) throws -> CloudBackupFile {
        let manifest: BackupArchiveManifest
        do {
            manifest = try BackupArchiveService.validateArchive(at: archiveFileURL)
        } catch {
            recordIssue("cloud_backup.source_validation_failed", fileURL: archiveFileURL, error: error)
            throw CloudBackupError.invalidBackupFile
        }
        let digest: String
        do {
            digest = try BackupArchiveSecurity.sha256Hex(of: archiveFileURL)
        } catch {
            recordIssue("cloud_backup.source_digest_failed", fileURL: archiveFileURL, error: error)
            throw CloudBackupError.invalidBackupFile
        }
        let directory = try backupsDirectoryURL(createIfNeeded: true)
        let targetURL = directory.appendingPathComponent(makeBackupFileName(scope: manifest.scope))
        let digestURL = integritySidecarURL(for: targetURL)
        return try coordinatedWritePair(
            firstURL: targetURL,
            firstOptions: .forReplacing,
            secondURL: digestURL,
            secondOptions: .forReplacing
        ) { coordinatedTargetURL, coordinatedDigestURL in
            try FileOps.replaceByCopyWithRollback(
                from: archiveFileURL,
                to: coordinatedTargetURL,
                context: .init(
                    event: "cloud_backup.save_archive",
                    category: .cloudBackup,
                    source: "CloudBackupService.saveArchiveToCloud"
                )
            )
            do {
                guard try BackupArchiveSecurity.sha256Hex(of: coordinatedTargetURL) == digest else {
                    throw BackupArchiveSecurityError.digestMismatch
                }
                try Data("\(digest)\n".utf8).write(to: coordinatedDigestURL, options: .atomic)
                BackupArchiveSecurity.applyDataProtection(to: coordinatedTargetURL)
                BackupArchiveSecurity.applyDataProtection(to: coordinatedDigestURL)
            } catch {
                try? FileManager.default.removeItem(at: coordinatedTargetURL)
                try? FileManager.default.removeItem(at: coordinatedDigestURL)
                recordIssue("cloud_backup.upload_validation_failed", fileURL: coordinatedTargetURL, error: error)
                throw CloudBackupError.invalidBackupFile
            }
            guard let file = cloudBackupFile(from: coordinatedTargetURL) else {
                throw CloudBackupError.invalidBackupFile
            }
            return file
        }
    }

    static func copyBackupToTemporaryFile(_ file: CloudBackupFile) throws -> URL {
        try ensureCloudFileIsReady(file.fileURL)
        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("icloud-backup-import-\(UUID().uuidString).zip")
        let expectedDigest: String? = try coordinatedRead(at: file.fileURL) { coordinatedSourceURL in
            guard FileManager.default.fileExists(atPath: coordinatedSourceURL.path) else {
                throw CloudBackupError.backupNotFound
            }
            try FileOps.replaceByCopyWithRollback(
                from: coordinatedSourceURL,
                to: targetURL,
                context: .init(
                    event: "cloud_backup.copy_to_temporary",
                    category: .cloudBackup,
                    source: "CloudBackupService.copyBackupToTemporaryFile"
                )
            )
            return try readIntegrityDigest(for: coordinatedSourceURL)
        }
        do {
            try BackupArchiveSecurity.validateRemoteCopy(at: targetURL, expectedSHA256: expectedDigest)
            BackupArchiveSecurity.applyDataProtection(to: targetURL)
            return targetURL
        } catch {
            try? FileManager.default.removeItem(at: targetURL)
            recordIssue("cloud_backup.restore_validation_failed", fileURL: file.fileURL, error: error)
            throw CloudBackupError.invalidBackupFile
        }
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

    /// Refresh completion first; a local copy alone is not proof of cloud availability.
    static func refreshUploadStatusAndPrune(keepMostRecent retainedCount: Int) throws -> [CloudBackupFile] {
        let backups = try listBackups()
        if let confirmed = CloudBackupRetentionPolicy.latestConfirmedDate(backups) {
            if confirmed > (CloudBackupSettingsStore.loadLastSuccessDate() ?? .distantPast) {
                CloudBackupSettingsStore.saveLastSuccessDate(confirmed)
            }
        }
        let pendingName = CloudBackupSettingsStore.loadPendingFileName()
        if !pendingName.isEmpty, backups.contains(where: { $0.fileName == pendingName && $0.uploadState == .uploaded }) {
            CloudBackupSettingsStore.savePendingFileName("")
            CloudBackupSettingsStore.saveAutoLastStatus(CloudBackupUploadState.uploaded.statusMessage)
        }
        let removable = CloudBackupRetentionPolicy.removableBackups(backups, keeping: retainedCount)
        for file in removable {
            do {
                try coordinatedWritePair(
                    firstURL: file.fileURL,
                    firstOptions: .forDeleting,
                    secondURL: integritySidecarURL(for: file.fileURL),
                    secondOptions: .forDeleting
                ) { coordinatedArchiveURL, coordinatedSidecarURL in
                    _ = try FileOps.removeIfExists(
                        at: coordinatedArchiveURL,
                        context: .init(
                            event: "cloud_backup.retention_prune",
                            category: .cloudBackup,
                            source: "CloudBackupService.pruneOldBackups"
                        )
                    )
                    _ = try FileOps.removeIfExists(
                        at: coordinatedSidecarURL,
                        context: .init(
                            event: "cloud_backup.retention_prune_digest",
                            category: .cloudBackup,
                            source: "CloudBackupService.pruneOldBackups"
                        )
                    )
                }
            } catch {
                recordIssue(
                    "cloud_backup.retention_prune_failed",
                    fileURL: file.fileURL,
                    details: ["retentionCount": String(retainedCount)],
                    error: error
                )
            }
        }
        return removable.isEmpty ? backups : try listBackups()
    }

    private static func coordinatedRead<T>(at url: URL, _ body: (URL) throws -> T) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var bodyResult: Result<T, any Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            bodyResult = Result { try body(coordinatedURL) }
        }
        if let bodyResult { return try bodyResult.get() }
        throw coordinatorError ?? CloudBackupError.iCloudUnavailable
    }

    private static func coordinatedWritePair<T>(
        firstURL: URL,
        firstOptions: NSFileCoordinator.WritingOptions,
        secondURL: URL,
        secondOptions: NSFileCoordinator.WritingOptions,
        _ body: (URL, URL) throws -> T
    ) throws -> T {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinatorError: NSError?
        var bodyResult: Result<T, any Error>?
        coordinator.coordinate(
            writingItemAt: firstURL,
            options: firstOptions,
            writingItemAt: secondURL,
            options: secondOptions,
            error: &coordinatorError
        ) { url1, url2 in
            bodyResult = Result { try body(url1, url2) }
        }
        if let bodyResult { return try bodyResult.get() }
        throw coordinatorError ?? CloudBackupError.iCloudUnavailable
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
            modifiedAt: values.contentModificationDate ?? Date.distantPast,
            uploadState: uploadState(for: url),
            scope: scope(forBackupFileName: url.lastPathComponent)
        )
    }

    private static func uploadState(for archiveURL: URL) -> CloudBackupUploadState {
        .evaluate(archive: uploadObservation(for: archiveURL), digest: uploadObservation(for: integritySidecarURL(for: archiveURL)))
    }

    private static func uploadObservation(for url: URL) -> CloudBackupUploadObservation {
        do {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey, .ubiquitousItemUploadingErrorKey])
            return CloudBackupUploadObservation(
                isUploaded: values.ubiquitousItemIsUploaded,
                errorMessage: values.ubiquitousItemUploadingError?.localizedDescription
            )
        } catch {
            // Missing status/sidecar is unconfirmed, never an uploaded backup.
            return CloudBackupUploadObservation(isUploaded: nil)
        }
    }

    private static func integritySidecarURL(for archiveURL: URL) -> URL {
        archiveURL.appendingPathExtension(digestFileExtension)
    }

    private static func readIntegrityDigest(for archiveURL: URL) throws -> String? {
        let sidecarURL = integritySidecarURL(for: archiveURL)
        guard FileManager.default.fileExists(atPath: sidecarURL.path) else { return nil }
        let value = try String(contentsOf: sidecarURL, encoding: .utf8)
        return try BackupArchiveSecurity.normalizedDigest(value)
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
