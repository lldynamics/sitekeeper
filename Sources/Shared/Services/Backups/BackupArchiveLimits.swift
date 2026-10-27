import Foundation

/// Shared export/streaming-import contract, independent of single-attachment imports.
struct BackupArchiveLimits: Sendable {
    let maximumEntryBytes: UInt64
    let maximumTotalBytes: UInt64
    let maximumEntryCount: Int
    var maximumMetadataBytes: UInt64 = 128 * 1024 * 1024

    static let backup = BackupArchiveLimits(
        maximumEntryBytes: 1024 * 1024 * 1024,
        maximumTotalBytes: 32 * 1024 * 1024 * 1024,
        maximumEntryCount: 100_000
    )

    /// Legacy APIs return all decoded bytes in memory; keep their smaller budget.
    static var inMemory: BackupArchiveLimits {
        let bytes = UInt64(max(TransferLimitPolicy.maxImportBytes, 1))
        return BackupArchiveLimits(maximumEntryBytes: bytes, maximumTotalBytes: bytes, maximumEntryCount: 20_000)
    }

    func validate(path: String, size: UInt64, entryCount: Int, total: inout UInt64) throws {
        guard entryCount <= maximumEntryCount else {
            throw SimpleZipArchiveReader.ZipReadError.limitExceeded("文件数量过多")
        }
        let entryLimit: UInt64
        switch path {
        case BackupArchiveService.metadataPath:
            entryLimit = min(maximumEntryBytes, maximumMetadataBytes)
        case BackupArchiveService.manifestPath:
            entryLimit = min(maximumEntryBytes, 1024 * 1024)
        default:
            entryLimit = maximumEntryBytes
        }
        guard size <= entryLimit else {
            throw SimpleZipArchiveReader.ZipReadError.limitExceeded(path)
        }
        let (newTotal, overflow) = total.addingReportingOverflow(size)
        guard !overflow, newTotal <= maximumTotalBytes else {
            throw SimpleZipArchiveReader.ZipReadError.limitExceeded("解压后总大小过大")
        }
        total = newTotal
    }
}
