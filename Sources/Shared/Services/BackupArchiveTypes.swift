import Foundation

private enum BackupArchiveDataCache {
    static let storage = NSCache<NSString, NSData>()
}

func recordBackupArchiveIssue(
    _ event: String,
    fileName: String? = nil,
    path: String? = nil,
    type: String? = nil,
    details: [String: String] = [:],
    error: Error? = nil
) {
    var payload = details
    if let fileName, !fileName.isEmpty {
        payload["file"] = fileName
    }
    if let path, !path.isEmpty {
        payload["path"] = path
    }
    if let type, !type.isEmpty {
        payload["type"] = type
    }
    StorageIssueLog.recordEvent(
        event,
        category: .zipArchive,
        details: payload,
        error: error
    )
}

struct BackupArchive {
    let fileURL: URL
    let includedFileCount: Int
    let missingFiles: [String]
    let metadataBytes: Int
    let rawFilesBytes: Int

    var totalBytes: Int { QuickNoteAttachmentStorage.fileSize(at: fileURL) }

    // 兼容旧调用：需要内存数据时按需读取。
    @available(*, deprecated, message: "请优先使用 fileURL 流式读取，避免整包加载到内存。")
    var data: Data {
        let cacheKey = fileURL.path as NSString
        if let cached = BackupArchiveDataCache.storage.object(forKey: cacheKey) {
            return Data(referencing: cached)
        }
        do {
            let loaded = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            BackupArchiveDataCache.storage.setObject(loaded as NSData, forKey: cacheKey)
            return loaded
        } catch {
            recordBackupArchiveIssue(
                "backup.archive.data_read_failed",
                fileName: fileURL.lastPathComponent,
                error: error
            )
            return Data()
        }
    }

    func loadData() async -> Data {
        let cacheKey = fileURL.path as NSString
        if let cached = BackupArchiveDataCache.storage.object(forKey: cacheKey) {
            return Data(referencing: cached)
        }
        return await Task.detached(priority: .utility) {
            do {
                let loaded = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                BackupArchiveDataCache.storage.setObject(loaded as NSData, forKey: cacheKey)
                return loaded
            } catch {
                recordBackupArchiveIssue(
                    "backup.archive.async_data_read_failed",
                    fileName: fileURL.lastPathComponent,
                    error: error
                )
                return Data()
            }
        }.value
    }
}

struct BackupArchiveEstimate {
    let metadataBytes: Int
    let rawFilesBytes: Int
    let missingFiles: [String]

    var estimatedBytes: Int { metadataBytes + rawFilesBytes }
}

struct BackupArchiveProgress {
    let completedSteps: Int
    let totalSteps: Int
    let currentItem: String

    var fractionCompleted: Double {
        guard totalSteps > 0 else { return 0 }
        return min(max(Double(completedSteps) / Double(totalSteps), 0), 1)
    }
}

struct BackupImportProgress {
    let completedBytes: Int64
    let totalBytes: Int64
    let currentItem: String

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }
}

struct BackupFileImpactSummary: Equatable {
    let photoFileNames: [String]
    let drawingFileNames: [String]
    let documentFileNames: [String]
    let quickNoteAttachmentFileNames: [String]

    init(
        photoFileNames: [String] = [],
        drawingFileNames: [String] = [],
        documentFileNames: [String] = [],
        quickNoteAttachmentFileNames: [String] = []
    ) {
        self.photoFileNames = Self.normalized(photoFileNames)
        self.drawingFileNames = Self.normalized(drawingFileNames)
        self.documentFileNames = Self.normalized(documentFileNames)
        self.quickNoteAttachmentFileNames = Self.normalized(quickNoteAttachmentFileNames)
    }

    var photoFileCount: Int { photoFileNames.count }
    var drawingFileCount: Int { drawingFileNames.count }
    var documentFileCount: Int { documentFileNames.count }
    var quickNoteAttachmentFileCount: Int { quickNoteAttachmentFileNames.count }

    var totalCount: Int {
        photoFileCount + drawingFileCount + documentFileCount + quickNoteAttachmentFileCount
    }

    var isEmpty: Bool { totalCount == 0 }

    private static func normalized(_ fileNames: [String]) -> [String] {
        Array(Set(fileNames.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

struct BackupImportPreview {
    let snapshot: BackupSnapshot
    let manifest: BackupArchiveManifest
    let incomingFiles: BackupFileImpactSummary
    let overwrittenLocalFiles: BackupFileImpactSummary

    var photoFileCount: Int { incomingFiles.photoFileCount }
    var drawingFileCount: Int { incomingFiles.drawingFileCount }
    var documentFileCount: Int { incomingFiles.documentFileCount }
    var quickNoteAttachmentFileCount: Int { incomingFiles.quickNoteAttachmentFileCount }
}

struct BackupEmbeddedRestoreCounts {
    var photoFileCount = 0
    var drawingFileCount = 0
    var documentFileCount = 0
    var quickNoteAttachmentFileCount = 0

    var totalCount: Int {
        photoFileCount + drawingFileCount + documentFileCount + quickNoteAttachmentFileCount
    }
}

enum BackupArchiveError: LocalizedError {
    case encodingFailed
    case missingMetadata
    case missingManifest
    case invalidBackup
    case unsupportedSchemaVersion(Int)
    case restoreFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return String(localized: "备份数据编码失败。")
        case .missingMetadata:
            return String(localized: "备份 ZIP 缺少数据索引。")
        case .missingManifest:
            return String(localized: "备份 ZIP 缺少清单文件。")
        case .invalidBackup:
            return String(localized: "备份文件格式不正确。")
        case .unsupportedSchemaVersion(let version):
            return String(
                format: String(localized: "备份格式版本不受支持（schema %lld），请使用当前版本重新导出后再导入。"),
                Int64(version)
            )
        case .restoreFailed(let reason):
            return reason
        case .cancelled:
            return String(localized: "已取消备份导出。")
        }
    }
}
